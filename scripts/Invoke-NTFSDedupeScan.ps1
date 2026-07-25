<#
.SYNOPSIS
    NTFS deduplication scanner optimized for Warp dashboards, with
    real-time ETA, per-folder progress, live throughput display,
    and structured log file output.

.DESCRIPTION
    Read-only scan of an NTFS volume (defaults to C:\).  For every regular
    file the script computes a content hash (SHA256 from the .NET BCL or
    BLAKE3 when `b3sum.exe` is on PATH), retrieves the NTFS File ID
    (the inode-equivalent reported by `GetFileInformationByHandle`),
    groups files by hash, distinguishes hard-linked copies from true
    content duplicates, and writes:

        * output/dedupe-<sessionId>.json  - Warp-dashboard-ready payload
        * output/dedupe-<sessionId>.csv   - flat per-file rows
        * logs/ntfs-dedupe-scan-<ts>.log  - structured INFO/WARN/ERROR/DEBUG

    The script never opens a file with write access and never mutates
    filesystem state.

    Live UX: ETA prediction (XXs | MM:SS | HH:MM:SS refreshed every s),
    per-folder progress bar (10-block ASCII bar with auto-collapse on
    completion), live throughput display ("Speed: 87 MB/s (avg 82,
    peak 104)") with instantaneous 1-s and 5-s moving-average.

.PARAMETER Path
    Root path to scan. Default: C:\

.PARAMETER OutputDir
    Folder for JSON/CSV artefacts. Created if missing. Default: .\output

.PARAMETER HashAlgorithm
    SHA256 (BCL; default) or BLAKE3 (requires b3sum.exe on PATH).

.PARAMETER ThrottleLimit
    Max parallel hash workers.  Default 8.  Reserved for future use;
    the current per-file loop is sequential to keep Write-Progress +
    per-folder bar updates deterministic.

.PARAMETER IncludeSystemPaths
    When present the default skip-list (Recycle Bin, System Volume
    Information, WindowsApps, etc.) is bypassed.

.PARAMETER DryRun
    Enumerate without hashing.  Reports the candidate-file count
    plus total bytes.

.PARAMETER LogDir
    Folder for the structured scan log. Default: .\logs

.EXAMPLE
    pwsh -File .\scripts\Invoke-NTFSDedupeScan.ps1

.EXAMPLE
    pwsh -File .\scripts\Invoke-NTFSDedupeScan.ps1 -HashAlgorithm BLAKE3 -ThrottleLimit 16

.EXAMPLE
    pwsh -File .\scripts\Invoke-NTFSDedupeScan.ps1 -Path .\sample-data -DryRun

