# Usage

## Console invocation

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\Invoke-NTFSDedupeScan.ps1
```

Default behaviour:

- `-Path`             `C:\`
- `-OutputDir`        `.\output`
- `-HashAlgorithm`    `SHA256`
- `-ThrottleLimit`    `8`
- `-IncludeSystemPaths` `$false`
- `-DryRun`           `$false`

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

## Returns

The script writes JSON and CSV into the output directory and prints:

- Number of files scanned
- Number of duplicate groups
- Wasted bytes (formatted as GB)
- Paths to the JSON and CSV files

It returns a structured `PSCustomObject` (`$Result`) with the same
counts so you can pipe it to other scripts:

```powershell
$result = & pwsh -File .\scripts\Invoke-NTFSDedupeScan.ps1 -Path .\sample-data
$result.duplicateGroups
$result.totalWastedBytes
```

## Scheduling

Add to Task Scheduler to dedupe weekly, or wrap in a dashboard-friendly
PowerShell workflow for Warp:

```powershell
$json = Get-Content .\output\dedupe-*.json -Raw | ConvertFrom-Json
$json | ConvertTo-Json -Depth 6 | Set-Clipboard  # paste into a Warp card
```

## Troubleshooting

| Symptom                                          | Fix                                                |
|--------------------------------------------------|----------------------------------------------------|
| BLAKE3 module not loaded; falling back...        | Install `b3sum.exe` or stay on SHA256              |
| Access denied on `C:\Windows\...`                | Add `-IncludeSystemPaths` (still read-only) or skip |
| Hash is empty for large files                    | File was unreadable; check the source path        |
| Output dir missing                               | The script creates it; ensure parent is writable  |
