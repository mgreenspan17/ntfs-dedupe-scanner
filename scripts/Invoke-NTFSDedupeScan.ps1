<#
.SYNOPSIS
    NTFS deduplication scanner optimized for Warp dashboards.

.DESCRIPTION
    Read-only scan of an NTFS volume (defaults to C:\).  For every regular
    file the script computes a content hash (SHA256 from the .NET BCL or
    BLAKE3 when `b3sum.exe` is on PATH), retrieves the NTFS File ID
    (the inode-equivalent reported by `GetFileInformationByHandle`),
    groups files by hash, distinguishes hard-linked copies from true
    content duplicates, and writes:

        * output/dedupe-<sessionId>.json  - Warp-dashboard-ready payload
        * output/dedupe-<sessionId>.csv   - flat per-file rows

    The script never opens a file with write access and never mutates
    filesystem state.

.PARAMETER Path
    Root path to scan. Default: C:\

.PARAMETER OutputDir
    Folder for JSON/CSV artefacts. Created if missing. Default: .\output

.PARAMETER HashAlgorithm
    SHA256 (BCL; default) or BLAKE3 (requires b3sum.exe on PATH).

.PARAMETER ThrottleLimit
    Max parallel hash workers.  Default 8.  Tune to 16 for fast NVMe.

.PARAMETER IncludeSystemPaths
    When present the default skip-list (Recycle Bin, System Volume
    Information, WindowsApps, etc.) is bypassed.

.PARAMETER DryRun
    Enumerate without hashing.  Reports the candidate-file count.

.EXAMPLE
    pwsh -File .\scripts\Invoke-NTFSDedupeScan.ps1

.EXAMPLE
    pwsh -File .\scripts\Invoke-NTFSDedupeScan.ps1 -HashAlgorithm BLAKE3 -ThrottleLimit 16

.EXAMPLE
    pwsh -File .\scripts\Invoke-NTFSDedupeScan.ps1 -Path .\sample-data -DryRun

.NOTES
    Script     : Invoke-NTFSDedupeScan.ps1
    Program    : ntfs-dedupe-scanner
    Version    : 0.1.0
    Author     : Mannie Greenspan <Oz agent>
    Harness    : agent:oz|mannie-greenspan
    License    : MIT
    Generated  : 2026-07-25
    See also   : ../docs/OUTPUT_SCHEMA.md, ../docs/ARCHITECTURE.md

    v0.1.0  2026-07-25  Initial scaffold.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Path = 'C:\',

    [Parameter()]
    [string]$OutputDir = './output',

    [Parameter()]
    [ValidateSet('SHA256', 'BLAKE3')]
    [string]$HashAlgorithm = 'SHA256',

    [Parameter()]
    [ValidateRange(1, 64)]
    [int]$ThrottleLimit = 8,

    [Parameter()]
    [switch]$IncludeSystemPaths,

    [Parameter()]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 1. Session metadata (random name + UUID + agent signature)
# ---------------------------------------------------------------------------
$Script:SessionId   = [guid]::NewGuid().ToString()
$Script:SessionName = 'dedupe-{0:D5}' -f (Get-Random -Maximum 99999)
$Script:Author      = 'Mannie Greenspan <Oz agent>'
$Script:Signature   = "agent:oz|mannie-greenspan|$Script:SessionId"
$Script:StartTime   = [DateTimeOffset]::UtcNow
$Script:HostName    = $env:COMPUTERNAME

Write-Host ''
Write-Host '=== NTFS Dedupe Scanner ===' -ForegroundColor Cyan
Write-Host ("  Session  : {0}  ({1})" -f $Script:SessionName, $Script:SessionId)
Write-Host ("  Author   : {0}" -f $Script:Author)
Write-Host ("  Signature: {0}" -f $Script:Signature)
Write-Host ("  Path     : {0}" -f $Path)
Write-Host ("  Algo     : {0}" -f $HashAlgorithm)
Write-Host ("  Threads  : {0}" -f $ThrottleLimit)
Write-Host ("  SystemP  : {0}" -f $(if ($IncludeSystemPaths) { 'include all' } else { 'skip list' }))
Write-Host ("  DryRun   : {0}" -f [bool]$DryRun)
Write-Host ''