.NOTES
    Script     : Invoke-NTFSDedupeScan.ps1
    Program    : ntfs-dedupe-scanner
    Version    : 0.4.1
    Author     : Mannie Greenspan <Oz agent>
    Harness    : agent:oz|mannie-greenspan
    License    : MIT
    Generated  : 2026-07-25
    See also   : ../docs/OUTPUT_SCHEMA.md, ../docs/ARCHITECTURE.md, ../docs/LOGGING.md

    v0.4.1  2026-07-25  Reviewer-driven correctness + docs polish from PR #1
                         review findings (Codex + CodeRabbit + Copilot):
                         * Blake3Hex: async stdout/stderr drains plus hard
                           30 s timeout + kill to avoid redirected-pipe
                           deadlocks; drains async readers on the fast path.
                         * Enumerate: try/catch around every lazy
                           Directory.Enumerate (IgnoreInaccessible
                           equivalent) so a single locked folder can no
                           longer abort the whole scan.
                         * ScanRecord: new HashAlgorithm field stamps
                           "blake3" or "sha256" per record; the duplicate
                           pass groups by (HashAlgorithm, Hash) so a single
                           fallback file cannot change which BLAKE3 records
                           match each other.
                         * Per-folder loop: $bytesDone + $folderBytes
                           advance even on hash failure so the final
                           progress / remaining-bytes / ETA are accurate
                           on the unreadable last file of a folder.
                         * Speed tracker no longer evaluates on the very
                           first record (avoids sub-millisecond speed
                           inflation that poisoned the running peak).
                         * Folder-bar: skip the in-place render on the
                           final file of a folder so the auto-collapse
                           prints exactly one 100% line.
                         * Write-ScanLog: flags + one-time console warning
                           if a log-write fails; carries the flag into the
                           summary line and the return object. log file is
                           written BOM-free so jq/awk/pandas treat it as a
                           plain UTF-8 stream.
                         * Log filename now includes the SessionId so
                           concurrent runs cannot clobber each other.
                         * Write-Warning at the first BLAKE3 fallback is
                           now a single-string invocation (no stray '+'
                           on the success output stream).
                         * Summary line `logWriteFailed=...` is JSON-style
                           lowercase ("true"/"false") so log parsers
                           don't have to special-case PS True/False.
                         JSON adds `attemptedFiles` next to `scannedFiles`;
                         the summary log line includes logWriteFailed.
                         PS5.1 hardening: BOM-free JSON/CSV/log writes,
                         no bare `(if ...) ` value expressions, no
                         `EnumerationOptions` compilation, and the group
                         key is split into `hashAlgorithm` + `hash`.
    v0.4.0  2026-07-25  BLAKE3-preferred / SHA256-fallback with explicit,
                         visible downgrade tracking.
                         * C# Blake3Hex: 30 s per-file timeout; kill-on-
                           timeout; return empty on non-zero exit, non-
                           empty stderr, or empty tokens.
                         * C# ScanSingleFile: when blake3Exe is non-empty,
                           try BLAKE3 first; on empty result, transparently
                           re-hash the file with SHA256 and stamp the new
                           ScanRecord.UsedFallback=true. Never silently
                           downgrades.
                         * C# ScanRecord.UsedFallback: new additive bool
                           field so callers can count + report per-file
                           downgrade decisions.
                         * PS tracker: $Script:Blake3FallbackCount + the
                           $Script:Blake3FallbackWarned latch ensure the
                           console warning fires once, not per file.
                         * JSON schema bumped 1.0.0 -> 1.0.1, adding
                           hashAlgorithmFallback and blake3FallbackCount.
                           Existing fields unchanged.
                         * Summary line "BLAKE3 fallbacks: N (SHA256 used
                           instead)" appears at the end of every run
                           (N=0 -> DarkGray; N>0 -> Yellow).
                         Still read-only / Windows PowerShell 5.1 safe.
    v0.3.0  2026-07-25  Progress UX bundle:
                         * Real-time ETA prediction (XXs | MM:SS | HH:MM:SS)
                           refreshed every 1 s from remaining bytes
                           and current moving-average MB/s speed.
                         * Per-folder progress bar (10-block ASCII bar
                           with percent + done/total counts) that
                           commits to a 100% line on completion and
                           auto-collapses to that single line
                           afterwards.
                         * Live throughput display: instantaneous 1-s
                           speed + 5-s moving average + peak across
                           the whole run ("Speed: 87 MB/s (avg 82,
                           peak 104)").
                         * Structured log file output: each session
                           writes ./logs/ntfs-dedupe-scan-<ts>.log
                           with timestamps + INFO/WARN/ERROR/DEBUG
                           levels for start/end, per-folder events,
                           throttled speed/ETA snapshots, error
                           counts, and the final summary.
                         * Completion summary with total time, average
                           speed, error counts, and per-folder stats.
                       Backed by new C# helpers PlanEntry + PlanScan
                       that materialize (path, size) pairs for byte
                       accounting. Stays Windows PowerShell 5.1 safe.
    v0.2.0  2026-07-25  Pre-scan counter + live Write-Progress bar;
                       new C# helpers ScanSingleFile / CountFiles /
                       EnumerateFiles; per-file hashing loop replaces
                       the bulk Parallel.ForEach call.
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
    [switch]$DryRun,

    [Parameter()]
    [string]$LogDir = './logs'
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
# 4b. Log directory + path  (structured logging, see docs/LOGGING.md)
# ---------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $LogDir)) {
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
}
$_logDirResolved = Resolve-Path -LiteralPath $LogDir -ErrorAction SilentlyContinue
if (-not $_logDirResolved) {
    throw "Log directory could not be resolved: $LogDir"
}
$Script:LogDirAbs = $_logDirResolved.ProviderPath
$Script:LogStamp  = Get-Date -Format 'yyyyMMddTHHmmss'
# Filename includes SessionId so concurrent or back-to-back runs cannot
# delete each other's logs (Windows clock collisions are rare but real on
# the second boundary).
$Script:LogPath   = Join-Path $Script:LogDirAbs ("ntfs-dedupe-scan-{0}-{1}.log" -f $Script:LogStamp, $Script:SessionId)
$Script:LogWriteFailed = $false

# ---------------------------------------------------------------------------
# 4c. Progress + logging helper functions (PS 5.1 safe)
# ---------------------------------------------------------------------------
function Write-ScanLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level,
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [switch]$NoConsole
    )
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] $Level : $Message"

    if ($Script:LogPath) {
        try {
            # `Add-Content -Encoding UTF8` in PS 5.1 prepends a BOM (EF BB BF)
            # on the FIRST call of every run, which trips strict downstream
            # parsers and shows up as `\ufeff` at the head of the log. We
            # hand-roll an appender that always uses UTF-8 without BOM so
            # the log stays grep-friendly for `jq`, `awk`, `pandas`, and
            # `Notion ingestion` alike.
            [System.IO.File]::AppendAllText(
                $Script:LogPath,
                ($line + [Environment]::NewLine),
                [System.Text.UTF8Encoding]::new($false))
        } catch {
            # Don't abort the scan for a logging hiccup; flag once and let
            # the summary line carry the count so dashboards know.
            if (-not $Script:LogWriteFailed) {
                $Script:LogWriteFailed = $true
                Write-Warning ("Failed to write to log file {0}; subsequent log events are dropped. Error: {1}" -f $Script:LogPath, $_.Exception.Message)
            }
        }
    }

    if (-not $NoConsole) {
        switch ($Level) {
            'INFO'  { Write-Host $line -ForegroundColor Cyan }
            'WARN'  { Write-Host $line -ForegroundColor Yellow }
            'ERROR' { Write-Host $line -ForegroundColor Red }
            'DEBUG' { Write-Host $line -ForegroundColor DarkGray }
            default { Write-Host $line }
        }
    }
}

function Format-Eta {
    [CmdletBinding()]
    param([int]$Seconds)
    if ($Seconds -lt 0) { return '--' }
    if ($Seconds -lt 60) { return ('{0}s' -f [int]$Seconds) }
    $m = [int][math]::Floor($Seconds / 60)
    $s = [int]($Seconds - ($m * 60))
    if ($m -lt 60) { return ('{0}:{1:D2}' -f $m, $s) }
    $h = [int][math]::Floor($m / 60)
    $m = $m - ($h * 60)
    return ('{0}:{1:D2}:{2:D2}' -f $h, $m, $s)
}

function Format-SpeedLine {
    [CmdletBinding()]
    param(
        [double]$Inst,
        [double]$Avg,
        [double]$Peak
    )
    return ('Speed: {0:N1} MB/s (avg {1:N1} MB/s, peak {2:N1} MB/s)' -f $Inst, $Avg, $Peak)
}

