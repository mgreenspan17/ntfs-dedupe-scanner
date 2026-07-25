# Usage

## Console invocation

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\Invoke-NTFSDedupeScan.ps1
```

Default behaviour:

|- `-Path`               `C:\`
|- `-OutputDir`          `.\output`
|- `-LogDir`             `.\logs`
|- `-HashAlgorithm`      `SHA256`
|- `-ThrottleLimit`      `8` (reserved; per-file loop is sequential in 0.3.0)
|- `-IncludeSystemPaths` `$false`
|- `-DryRun`             `$false`

## Common recipes

### Smoke test on a small folder

```powershell
$root = 'C:\Users\manni\projects\ntfs-dedupe-scanner\sample-data'
1..5 | ForEach-Object { 'lorem ipsum dolor sit amet '*1000 | Set-Content (Join-Path $root "dup-$_.txt") }
'unique-content-x' | Set-Content (Join-Path $root 'unique.txt')

pwsh -File .\scripts\Invoke-NTFSDedupeScan.ps1 -Path $root -OutputDir .\output
```

### BLAKE3

`b3sum.exe` must be on PATH. The script auto-detects it; download the
release from [bluezealot/b3sum](https://github.com/BlueZealot/b3sum-windows)
or build from `cargo install b3sum`.

```powershell
pwsh -File .\scripts\Invoke-NTFSDedupeScan.ps1 -HashAlgorithm BLAKE3
```

### Whole `C:\` in 2-5 minutes

```powershell
# Recommended for NVMe: bump to 16 workers
pwsh -File .\scripts\Invoke-NTFSDedupeScan.ps1 -ThrottleLimit 16
```

### Including system folders (rarely useful)

```powershell
pwsh -File .\scripts\Invoke-NTFSDedupeScan.ps1 -IncludeSystemPaths
```

### Dry run

List everything that would be hashed without actually hashing:

```powershell
pwsh -File .\scripts\Invoke-NTFSDedupeScan.ps1 -DryRun
```

## Live UX (v0.3.0+)

During a full scan the `Write-Progress` taskbar, the per-folder console
line, and the structured log file all update together every ~1 s.

### ETA prediction

```text
ETA: 1:23        # 1 min 23 s remaining
ETA: 45s         # < 60 s
ETA: 2:14:09     # >= 1 h
ETA: --          # not yet estimable (no throughput yet)
```

ETA = remaining bytes / instantaneous MB/s. The renderer
(`Format-Eta`) follows the spec:

- < 60 s → `XXs`
- < 60 min → `MM:SS`
- otherwise → `HH:MM:SS`

### Per-folder progress bar

Each parent folder draws a 10-block ASCII bar in place (via `\r` +
`NoNewline`) and commits a final 100% line on completion — that line
scrolls up into the buffer, so each folder takes a single visual row
once the scan has moved past it.

```text
[████████░░]  80% (45/56 files) C:\Users\manni\Photos
[██████████] 100% (56/56 files) C:\Users\manni\Photos
[███░░░░░░░]  30% (12/40 files) C:\Users\manni\Documents
```

Pattern uses `█` (U+2588) and `░` (U+2591).

### Live throughput

```text
Speed: 87 MB/s (avg 82 MB/s, peak 104 MB/s)
```

- **instantaneous** — round-up printed every ~1 s
- **average5s** — moving average over the last 5 s
- **peak** — highest instantaneous speed observed during the run

The same numbers land in `JSON.speedMBps` for dashboarding.

## Returns

The script writes JSON, CSV, and a log file and prints:

- Number of files scanned
- Number of duplicate groups
- Wasted bytes (formatted as GB)
- Total bytes (formatted as GiB)
- Per-file errors, elapsed seconds, average + peak speed

It returns a structured `PSCustomObject` (`$Result`) so you can pipe
it to other scripts:

```powershell
$result = & pwsh -File .\scripts\Invoke-NTFSDedupeScan.ps1 -Path .\sample-data
$result.duplicateGroups
$result.totalWastedBytes
$result.averageSpeedMBps
$result.peakSpeedMBps
$result.logPath
```

## Scheduling

Add to Task Scheduler to dedupe weekly, or wrap in a dashboard-friendly
PowerShell workflow for Warp:

```powershell
$json = Get-Content .\output\dedupe-*.json -Raw | ConvertFrom-Json
$json | ConvertTo-Json -Depth 6 | Set-Clipboard  # paste into a Warp card
```

For log-parsing pipelines:

```powershell
Get-Content .\logs\ntfs-dedupe-scan-*.log |
    Where-Object { $_ -match '^\[' } |
    ForEach-Object { $_ -replace '^\[(\S+ \S+)\] (\S+) : (.+)$', '$1|$2|$3' } |
    ConvertFrom-Csv -Delimiter '|'
```

See [`docs/LOGGING.md`](LOGGING.md) for the full event vocabulary.

## Troubleshooting

| Symptom                                          | Fix                                                |
|--------------------------------------------------|----------------------------------------------------|
| BLAKE3 module not loaded; falling back...        | Install `b3sum.exe` or stay on SHA256              |
| Access denied on `C:\Windows\...`                | Add `-IncludeSystemPaths` (still read-only) or skip |
| Hash is empty for large files                    | File was unreadable; check the source path         |
| Output dir missing                               | The script creates it; ensure parent is writable   |
| Log dir not appearing                            | Check `-LogDir` and ensure parent is writable      |
| ETA stays at `--`                                | First ~1 s after `hashing start`; speed history warmup |