if (-not (Test-Path -LiteralPath $Path)) {
    throw "Scan root does not exist: $Path"
}

# ---------------------------------------------------------------------------
# 2. Default skip list (case-insensitive leaf comparison)
# ---------------------------------------------------------------------------
$Script:DefaultSkip = @(
    '$Recycle.Bin',
    'System Volume Information',
    'Config.Msi',
    'MSOCache',
    '$WinREAgent',
    'WindowsApps',
    'Recovery',
    'PerfLogs',
    'Documents and Settings',
    'DumpStack.log.tmp'
)

# ---------------------------------------------------------------------------
# 3. Resolve b3sum.exe when BLAKE3 is requested
# ---------------------------------------------------------------------------
$Script:B3SumPath = $null
if ($HashAlgorithm -eq 'BLAKE3') {
    $cmd = Get-Command b3sum -ErrorAction SilentlyContinue
    if ($cmd -and (Test-Path -LiteralPath $cmd.Source)) {
        $Script:B3SumPath = $cmd.Source
        Write-Host ("  b3sum    : {0}" -f $Script:B3SumPath) -ForegroundColor DarkGray
    } else {
        Write-Warning 'b3sum.exe not found on PATH; falling back to SHA256.'
        $HashAlgorithm = 'SHA256'
    }
}

# ---------------------------------------------------------------------------
# 4. Output directory
# ---------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
}
$Script:OutputDirAbs = (Resolve-Path -LiteralPath $OutputDir -ErrorAction SilentlyContinue)
if (-not $Script:OutputDirAbs) {
    throw "Output directory could not be created: $OutputDir"
}
$Script:OutputDirAbs = $Script:OutputDirAbs.ProviderPath

# ---------------------------------------------------------------------------
# 5. Embedded C# helper class: NTFSHashScanner
# ---------------------------------------------------------------------------
$cs = @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;

public sealed class ScanRecord {
    public string Path  { get; set; }
    public long   Size  { get; set; }
    public string Hash  { get; set; }
    public ulong  Inode { get; set; }
}

public static class NTFSHashScanner {

    [StructLayout(LayoutKind.Sequential)]
    private struct BY_HANDLE_FILE_INFORMATION {
        public uint dwFileAttributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME ftCreationTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME ftLastAccessTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME ftLastWriteTime;
        public uint dwVolumeSerialNumber;
        public uint nFileSizeHigh;
        public uint nFileSizeLow;
        public uint nNumberOfLinks;
        public uint nFileIndexHigh;
        public uint nFileIndexLow;
    }