# Renders a 10-block progress bar. When `-Commit`, prints the line with
# newline so subsequent folders appear below (auto-collapse: completed
# folder shows only its 100% line). When `-Commit` is absent, the line
# is updated in place via CR + NoNewline.
function Show-FolderProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Folder,
        [Parameter(Mandatory = $true)][int]$Done,
        [Parameter(Mandatory = $true)][int]$Total,
        [switch]$Commit
    )
    $pct = if ($Total -gt 0) { [int][math]::Round(($Done / [double]$Total) * 100, 0) } else { 100 }
    if ($pct -gt 100) { $pct = 100 }
    if ($pct -lt 0)   { $pct = 0 }
    $filled = [int][math]::Floor($pct / 10)
    if ($filled -gt 10) { $filled = 10 }
    if ($filled -lt 0)  { $filled = 0 }
    $fillChar  = [string]::new([char]0x2588, $filled)
    $emptyChar = [string]::new([char]0x2591, 10 - $filled)
    $bar = '[' + $fillChar + $emptyChar + ']'
    $line = ($bar + ' {0,3}% ({1:N0}/{2:N0} files) {3}' -f $pct, $Done, $Total, $Folder)
    if ($Commit) {
        Write-Host $line
    } else {
        if ([Console]::IsOutputRedirected) {
            Write-Host $line
        } else {
            $width = [Math]::Max($line.Length + 2, [Console]::WindowWidth - 1)
            Write-Host ("`r{0}" -f $line.PadRight($width)) -NoNewline
        }
    }
}

# Tracks 1-s instantaneous speed, 5-s moving average, peak.
$Script:InstSpeed      = [double]0
$Script:AvgSpeed       = [double]0
$Script:PeakSpeed      = [double]0
$Script:LastTick       = [DateTime]::UtcNow
$Script:LastBytesDone  = [long]0
$Script:SpeedHistory   = New-Object 'System.Collections.Generic.List[object]'
$Script:ScanTick       = [DateTime]::UtcNow
$Script:Errors              = 0
$Script:FolderStats         = @()
# When BLAKE3 is requested and a specific file's b3sum call falls back to
# SHA256, this counter is incremented. The scanner prints a warning the
# first time it crosses 1, then quietly keeps incrementing so the log is
# not spammed. The final count is written into the JSON report.
$Script:Blake3FallbackCount = 0
$Script:Blake3FallbackWarned = $false

function Update-SpeedState {
    [CmdletBinding()]
    param([long]$BytesDone)
    $now = [DateTime]::UtcNow
    $dt  = ($now - $Script:LastTick).TotalSeconds
    if ($dt -gt 0) {
        $Script:InstSpeed = ($BytesDone - $Script:LastBytesDone) / $dt / 1MB
        if ($Script:InstSpeed -gt $Script:PeakSpeed) {
            $Script:PeakSpeed = $Script:InstSpeed
        }
    }
    $Script:SpeedHistory.Add(@{ tick = $now; bytes = $BytesDone })
    while ($Script:SpeedHistory.Count -gt 0 -and ($now - $Script:SpeedHistory[0].tick).TotalSeconds -gt 5.5) {
        $Script:SpeedHistory.RemoveAt(0) | Out-Null
    }
    if ($Script:SpeedHistory.Count -ge 2) {
        $first = $Script:SpeedHistory[0]
        $last  = $Script:SpeedHistory[$Script:SpeedHistory.Count - 1]
        $dt5 = ($last.tick - $first.tick).TotalSeconds
        $db5 = ($last.bytes - $first.bytes)
        if ($dt5 -gt 0) { $Script:AvgSpeed = $db5 / $dt5 / 1MB }
    }
    $Script:LastTick = $now
    $Script:LastBytesDone = $BytesDone
}

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
    // Lower-case hash algorithm that produced `Hash` for THIS record.
    // Either "blake3" or "sha256". Additive field; older consumers can
    // ignore it. v0.4.1 uses this to keep BLAKE3 and SHA256 digests in
    // separate duplicate-group buckets so a single fallback file cannot
    // silently change the result set.
    public string HashAlgorithm { get; set; }
    public string Hash  { get; set; }
    public ulong  Inode { get; set; }
    // True when BLAKE3 was requested but the call fell back to SHA256 for
    // this file (b3sum returned empty hash, non-zero exit, timed out, or
    // printed anything to stderr). Additive field; older code paths can
    // ignore it.
    public bool   UsedFallback { get; set; }
}

