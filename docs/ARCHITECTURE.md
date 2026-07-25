# Architecture

The scanner is intentionally a single PowerShell script with an embedded
C# helper class. The split puts the performance-critical work in compiled
C# (TPL, P/Invoke, BCL hashing) while keeping the orchestration, UX,
and output formatting in PowerShell so it is easy to read and tweak.

## Pipelines

```
   ┌───────────────────────┐
   │ Enumerate             │  Parallel         ┌──────────────────────┐
   │ (C# enumerator via    │  stack recursion ─►│  Scan worker (TPL)   │
   │ Tab + skip-list)      │                    │  - File length       │
   └───────────────────────┘                    │  - NTFS File ID      │
                                                │  - BLAKE3 / SHA256   │
                                                └──────────┬───────────┘
                                                           │
                                              ConcurrentBag<ScanRecord>
                                                           │
                                                ┌──────────▼───────────┐
                                                │ PowerShell grouping  │
                                                │ Group-Object Hash    │
                                                │ Compute wastedBytes  │
                                                │ (only non-hardlinked)│
                                                └──────────┬───────────┘
                                                           │
                                          ┌────────────────▼────────────────┐
                                          │  Warp-dashboard JSON + CSV      │
                                          │  schemaVersion "1.0.0"          │
                                          └─────────────────────────────────┘
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

`Parallel.ForEach` (Task Parallel Library) drives a configurable number
of workers (`-ThrottleLimit`). Each worker:

1. Opens the file with `FILE_SHARE_READ|WRITE|DELETE`,
   `OPEN_EXISTING`, `FILE_FLAG_BACKUP_SEMANTICS`
2. Reads the BY_HANDLE_FILE_INFORMATION via P/Invoke
3. Streams the file through `System.Security.Cryptography.SHA256`
   (or shells `b3sum.exe` for BLAKE3)
4. Writes a `ScanRecord` into a `ConcurrentBag<ScanRecord>`

PowerShell is left to coordinate only, so there is no runspace or
thread-job overhead.

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

### Provenance

- A random `SessionId` GUID is generated per invocation
- `SessionName` is a human-readable `dedupe-<rand>` identifier
- Both flow into JSON output filename, manifest, and the script header
- `session.author` is set to `agent:oz|mannie-greenspan|<sessionId>`

This satisfies the project's traceability rule so every artefact can
be linked back to the AI session that produced it.