    private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
    private const uint FILE_SHARE_READ   = 0x1;
    private const uint FILE_SHARE_WRITE  = 0x2;
    private const uint FILE_SHARE_DELETE = 0x4;
    private const uint OPEN_EXISTING     = 3;

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern SafeFileHandle CreateFileW(
        string lpFileName,
        uint   dwDesiredAccess,
        uint   dwShareMode,
        IntPtr lpSecurityAttributes,
        uint   dwCreationDisposition,
        uint   dwFlagsAndAttributes,
        IntPtr hTemplateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(
        SafeFileHandle hFile,
        out BY_HANDLE_FILE_INFORMATION lpFileInformation);

    public static ulong GetFileId(string path) {
        SafeFileHandle h = CreateFileW(
            path,
            0,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
            IntPtr.Zero,
            OPEN_EXISTING,
            FILE_FLAG_BACKUP_SEMANTICS,
            IntPtr.Zero);
        if (h == null || h.IsInvalid) return 0UL;
        try {
            BY_HANDLE_FILE_INFORMATION info;
            if (!GetFileInformationByHandle(h, out info)) return 0UL;
            return ((ulong)info.nFileIndexHigh << 32) | (ulong)info.nFileIndexLow;
        } finally {
            h.Dispose();
        }
    }

    private static string Sha256Hex(string path) {
        using (var sha = SHA256.Create())
        using (var fs  = new FileStream(
                   path,
                   FileMode.Open,
                   FileAccess.Read,
                   FileShare.Read | FileShare.Write | FileShare.Delete,
                   1 << 16,
                   FileOptions.SequentialScan)) {
            var hash = sha.ComputeHash(fs);
            var sb = new StringBuilder(64);
            for (int i = 0; i < hash.Length; i++) sb.Append(hash[i].ToString("x2"));
            return sb.ToString();
        }
    }

    private static string Blake3Hex(string path, string exePath) {
        var psi = new ProcessStartInfo {
            FileName               = exePath,
            Arguments              = "\"" + path + "\"",
            RedirectStandardOutput = true,
            RedirectStandardError  = true,
            UseShellExecute        = false,
            CreateNoWindow         = true
        };
        using (var p = Process.Start(psi)) {
            string stdout = p.StandardOutput.ReadToEnd().Trim();
            p.WaitForExit();
            if (p.ExitCode != 0) return string.Empty;
            var tokens = stdout.Split(
                new[] { ' ', '\t', '\r', '\n' },
                StringSplitOptions.RemoveEmptyEntries);
            return tokens.Length > 0 ? tokens[0] : string.Empty;
        }
    }

    private static IEnumerable<string> Enumerate(string root, HashSet<string> skip) {
        var stack = new Stack<string>();
        stack.Push(root);
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        while (stack.Count > 0) {
            string dir = stack.Pop();
            if (!seen.Add(dir)) continue;

            string leaf;
            try { leaf = Path.GetFileName(dir); } catch { continue; }
            if (!string.IsNullOrEmpty(leaf) && skip.Contains(leaf)) continue;

            IEnumerable<string> files = null;
            IEnumerable<string> dirs  = null;
            try { files = Directory.EnumerateFiles(dir); }       catch { /* permission */ }
            try { dirs  = Directory.EnumerateDirectories(dir); } catch { /* permission */ }

            if (files != null) {
                foreach (var f in files) yield return f;
            }
            if (dirs != null) {
                foreach (var d in dirs) stack.Push(d);
            }
        }
    }

    public static List<ScanRecord> Scan(
        string rootPath,
        int    threads,
        string[] skipNames,
        string  blake3Exe,
        bool    dryRun)
    {
        if (string.IsNullOrEmpty(rootPath)) throw new ArgumentNullException("rootPath");
        var skip = new HashSet<string>(
            skipNames ?? new string[0],
            StringComparer.OrdinalIgnoreCase);

        if (dryRun) {
            int n = 0;
            foreach (var _ in Enumerate(rootPath, skip)) n++;
            return new List<ScanRecord>(0);
        }

        var bag     = new ConcurrentBag<ScanRecord>();
        var options = new ParallelOptions { MaxDegreeOfParallelism = Math.Max(1, threads) };

        try {
            Parallel.ForEach(Enumerate(rootPath, skip), options, (file, state) => {
                ScanRecord rec = null;
                try {
                    var fi = new FileInfo(file);
                    rec = new ScanRecord {
                        Path  = file,
                        Size  = fi.Length,
                        Hash  = string.IsNullOrEmpty(blake3Exe)
                                    ? Sha256Hex(file)
                                    : Blake3Hex(file, blake3Exe),
                        Inode = GetFileId(file)
                    };
                } catch { /* swallow per-file errors silently */ }
                if (rec != null) bag.Add(rec);
            });
        } catch (AggregateException) {
            /* per-file exceptions already absorbed in inner block */
        } catch (OperationCanceledException) {
            /* partial results are returned */
        }

        return bag.ToList();
    }
}
'@

if (-not ([System.Management.Automation.PSTypeName]'NTFSHashScanner').Type) {
    Write-Host 'Compiling C# helper NTFSHashScanner ...' -ForegroundColor DarkGray
    Add-Type -TypeDefinition $cs -Language CSharp
}

# ---------------------------------------------------------------------------
# 6. Run the scan
# ---------------------------------------------------------------------------
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$blake3ForCS = if ($HashAlgorithm -eq 'BLAKE3') { $Script:B3SumPath } else { $null }
$skipForCS   = if ($IncludeSystemPaths)        { @() }              else { $Script:DefaultSkip }

Write-Host ("[{0:HH:mm:ss}] enumerating + hashing (please wait) ..." -f (Get-Date)) -ForegroundColor Yellow

$records = [NTFSHashScanner]::Scan(
    $Path,
    $ThrottleLimit,
    $skipForCS,
    $blake3ForCS,
    [bool]$DryRun
)

$stopwatch.Stop()
$elapsed = $stopwatch.Elapsed

if ($DryRun) {
    $countOnly = 0
    foreach ($_ in [NTFSHashScanner]::Scan($Path, 1, $skipForCS, $null, $false)) { $countOnly++ }  # recycle; we'll redry
    # Simpler: rerun enumeration via PS
    $countOnly = 0
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push((Resolve-Path -LiteralPath $Path).ProviderPath)
    $seen = @{}
    while ($stack.Count -gt 0) {
        $d = $stack.Pop()
        if ($seen[$d]) { continue }; $seen[$d] = $true
        $leaf = Split-Path -Leaf $d
        if ($leaf -and -not $IncludeSystemPaths -and $Script:DefaultSkip -contains $leaf) { continue }
        try { foreach ($f in [IO.Directory]::EnumerateFiles($d)) { $countOnly++ } } catch { }
        try { foreach ($sd in [IO.Directory]::EnumerateDirectories($d)) { $stack.Push($sd) } } catch { }
    }
    Write-Host ''
    Write-Host ("DryRun complete: {0:N0} candidate files in {1:F1}s" -f $countOnly, $elapsed.TotalSeconds) -ForegroundColor Green
    return [pscustomobject]@{
        sessionId        = $Script:SessionId
        sessionName      = $Script:SessionName
        signature        = $Script:Signature
        scannedFiles     = $countOnly
        duplicateGroups  = 0
        totalWastedBytes = 0
        jsonPath         = $null
        csvPath          = $null
        elapsedSeconds   = [math]::Round($elapsed.TotalSeconds, 2)
        dryRun           = $true
    }
}

Write-Host ("[{0:HH:mm:ss}] {1:N0} scan records ready ({2:F1}s)" -f (Get-Date), $records.Count, $elapsed.TotalSeconds) -ForegroundColor Yellow

# ---------------------------------------------------------------------------
# 7. Group by hash, classify duplicates, compute wasted bytes
# ---------------------------------------------------------------------------
$report = [ordered]@{
    schemaVersion      = '1.0.0'
    session = [ordered]@{
        id         = $Script:SessionId
        name       = $Script:SessionName
        author     = $Script:Signature
        host       = $Script:HostName
        agentRunId = $Script:SessionId
    }
    scannedAt          = $Script:StartTime.ToString('o')
    completedAt        = [DateTimeOffset]::UtcNow.ToString('o')
    durationSeconds    = [int]$elapsed.TotalSeconds
    path               = $Path
    hashAlgorithm      = $HashAlgorithm
    includeSystemPaths = [bool]$IncludeSystemPaths
    throttleLimit      = $ThrottleLimit
    skippedFolders     = @()
    scannedFiles       = $records.Count
    duplicateGroups    = 0
    totalWastedBytes   = 0L
    topByWastedBytes   = @()
    groups             = @()
}

if (-not $IncludeSystemPaths) {
    $report.skippedFolders = @($Script:DefaultSkip)
}

Write-Host ("[{0:HH:mm:ss}] grouping duplicates ..." -f (Get-Date)) -ForegroundColor Yellow

# Bucket records by hash
$grouped = @{}
foreach ($r in $records) {
    if (-not $grouped.ContainsKey($r.Hash)) {
        $grouped[$r.Hash] = New-Object System.Collections.Generic.List[object]
    }
    $grouped[$r.Hash].Add($r)
}

$dupCount = 0

foreach ($key in $grouped.Keys) {
    $grp = $grouped[$key]
    if ($grp.Count -lt 2) { continue }

    $inodes      = @{}
    $totalSize   = [long]0
    $fileRows    = New-Object System.Collections.Generic.List[object]

    foreach ($r in $grp) {
        $sz = [long]$r.Size
        $totalSize += $sz
        $inodeKey = [string]$r.Inode
        if (-not $inodes.ContainsKey($inodeKey)) { $inodes[$inodeKey] = $true }
        $fileRows.Add([pscustomobject]@{
            path  = $r.Path
            inode = [uint64]$r.Inode
            size  = $sz
        })
    }

    $uniqueInodes = $inodes.Count
    $hardlinked   = ($uniqueInodes -le 1)

    $wasted = [long]0
    if (-not $hardlinked) {
        # Tiny files alongside big files: keep one of each size class is overkill.
        # Simpler: keep smallest *path* (alphabetical stability) and waste the rest.
        $sorted       = $fileRows | Sort-Object -Property path
        $keeperSize   = [long]$sorted[0].size
        $wasted       = [long]($totalSize - $keeperSize)
        if ($wasted -lt 0) { $wasted = [long]0 }
    }

    $dupCount++
    if (-not $hardlinked) {
        $report.totalWastedBytes = [long]$report.totalWastedBytes + $wasted
    }

    $report.groups += [pscustomobject]@{
        hash         = $key
        fileCount    = $grp.Count
        uniqueInodes = $uniqueInodes
        wastedBytes  = $wasted
        hardlinked   = $hardlinked
        files        = $fileRows
    }
}

$report.duplicateGroups = $dupCount

# Top-50 by wasted bytes (for dashboards)
$report.topByWastedBytes = @(
    $report.groups |
        Where-Object { -not $_.hardlinked -and $_.wastedBytes -gt 0 } |
        Sort-Object -Property wastedBytes -Descending |
        Select-Object -First 50
)

# ---------------------------------------------------------------------------
# 8. Emit JSON + CSV
# ---------------------------------------------------------------------------
$jsonPath = Join-Path -Path $Script:OutputDirAbs -ChildPath ("dedupe-{0}.json" -f $Script:SessionId)
$csvPath  = Join-Path -Path $Script:OutputDirAbs -ChildPath ("dedupe-{0}.csv"  -f $Script:SessionId)

Write-Host ("[{0:HH:mm:ss}] writing JSON -> {1}" -f (Get-Date), $jsonPath) -ForegroundColor Yellow
$report | ConvertTo-Json -Depth 12 | Out-File -FilePath $jsonPath -Encoding UTF8

Write-Host ("[{0:HH:mm:ss}] writing CSV  -> {1}" -f (Get-Date), $csvPath) -ForegroundColor Yellow
$csvRows = foreach ($g in $report.groups) {
    foreach ($f in $g.files) {
        [pscustomobject]@{
            Hash         = $g.hash
            FileCount    = $g.fileCount
            UniqueInodes = $g.uniqueInodes
            WastedBytes  = $g.wastedBytes
            Hardlinked   = $g.hardlinked
            Path         = $f.path
            Size         = $f.size
            Inode        = $f.inode
        }
    }
}
$csvRows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

# ---------------------------------------------------------------------------
# 9. Summary + return value for callers
# ---------------------------------------------------------------------------
$hardlinkedCount = @($report.groups | Where-Object { $_.hardlinked }).Count
$gb              = [math]::Round($report.totalWastedBytes / 1GB, 3)

Write-Host ''
Write-Host '=== Summary ===' -ForegroundColor Green
Write-Host ("  Session           : {0}  ({1})" -f $Script:SessionName, $Script:SessionId)
Write-Host ("  Path              : {0}" -f $Path)
Write-Host ("  Algorithm         : {0}" -f $HashAlgorithm)
Write-Host ("  Threads           : {0}" -f $ThrottleLimit)
Write-Host ("  Scanned files     : {0:N0}" -f $report.scannedFiles)
Write-Host ("  Duplicate groups  : {0:N0}" -f $report.duplicateGroups)
Write-Host ("  Hard-linked grps  : {0:N0}" -f $hardlinkedCount)
Write-Host ("  Wasted bytes      : {0:N0} ({1:N3} GB)" -f $report.totalWastedBytes, $gb)
Write-Host ("  Elapsed           : {0:F1}s" -f $elapsed.TotalSeconds)
Write-Host ("  JSON              : {0}" -f $jsonPath)
Write-Host ("  CSV               : {0}" -f $csvPath)
Write-Host ("  Signature         : {0}" -f $Script:Signature)
Write-Host ''

[pscustomobject]@{
    sessionId        = $Script:SessionId
    sessionName      = $Script:SessionName
    signature        = $Script:Signature
    scannedFiles     = $report.scannedFiles
    duplicateGroups  = $report.duplicateGroups
    hardlinkedGroups = $hardlinkedCount
    totalWastedBytes = $report.totalWastedBytes
    jsonPath         = $jsonPath
    csvPath          = $csvPath
    elapsedSeconds   = [math]::Round($elapsed.TotalSeconds, 2)
    dryRun           = $false
}