public sealed class PlanEntry {
    public string Path { get; set; }
    public long   Size { get; set; }
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
    private const uint OPEN_EXISTING     = 0x3;

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
        using (var p = new Process { StartInfo = psi }) {
            // Drain stdout / stderr asynchronously. Synchronous ReadToEnd()
            // can deadlock the parent when one redirected pipe fills before
            // b3sum exits; BeginOutputReadLine + OutputDataReceived keeps
            // both buffers moving while we WaitForExit with a hard timeout.
            var stdout = new System.Text.StringBuilder();
            var stderr = new System.Text.StringBuilder();
            var stdoutDone = new ManualResetEvent(false);
            var stderrDone = new ManualResetEvent(false);
            p.OutputDataReceived += (s, e) => {
                if (e.Data != null) stdout.AppendLine(e.Data);
                else stdoutDone.Set();
            };
            p.ErrorDataReceived  += (s, e) => {
                if (e.Data != null) stderr.AppendLine(e.Data);
                else stderrDone.Set();
            };
            if (!p.Start()) return string.Empty;
            p.BeginOutputReadLine();
            p.BeginErrorReadLine();

            // Per-file timeout: 30 s. If b3sum hangs (locked handle,
            // sshfs-style network mount, deadlocked pipe), we kill and
            // treat the result as a fallback.
            const int timeoutMs = 30 * 1000;
            if (!p.WaitForExit(timeoutMs)) {
                try { p.Kill(); } catch { }
                try { p.WaitForExit(); } catch { }
                return string.Empty;
            }
            // Ensure the async readers drained even on the fast path.
            stdoutDone.WaitOne(2000);
            stderrDone.WaitOne(2000);

            string outStr = stdout.ToString().Trim();
            string errStr = stderr.ToString().Trim();
            if (p.ExitCode != 0)               return string.Empty;
            if (!string.IsNullOrEmpty(errStr)) return string.Empty;
            if (string.IsNullOrEmpty(outStr))  return string.Empty;
            var tokens = outStr.Split(
                new[] { ' ', '\t', '\r', '\n' },
                StringSplitOptions.RemoveEmptyEntries);
            return tokens.Length > 0 ? tokens[0] : string.Empty;
        }
    }

    private static IEnumerable<string> Enumerate(string root, HashSet<string> skip) {
        // Manual DFS without relying on a unified EnumerationOptions.
        // PS 5.1 + .NET Framework 4.x don't reliably expose EnumerationOptions,
        // so we enumerate directories breadth-first and wrap EVERY foreach
        // over the lazy enumerator in a try/catch. A single locked folder
        // therefore cannot abort a full-volume walk; traversal continues
        // with whatever siblings we successfully enumerated.
        var stack = new Stack<string>();
        stack.Push(root);
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        while (stack.Count > 0) {
            string dir = stack.Pop();
            if (!seen.Add(dir)) continue;

            string leaf;
            try { leaf = Path.GetFileName(dir); } catch { continue; }
            if (!string.IsNullOrEmpty(leaf) && skip.Contains(leaf)) continue;

            // Children: directories + files. Push directories first, then
            // yield files so DFS order matches the caller's expectation.
            List<string> childDirs = null;
            try {
                childDirs = new List<string>(Directory.EnumerateDirectories(dir));
            } catch (UnauthorizedAccessException) { }
            catch (DirectoryNotFoundException)     { }
            catch (IOException)                    { }
            List<string> childFiles = null;
            try {
                childFiles = new List<string>(Directory.EnumerateFiles(dir));
            } catch (UnauthorizedAccessException) { }
            catch (DirectoryNotFoundException)     { }
            catch (IOException)                    { }

            if (childDirs != null) {
                foreach (var d in childDirs) stack.Push(d);
            }
            if (childFiles != null) {
                foreach (var f in childFiles) yield return f;
            }
        }
    }

    /// <summary>
    /// Lazy enumeration of every regular file under <paramref name="rootPath"/>,
    /// honouring <paramref name="skipNames"/>.
    /// </summary>
    public static IEnumerable<string> EnumerateFiles(string rootPath, string[] skipNames) {
        if (string.IsNullOrEmpty(rootPath)) throw new ArgumentNullException("rootPath");
        var skip = new HashSet<string>(
            skipNames ?? new string[0],
            StringComparer.OrdinalIgnoreCase);
        return Enumerate(rootPath, skip);
    }

    /// <summary>
    /// Fast directory walk that returns just the candidate-file count.
    /// </summary>
    public static int CountFiles(string rootPath, string[] skipNames) {
        int n = 0;
        foreach (var _ in EnumerateFiles(rootPath, skipNames)) { n++; }
        return n;
    }

    /// <summary>
    /// Materializes (path, size) pairs in DFS order so PowerShell can
    /// group by folder and compute ETA/speed from total bytes.
    /// </summary>
    public static List<PlanEntry> PlanScan(string rootPath, string[] skipNames) {
        if (string.IsNullOrEmpty(rootPath)) throw new ArgumentNullException("rootPath");
        var plan = new List<PlanEntry>();
        foreach (var f in EnumerateFiles(rootPath, skipNames)) {
            long sz = 0;
            try { sz = new FileInfo(f).Length; } catch { }
            plan.Add(new PlanEntry { Path = f, Size = sz });
        }
        return plan;
    }

    /// <summary>
    /// Hash + inode lookup for a single file. Returns <c>null</c> on
    /// any per-file failure (permission denied, vanished file, ...).
    ///
    /// When <paramref name="blake3Exe"/> is non-empty, BLAKE3 is preferred.
    /// If the BLAKE3 call returns an empty hash (non-zero exit, timeout, or
    /// b3sum reported an error), we transparently fall back to SHA256 for
    /// THIS file and stamp ScanRecord.UsedFallback = true so callers can
    /// count and report the downgrade.
    /// </summary>
    public static ScanRecord ScanSingleFile(string file, string blake3Exe) {
        if (string.IsNullOrEmpty(file)) return null;
        try {
            var fi = new FileInfo(file);
            ScanRecord rec;
            if (string.IsNullOrEmpty(blake3Exe)) {
                rec = new ScanRecord {
                    Path         = file,
                    Size         = fi.Length,
                    Hash         = Sha256Hex(file),
                    HashAlgorithm = "sha256",
                    Inode        = GetFileId(file),
                    UsedFallback = false
                };
            } else {
                string b3 = Blake3Hex(file, blake3Exe);
                if (string.IsNullOrEmpty(b3)) {
                    // BLAKE3 failed for this one file; downgrade to SHA256.
                    rec = new ScanRecord {
                        Path         = file,
                        Size         = fi.Length,
                        Hash         = Sha256Hex(file),
                        HashAlgorithm = "sha256",
                        Inode        = GetFileId(file),
                        UsedFallback = true
                    };
                } else {
                    rec = new ScanRecord {
                        Path         = file,
                        Size         = fi.Length,
                        Hash         = b3,
                        HashAlgorithm = "blake3",
                        Inode        = GetFileId(file),
                        UsedFallback = false
                    };
                }
            }
            return rec;
        } catch {
            /* permission denied, vanished file, locked handle, etc. */
            return null;
        }
    }
}
'@

