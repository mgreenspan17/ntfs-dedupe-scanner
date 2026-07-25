# ntfs-dedupe-scanner

A read-only NTFS duplicate-file scanner optimized for Warp dashboards.

It walks any NTFS volume (defaults to `C:\`), computes a content hash for every
file, retrieves the NTFS File ID (the inode-equivalent exposed by NTFS),
groups files by hash, and distinguishes true content duplicates from
hard-linked copies. Output is a single JSON document shaped for Warp
dashboards plus a CSV mirror for spreadsheet review.

> Read-only. No file is opened in write mode, modified, moved, or deleted.

## Highlights

- **Fast:** 2-5 minutes on a populated `C:\` (NVMe + 8+ threads)
- **Safe:** P/Invoke to `GetFileInformationByHandle` opens files with
  `FILE_SHARE_READ|WRITE|DELETE` and zero write access
- **Hashing:** BLAKE3 when `b3sum` is on PATH, SHA256 (BCL) otherwise
- **Hard-link aware:** Groups with a single NTFS File ID are flagged
  `hardlinked: true` and excluded from wasted-byte totals
- **Warp-dashboard JSON:** stable, versioned schema (see
  [`docs/OUTPUT_SCHEMA.md`](docs/OUTPUT_SCHEMA.md))
- **CSV mirror:** one row per file for spreadsheet review

## Quick start

```powershell
# Defaults: scan C:\, write to .\output, SHA256 hash, 8 threads
pwsh -File .\scripts\Invoke-NTFSDedupeScan.ps1

# Smaller test on a sample folder with BLAKE3
pwsh -File .\scripts\Invoke-NTFSDedupeScan.ps1 `
     -Path .\sample-data `
     -HashAlgorithm BLAKE3 `
     -OutputDir .\output
```

After completion you'll find two files in `.\output\`:

- `dedupe-<sessionId>.json` — Warp-dashboard-ready payload
- `dedupe-<sessionId>.csv` — flat per-file rows

## Parameters

| Parameter           | Default          | Notes                                          |
|---------------------|------------------|------------------------------------------------|
| `-Path`             | `C:\`            | Root path to scan                              |
| `-OutputDir`        | `.\output`       | Where JSON + CSV are written                   |
| `-HashAlgorithm`    | `SHA256`         | `SHA256` or `BLAKE3` (needs `b3sum` on PATH)   |
| `-ThrottleLimit`    | `8`              | Max parallel hash workers                      |
| `-IncludeSystemPaths` | off            | Include `System Volume Information` etc.       |
| `-DryRun`           | off              | Enumerate and report counts without hashing    |

## Outputs at a glance

```json
{
  "schemaVersion": "1.0.0",
  "session": { "id": "...", "name": "dedupe-...", "author": "Mannie Greenspan <Oz agent>" },
  "scannedAt": "2026-07-25T14:34:58Z",
  "path": "C:\\",
  "hashAlgorithm": "SHA256",
  "scannedFiles": 482103,
  "duplicateGroups": 3127,
  "totalWastedBytes": 18429384711,
  "topByWastedBytes": [ { ... }, ... ],
  "groups": [ { "hash": "...", "fileCount": 4, "uniqueInodes": 2, "wastedBytes": 8294123, "hardlinked": false, "files": [ ... ] } ]
}
```

See [`docs/OUTPUT_SCHEMA.md`](docs/OUTPUT_SCHEMA.md) for the full schema.

## Repository layout

```
ntfs-dedupe-scanner/
├── scripts/
│   └── Invoke-NTFSDedupeScan.ps1    # Main entry point
├── docs/
│   ├── ARCHITECTURE.md
│   ├── OUTPUT_SCHEMA.md
│   └── USAGE.md
├── output/                          # Generated reports land here
├── sample-data/                     # Throwaway folder for fast tests
├── README.md
├── CHANGELOG.md
├── LICENSE
└── .gitignore
```

## Provenance

- **Session id:** UUID generated each run, embedded in every output file and log line
- **Author signature:** `agent:oz|mannie-greenspan|<sessionId>` written to JSON `session.author`
- **Source provenance:** JSON records `path`, `hashAlgorithm`, `scannedAt`
- **Hard-link detection:** NTFS File IDs come straight from
  `GetFileInformationByHandle`, not heuristically derived

## License

MIT - see [`LICENSE`](LICENSE).
