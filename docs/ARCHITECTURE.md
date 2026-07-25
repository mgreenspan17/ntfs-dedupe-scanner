# Architecture

The scanner is intentionally a single PowerShell script with an embedded
C# helper class. The split puts the performance-critical work in compiled
C# (P/Invoke, BCL hashing, byte-level enumeration) while keeping the
orchestration, UX, output formatting, and structured logging in
PowerShell so it is easy to read and tweak.

## Pipelines

```
   ┌───────────────────────┐
   │ PlanScan (C#)         │  pre-scan, single pass, byte-level
   │ (path, size) pairs    │  ──► bytesTotal + per-folder bins ──►
   │ in DFS order          │                                      │
   └─────────┬─────────────┘                                      │
             │  List<PlanEntry>                                   ▼
             │                                        ┌────────────────────┐
             ▼                                        │  Speed + ETA state │
   ┌───────────────────────┐    per file:             │  instantaneous,   │
   │ Per-folder loop       │ ──► ScanSingleFile ──►   │  5-s moving avg,   │
   │ (PowerShell)          │    ┌──────────┐          │  peak MB/s         │
   │  - folder progress bar│    │ C#       │          └─────────┬──────────┘
   │  - hash + inode       │    │ NTFSHash │                    │
   │  - record into list   │    │ Scanner  │                    ▼
   └─────────┬─────────────┘    └──────────┘         ┌────────────────────┐
             │                                        │  Write-Progress +  │
             │                                        │  per-folder bar    │
             ▼                                        │  + structured log  │
   ┌───────────────────────┐                          └────────────────────┘
   │ PowerShell grouping   │
   │ Group-Object Hash     │
   │ Compute wastedBytes   │
   │ (only non-hardlinked) │
   └─────────┬─────────────┘
             │
   ┌─────────▼─────────────────────────────┐
   │  Warp-dashboard JSON + CSV + log     │
   │  schemaVersion "1.0.0" (additive)    │
   └───────────────────────────────────────┘
```

## Key design decisions

### P/Invoke over `fsutil`

`fsutil file queryFileNameID` spawns a process per call, which would
blow the budget on a full volume scan. Instead we call
`GetFileInformationByHandle` once per file via a single P/Invoke
wrapper bundled in `NTFSHashScanner`. The `BY_HANDLE_FILE_INFORMATION`
struct returns `nFileIndexHigh` and `nFileIndexLow`; concatenating them
yields a 64-bit NTFS File ID (the NTFS equivalent of an inode).

### Threading model

The per-file loop is **sequential in v0.3.0** so that `Write-Progress`,
the ETA, the live speed display, and the per-folder bar all update
deterministically. The `-ThrottleLimit` parameter is preserved for API
compatibility and reserved for a future parallel re-introduction
(starting with a per-folder schedule).

In v0.1.0 the helper exposed a single `Scan()` method that wrapped
`Parallel.ForEach` (Task Parallel Library). v0.2.0 split that into a
lazy enumerator plus a per-file `ScanSingleFile` so PowerShell can
drive one file at a time and update progress between calls. v0.3.0
added `PlanScan` so the byte total is known before hashing starts,
enabling accurate ETA and live throughput.

Each per-file call still does:

1. Opens the file with `FILE_SHARE_READ|WRITE|DELETE`,
   `OPEN_EXISTING`, `FILE_FLAG_BACKUP_SEMANTICS`
2. Reads the BY_HANDLE_FILE_INFORMATION via P/Invoke
3. Streams the file through `System.Security.Cryptography.SHA256`
   (or shells `b3sum.exe` for BLAKE3)
4. Returns a populated `ScanRecord` (or `null` on per-file failure)

PowerShell does all coordination so there is no runspace or thread-job
overhead.

### Hashing strategy

BLAKE3 is preferred when speed is paramount; it is requested by passing
`-HashAlgorithm BLAKE3` and is implemented by shelling out to
`b3sum.exe` (placed on PATH). The fallback path uses `SHA256.Create`
which is always available because it ships in the .NET BCL. The
resulting hex digest is part of the JSON output, so downstream
consumers can rely on it without knowing which path was taken.

### Hard-link detection

NTFS hard-links share the same File ID but have different directory
entries. The scanner treats a hash-group as "hard-linked" iff every
member of the group has the same NTFS File ID. Groups with that flag
are excluded from `totalWastedBytes` since eliminating them would not
recover disk space, only re-link the same inode.

### Skipped paths

Default skip-list (case-insensitive leaf comparison):

| Leaf                          | Reason                                        |
|-------------------------------|-----------------------------------------------|
| `$Recycle.Bin`                | Recycle bin contents                          |
| `System Volume Information`   | VSS / restore partition metadata, ACL-locked  |
| `Config.Msi`                  | Windows Installer temp                        |
| `MSOCache`                    | Office installer cache                        |
| `$WinREAgent`                 | WinRE staging                                 |
| `WindowsApps`                 | Appx packages, byte-identical between users   |
| `Recovery`                    | WinRE binaries                                |
| `PerfLogs`                    | ETW circular logs                             |
| `Documents and Settings`      | Junction                                       |
| `DumpStack.log.tmp`           | BSOD scratch                                  |

Pass `-IncludeSystemPaths` to override.

### Live UX layer

`scripts/Invoke-NTFSDedupeScan.ps1` ships four small helper
functions all written in pure PowerShell 5.1:

- `Format-Eta` — turns an integer second count into `XXs`, `MM:SS`,
  or `HH:MM:SS`.
- `Format-SpeedLine` — builds the `Speed: X (avg Y, peak Z)` string.
- `Show-FolderProgress` — renders the 10-block ASCII bar and,
  optionally, commits a final 100% line on folder completion
  (the per-folder "auto-collapse").
- `Write-ScanLog` — writes `[timestamp] LEVEL : message` to both
  `./logs/.../*.log` and the console. See `docs/LOGGING.md`.

Speed state is held in `$Script:` variables (`InstSpeed`, `AvgSpeed`,
`PeakSpeed`, `LastTick`, `LastBytesDone`, `SpeedHistory`) and is
refreshed every ~1 s by `Update-SpeedState`. ETA is recomputed at
the same cadence from remaining bytes and instantaneous MB/s.

### Skipped paths

Default skip-list (case-insensitive leaf comparison):

|| Leaf                          | Reason                                        |
||-------------------------------|-----------------------------------------------|
|| `$Recycle.Bin`                | Recycle bin contents                          |
|| `System Volume Information`   | VSS / restore partition metadata, ACL-locked  |
|| `Config.Msi`                  | Windows Installer temp                        |
|| `MSOCache`                    | Office installer cache                        |
|| `$WinREAgent`                 | WinRE staging                                 |
|| `WindowsApps`                 | Appx packages, byte-identical between users   |
|| `Recovery`                    | WinRE binaries                                |
|| `PerfLogs`                    | ETW circular logs                             |
|| `Documents and Settings`      | Junction                                      |
|| `DumpStack.log.tmp`           | BSOD scratch                                  |

Pass `-IncludeSystemPaths` to override.

### Provenance

- A random `SessionId` GUID is generated per invocation
- `SessionName` is a human-readable `dedupe-<rand>` identifier
- Both flow into JSON output filename, the log filename, and the script header
- `session.author` is set to `agent:oz|mannie-greenspan|<sessionId>`

This satisfies the project's traceability rule so every artefact
(JSON, CSV, log) can be linked back to the AI session that produced
it.