if (-not ([System.Management.Automation.PSTypeName]'NTFSHashScanner').Type) {
    Write-Host 'Compiling C# helper NTFSHashScanner ...' -ForegroundColor DarkGray
    Add-Type -TypeDefinition $cs -Language CSharp
}

# ---------------------------------------------------------------------------
# 5b. Emit session-start log record (file + console)
# ---------------------------------------------------------------------------
Write-ScanLog -Level INFO -Message ("ntfs-dedupe-scan starting; session={0} id={1} path={2} algo={3} threads={4} dryRun={5} hashSuite=NTFSHashScanner" -f `
    $Script:SessionName, $Script:SessionId, $Path, $HashAlgorithm, $ThrottleLimit, [bool]$DryRun)
Write-ScanLog -Level INFO -Message ("log path resolved; logFile={0}" -f $Script:LogPath)

# ---------------------------------------------------------------------------
# 6. Run the scan
# ---------------------------------------------------------------------------
$stopwatch     = [System.Diagnostics.Stopwatch]::StartNew()
$blake3ForCS   = if ($HashAlgorithm -eq 'BLAKE3') { $Script:B3SumPath } else { $null }
$skipForCS     = if ($IncludeSystemPaths)        { @() }              else { $Script:DefaultSkip }

# 6a. Pre-scan: enumerate every path with its size so ETA + speed can
# be computed from total bytes and per-byte throughput.
Write-Host ("[{0:HH:mm:ss}] pre-scanning candidate files ..." -f (Get-Date)) -ForegroundColor Yellow
Write-ScanLog -Level INFO -Message ("pre-scan start; path={0}" -f $Path)
$plan         = [NTFSHashScanner]::PlanScan($Path, $skipForCS)
$total        = $plan.Count
$bytesTotal   = [long]($plan | Measure-Object -Property Size -Sum).Sum
Write-Host ("[{0:HH:mm:ss}] {1:N0} candidate files ({2:N2} GiB) found in {3:F1}s" -f (Get-Date), $total, ($bytesTotal / 1GB), $stopwatch.Elapsed.TotalSeconds) -ForegroundColor Yellow
Write-ScanLog -Level INFO -Message ("pre-scan complete; candidates={0} bytesTotal={1} elapsedSec={2:F2}" -f $total, $bytesTotal, $stopwatch.Elapsed.TotalSeconds)

# 6b. DryRun short-circuit
if ($DryRun) {
    $stopwatch.Stop()
    $elapsed = $stopwatch.Elapsed
    $dryStatus = '{0:N0} candidate files ({1:N2} GiB)' -f $total, ($bytesTotal / 1GB)
    Write-Host ''
    Write-Host ("DryRun complete: {0:N0} candidate files in {1:F1}s" -f $total, $elapsed.TotalSeconds) -ForegroundColor Green
    Write-ScanLog -Level INFO -Message ("dry-run complete; candidates={0} bytesTotal={1} elapsedSec={2:F2}" -f $total, $bytesTotal, $elapsed.TotalSeconds)
    Write-Progress -Activity 'NTFS deduplication scan (dry-run)' -Status $dryStatus -PercentComplete 100 -Completed
    return [pscustomobject]@{
        sessionId        = $Script:SessionId
        sessionName      = $Script:SessionName
        signature        = $Script:Signature
        scannedFiles     = $total
        duplicateGroups  = 0
        totalWastedBytes = 0
        jsonPath         = $null
        csvPath          = $null
        elapsedSeconds   = [math]::Round($elapsed.TotalSeconds, 2)
        dryRun           = $true
    }
}

# 6c. Group plan by parent folder (DFS insertion order preserved).
$folderGroups = [ordered]@{}
foreach ($e in $plan) {
    $folder = Split-Path -Parent $e.Path
    if (-not $folderGroups.Contains($folder)) {
        $folderGroups[$folder] = New-Object 'System.Collections.Generic.List[object]'
    }
    $folderGroups[$folder].Add($e)
}

# Reset speed tracker to start of scan proper, not pre-scan time.
$Script:ScanTick      = [DateTime]::UtcNow
$Script:LastTick      = $Script:ScanTick
$Script:LastBytesDone = [long]0
$Script:InstSpeed     = [double]0
$Script:AvgSpeed      = [double]0
$Script:PeakSpeed     = [double]0
$Script:SpeedHistory.Clear()

# 6d. Per-folder hashing loop with live ETA + speed + per-folder bar.
$records    = New-Object 'System.Collections.Generic.List[object]'
$done       = 0   # files that produced a usable ScanRecord (success)
$attempted  = 0   # files we got to, including per-folder hash failures
$bytesDone  = [long]0
$progressActivity = 'NTFS deduplication scan'
$lastSpeedLog    = [DateTime]::UtcNow
$lastEtaLog      = [DateTime]::UtcNow

Write-Host ("[{0:HH:mm:ss}] hashing {1:N0} files in {2:N0} folders (per-file loop, --ThrottleLimit {3} reserved) ..." -f (Get-Date), $total, $folderGroups.Count, $ThrottleLimit) -ForegroundColor Yellow
Write-ScanLog -Level INFO -Message ("hashing start; total={0} bytesTotal={1} folders={2}" -f $total, $bytesTotal, $folderGroups.Count)

try {
    foreach ($folder in $folderGroups.Keys) {
        $entries     = $folderGroups[$folder]
        $folderTotal = $entries.Count
        $folderDone  = 0
        $folderBytes = [long]0
        $folderStart = [DateTime]::UtcNow

        Write-ScanLog -Level INFO -Message ("folder start; path={0} files={1}" -f $folder, $folderTotal)

        foreach ($e in $entries) {
            $rec = [NTFSHashScanner]::ScanSingleFile($e.Path, $blake3ForCS)
            if ($rec) {
                # Track per-file BLAKE3 -> SHA256 fallback. The C# helper
                # stamps UsedFallback=true exactly when the BLAKE3 path
                # returned empty; we surface it loudly the first time so
                # the operator notices but don't spam.
                if ($rec.UsedFallback) {
                    $Script:Blake3FallbackCount++
                    if (-not $Script:Blake3FallbackWarned) {
                        Write-Warning ("BLAKE3 fallback detected for {0} (using SHA256 instead). This warning is shown once; further fallbacks are counted and reported in the JSON." -f $e.Path)
                        Write-ScanLog -Level WARN -Message ("blake3 fallback first-occurrence; path={0} using=SHA256" -f $e.Path)
                        $Script:Blake3FallbackWarned = $true
                    }
                }
                $records.Add($rec)
                $bytesDone += [long]$rec.Size
                $folderBytes += [long]$rec.Size
                $done++
                $folderDone++
            } else {
                # Hash failed (permission denied, vanished file, etc.). Still
                # advance $bytesDone + $folderBytes so the final progress,
                # remaining bytes, and ETA are accurate on the unreadable last
                # file of a folder.
                $Script:Errors++
                $bytesDone += [long]$e.Size
                $folderBytes += [long]$e.Size
                $done++
                $folderDone++
            }
            $attempted++

            $now        = [DateTime]::UtcNow
            $sinceTick  = ($now - $Script:LastTick).TotalSeconds
            # Skip the speed/ETA tick on the very first record: dividing a
            # full file size by sub-second elapsed time blows up
            # instantaneous MB/s AND poisons the running peak. We seed the
            # history by just resetting the timer; the next normal tick
            # produces a stable sample.
            $shouldTick = ($sinceTick -ge 1.0) -or ($done -eq $total)

            if ($shouldTick) {
                Update-SpeedState -BytesDone $bytesDone
                $pct = if ($total -gt 0) { [int][math]::Round(($done / [double]$total) * 100, 0) } else { 100 }
                if ($pct -gt 100) { $pct = 100 }
                $remaining = [Math]::Max(0, [double]($bytesTotal - $bytesDone))
                $etaSec    = if ($Script:InstSpeed -gt 0.01) { [int]($remaining / ($Script:InstSpeed * 1MB)) } else { -1 }
                $etaStr    = Format-Eta -Seconds $etaSec
                $speedStr  = Format-SpeedLine -Inst $Script:InstSpeed -Avg $Script:AvgSpeed -Peak $Script:PeakSpeed
                $status    = ('{0:N0}/{1:N0} files ({2}%) | {3} | ETA {4}' -f $done, $total, $pct, $speedStr, $etaStr)
                Write-Progress -Activity $progressActivity -Status $status -PercentComplete $pct -CurrentOperation $e.Path

                # Throttle log emissions: one speed row + one ETA row every ~5 sec
                if (($now - $lastSpeedLog).TotalSeconds -ge 5.0) {
                    Write-ScanLog -Level INFO -Message ("speed update; {0}" -f $speedStr)
                    $lastSpeedLog = $now
                }
                if (($now - $lastEtaLog).TotalSeconds -ge 5.0) {
                    Write-ScanLog -Level INFO -Message ("eta update; remainingBytes={0} eta={1}" -f ([long]$remaining), $etaStr)
                    $lastEtaLog = $now
                }
            }

            # Per-folder bar update (always at start + end; rate-limited mid-folder).
            # On the very last file we skip the in-place render and let the
            # -Commit render below produce the single 100% line; otherwise a
            # non-commit render followed immediately by the commit prints the
            # bar twice on one physical line in interactive consoles.
            $barThreshold = if ($folderTotal -gt 100) { [int]($folderTotal / 10) } else { 1 }
            $isFinalFile  = ($folderDone -eq $folderTotal)
            if (-not $isFinalFile -and ($folderTotal -le 5 -or $folderDone -eq 1 -or (($folderDone % $barThreshold) -eq 0))) {
                Show-FolderProgress -Folder $folder -Done $folderDone -Total $folderTotal
            }
        }
        Show-FolderProgress -Folder $folder -Done $folderTotal -Total $folderTotal -Commit

        $folderElapsed = ([DateTime]::UtcNow - $folderStart).TotalSeconds
        $Script:FolderStats += [pscustomobject]@{
            Path         = $folder
            Files        = $folderTotal
            Bytes        = $folderBytes
            DurationSec  = [math]::Round($folderElapsed, 2)
            FilesPerSec  = if ($folderElapsed -gt 0) { [math]::Round($folderTotal / $folderElapsed, 1) } else { 0 }
        }
        Write-ScanLog -Level INFO -Message ("folder complete; path={0} files={1} bytes={2} durationSec={3:F2}" -f $folder, $folderTotal, $folderBytes, $folderElapsed)
    }
} finally {
    Write-Progress -Activity $progressActivity -Completed
}

$stopwatch.Stop()
$elapsed = $stopwatch.Elapsed

Write-Host ("[{0:HH:mm:ss}] {1:N0}/{2:N0} files hashed ({3:N0} scan records), {4:N0} per-file errors, {5:F1}s elapsed" -f (Get-Date), $done, $total, $records.Count, $Script:Errors, $elapsed.TotalSeconds) -ForegroundColor Yellow
Write-ScanLog -Level INFO -Message ("hashing complete; hashed={0} attempted={1} records={2} errors={3} bytesDone={4} elapsedSec={5:F2}" -f $done, $attempted, $records.Count, $Script:Errors, $bytesDone, $elapsed.TotalSeconds)

# ---------------------------------------------------------------------------
# 7. Group by hash, classify duplicates, compute wasted bytes
# ---------------------------------------------------------------------------
# Bumped to 1.0.1: adds hashAlgorithmFallback and blake3FallbackCount so
# dashboards can detect when the hash suite requested was not actually
# used for every file. The bump is additive (new fields, no renames).
$report = [ordered]@{
    schemaVersion      = '1.0.1'
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
    # hashAlgorithmFallback is null when no per-file fallback happened; set
    # to "SHA256" whenever at least one file's BLAKE3 call silently
    # downgraded. New in 1.0.1.
    hashAlgorithmFallback = if ($Script:Blake3FallbackCount -gt 0) { 'SHA256' } else { $null }
    blake3FallbackCount   = $Script:Blake3FallbackCount
    includeSystemPaths = [bool]$IncludeSystemPaths
    throttleLimit      = $ThrottleLimit
    skippedFolders     = @()
    scannedFiles       = $done        # successfully hashed files
    attemptedFiles     = $attempted   # files we got to, incl. failures
    duplicateGroups    = 0
    totalWastedBytes   = 0L
    totalBytes         = $bytesTotal
    speedMBps          = [ordered]@{
        instantaneous = [math]::Round($Script:InstSpeed, 2)
        average5s     = [math]::Round($Script:AvgSpeed, 2)
        peak          = [math]::Round($Script:PeakSpeed, 2)
    }
    perFolder          = @()
    topByWastedBytes   = @()
    groups             = @()
}

if (-not $IncludeSystemPaths) {
    $report.skippedFolders = @($Script:DefaultSkip)
}

$report.perFolder = @($Script:FolderStats)

Write-Host ("[{0:HH:mm:ss}] grouping duplicates ..." -f (Get-Date)) -ForegroundColor Yellow

# Bucket records by (HashAlgorithm, Hash). Keeping digests from different
# algorithms in separate buckets means a single per-file SHA256 fallback
# cannot change which BLAKE3 records match each other. Fallback files
# land in a small "sha256" group of their own that dashboards can show
# alongside the BLAKE3 groups.
$grouped = @{}
foreach ($r in $records) {
    $algo  = if ([string]::IsNullOrEmpty($r.HashAlgorithm)) { 'unknown' } else { $r.HashAlgorithm.ToLowerInvariant() }
    $key   = "$algo|$($r.Hash)"
    if (-not $grouped.ContainsKey($key)) {
        $grouped[$key] = New-Object System.Collections.Generic.List[object]
    }
    $grouped[$key].Add($r)
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

    # $key is "$algo|$($r.Hash)" (added in v0.4.1 to keep BLAKE3 and
    # SHA256 digests in separate buckets). Split it apart so dashboards
    # see clean fields rather than a "blake3:abcdef..." concatenated
    # string in the hash column.
    $keyParts      = $key -split '\|', 2
    $groupAlgo     = $keyParts[0]
    $groupHash     = $keyParts[1]

    $report.groups += [pscustomobject]@{
        hashAlgorithm = $groupAlgo
        hash          = $groupHash
        fileCount     = $grp.Count
        uniqueInodes  = $uniqueInodes
        wastedBytes   = $wasted
        hardlinked    = $hardlinked
        files         = $fileRows
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
# Write the JSON without a UTF-8 BOM. `Out-File -Encoding UTF8` in
# PS 5.1 prepends a BOM, which trip up strict downstream parsers
# (json.load, jq, gcloud jq). We hand-roll the file write with an
# explicit UTF-8-without-BOM encoding.
$_reportJson = ($report | ConvertTo-Json -Depth 12) + [Environment]::NewLine
[System.IO.File]::WriteAllText($jsonPath, $_reportJson, [System.Text.UTF8Encoding]::new($false))

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
# `Export-Csv -Encoding UTF8` in PS 5.1 prepends a BOM, which trips
# strict downstream parsers (pandas.read_csv without encoding='utf-8-sig',
# DuckDB csv reader, etc.). Hand-roll the write so the file starts with
# a clean UTF-8 byte stream.
$_csvHeader = 'Hash,FileCount,UniqueInodes,WastedBytes,Hardlinked,Path,Size,Inode'
$_csvLines  = foreach ($r in $csvRows) {
    ('"{0}",{1},{2},{3},{4},"{5}",{6},{7}' -f `
        $r.Hash, $r.FileCount, $r.UniqueInodes, $r.WastedBytes, $r.Hardlinked,
        ($r.Path -replace '"', '""'), $r.Size, $r.Inode)
}
$_csvText = ($_csvHeader + [Environment]::NewLine) + (($_csvLines -join [Environment]::NewLine) + [Environment]::NewLine)
[System.IO.File]::WriteAllText($csvPath, $_csvText, [System.Text.UTF8Encoding]::new($false))

# ---------------------------------------------------------------------------
# 9. Summary + return value for callers
# ---------------------------------------------------------------------------
$hardlinkedCount = @($report.groups | Where-Object { $_.hardlinked }).Count
$gb              = [math]::Round($report.totalWastedBytes / 1GB, 3)
$avgSpeed        = if ($elapsed.TotalSeconds -gt 0) { ($bytesDone / $elapsed.TotalSeconds) / 1MB } else { 0 }

Write-Host ''
Write-Host '=== Summary ===' -ForegroundColor Green
Write-Host ("  Session           : {0}  ({1})" -f $Script:SessionName, $Script:SessionId)
Write-Host ("  Path              : {0}" -f $Path)
Write-Host ("  Algorithm         : {0}" -f $HashAlgorithm)
if ($Script:Blake3FallbackCount -gt 0) {
    Write-Host ("  Hash fallback     : {0} files downgraded to SHA256 because BLAKE3 was unavailable for them" -f $Script:Blake3FallbackCount) -ForegroundColor Yellow
} else {
    Write-Host ("  Hash fallback     : none (every file hashed with {0})" -f $HashAlgorithm) -ForegroundColor DarkGray
}
Write-Host ("  Threads           : {0}" -f $ThrottleLimit)
Write-Host ("  Scanned files     : {0:N0}" -f $report.scannedFiles)
Write-Host ("  Duplicate groups  : {0:N0}" -f $report.duplicateGroups)
Write-Host ("  Hard-linked grps  : {0:N0}" -f $hardlinkedCount)
Write-Host ("  Wasted bytes      : {0:N0} ({1:N3} GB)" -f $report.totalWastedBytes, $gb)
Write-Host ("  Total bytes       : {0:N0} ({1:N2} GiB)" -f $bytesTotal, ($bytesTotal / 1GB))
Write-Host ("  Per-file errors   : {0:N0}" -f $Script:Errors)
Write-Host ("  Folders processed : {0:N0}" -f $Script:FolderStats.Count)
Write-Host ("  Elapsed           : {0:F1}s" -f $elapsed.TotalSeconds)
Write-Host ("  Average speed     : {0:N1} MB/s" -f $avgSpeed)
Write-Host ("  Peak speed        : {0:N1} MB/s" -f $Script:PeakSpeed)
Write-Host ("  JSON              : {0}" -f $jsonPath)
Write-Host ("  CSV               : {0}" -f $csvPath)
Write-Host ("  Log               : {0}" -f $Script:LogPath)
Write-Host ("  Signature         : {0}" -f $Script:Signature)
Write-Host ''

# Per the intent envelope: clarify that the user-requested algorithm and
# the actually-used algorithm can diverge. Skipped if zero fallbacks.
Write-Host ("BLAKE3 fallbacks: {0} (SHA256 used instead)" -f $Script:Blake3FallbackCount) -ForegroundColor $(if ($Script:Blake3FallbackCount -gt 0) { 'Yellow' } else { 'DarkGray' })

# Final summary log line (so dashboards can parse end events quickly).
# PowerShell 5.1 does not support bare `(if ...) ` as a value expression,
# so we resolve both ternaries into locals first. `logWriteFailed` is
# spelled JSON-style ("true"/"false") rather than PowerShell's default
# "True"/"False" so log parsers reading for `=true` / `=false` keep
# working without per-language customization.
$summaryAlgoFallback    = if ($null -ne $report.hashAlgorithmFallback) { $report.hashAlgorithmFallback } else { 'none' }
$summaryLogWriteFailed  = if ($Script:LogWriteFailed) { 'true' } else { 'false' }
Write-ScanLog -Level INFO -Message ("summary; scannedFiles={0} attemptedFiles={1} duplicateGroups={2} hardlinkedGroups={3} wastedBytes={4} totalBytes={5} errors={6} folders={7} elapsedSec={8:F2} avgSpeedMBps={9:N1} peakSpeedMBps={10:N1} blake3FallbackCount={11} hashAlgorithmFallback={12} logWriteFailed={13} jsonPath={14} csvPath={15} logPath={16}" -f `
    $report.scannedFiles, $report.attemptedFiles, $report.duplicateGroups, $hardlinkedCount, $report.totalWastedBytes, $bytesTotal, $Script:Errors, $Script:FolderStats.Count, $elapsed.TotalSeconds, $avgSpeed, $Script:PeakSpeed, $Script:Blake3FallbackCount, $summaryAlgoFallback, $summaryLogWriteFailed, $jsonPath, $csvPath, $Script:LogPath)
if ($Script:Blake3FallbackCount -gt 0) {
    Write-ScanLog -Level WARN -Message ("blake3 fallbacks detected; count={0} downgrade=SHA256" -f $Script:Blake3FallbackCount)
}
Write-ScanLog -Level INFO -Message 'ntfs-dedupe-scan end'

[pscustomobject]@{
    sessionId        = $Script:SessionId
    sessionName      = $Script:SessionName
    signature        = $Script:Signature
    scannedFiles     = $report.scannedFiles
    attemptedFiles   = $report.attemptedFiles
    duplicateGroups  = $report.duplicateGroups
    hardlinkedGroups = $hardlinkedCount
    totalWastedBytes = $report.totalWastedBytes
    totalBytes       = $bytesTotal
    errors           = $Script:Errors
    folders          = $Script:FolderStats.Count
    elapsedSeconds   = [math]::Round($elapsed.TotalSeconds, 2)
    averageSpeedMBps = [math]::Round($avgSpeed, 2)
    peakSpeedMBps    = [math]::Round($Script:PeakSpeed, 2)
    blake3FallbackCount = $Script:Blake3FallbackCount
    jsonPath         = $jsonPath
    csvPath          = $csvPath
    logPath          = $Script:LogPath
    logWriteFailed   = [bool]$Script:LogWriteFailed
    dryRun           = $false
}
