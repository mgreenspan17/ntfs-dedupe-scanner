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
- **Live UX:** real-time ETA, per-folder progress bar (auto-collapse),
  and live throughput display (instant + 5-s avg + peak MB/s) refreshed
  every second (see [`docs/USAGE.md`](docs/USAGE.md#live-ux))
- **Structured logs:** each session writes a timestamped
  `[YYYY-MM-DD HH:MM:SS] LEVEL : message` log to `./logs/`
  (see [`docs/LOGGING.md`](docs/LOGGING.md))
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

After completion you'll find three artefacts:

- `.\\output\dedupe-<sessionId>.json` — Warp-dashboard-ready payload
- `.\\output\dedupe-<sessionId>.csv` — flat per-file rows
- `.\\logs\ntfs-dedupe-scan-<timestamp>.log` — structured run log

## Parameters

|| Parameter           | Default          | Notes                                          |
||---------------------|------------------|------------------------------------------------|
|| `-Path`             | `C:\`            | Root path to scan                              |
|| `-OutputDir`        | `.\output`       | Where JSON + CSV are written                   |
|| `-LogDir`           | `.\logs`         | Where the structured run log is written        |
|| `-HashAlgorithm`    | `SHA256`         | `SHA256` or `BLAKE3` (needs `b3sum` on PATH)   |
|| `-ThrottleLimit`    | `8`              | Reserved (per-file loop is sequential in 0.3.0)|
|| `-IncludeSystemPaths` | off            | Include `System Volume Information` etc.       |
|| `-DryRun`           | off              | Enumerate + total bytes; do not hash           |

## Live UX (v0.3.0+)

During a full scan the console + Write-Progress panel + log file all
receive live updates every ~1 s:

- ETA prediction rendered as `XXs`, `MM:SS`, or `HH:MM:SS`.
- Per-folder progress bar:
  `[\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2588] 63% (45/71 files) C:\Users\Mannie\Project\Folder`
  Commits to a single 100% line on completion (auto-collapse).
- Throughput: `Speed: 87 MB/s (avg 82 MB/s, peak 104 MB/s)`.

See [`docs/USAGE.md`](docs/USAGE.md#live-ux) and
[`docs/LOGGING.md`](docs/LOGGING.md) for details.

## Outputs at a glance

```json
{
  "schemaVersion": "1.0.0",
  "session": { "id": "...", "name": "dedupe-...", "author": "Mannie Greenspan <Oz agent>" },
  "scannedAt": "2026-07-25T14:34:58Z",
  "completedAt": "2026-07-25T14:39:11Z",
  "durationSeconds": 253,
  "path": "C:\\",
  "hashAlgorithm": "SHA256",
  "scannedFiles": 482103,
  "duplicateGroups": 3127,
  "totalBytes": 4821038124,
  "totalWastedBytes": 18429384711,
  "speedMBps": {
    "instantaneous": 87.0,
    "average5s": 82.4,
    "peak": 104.1
  },
  "perFolder": [
    { "Path": "C:\\Users\\Mannie\\Photos", "Files": 1234, "Bytes": 5129381,
      "DurationSec": 12.4, "FilesPerSec": 99.5 }
  ],
  "topByWastedBytes": [ { ... }, ... ],
  "groups": [ { "hash": "...", "fileCount": 4, "uniqueInodes": 2,
                "wastedBytes": 8294123, "hardlinked": false, "files": [ ... ] } ]
}
```

The `schemaVersion` stays at `1.0.0`; new fields are additive so older
Warp dashboards keep parsing the same fields. See
[`docs/OUTPUT_SCHEMA.md`](docs/OUTPUT_SCHEMA.md) for the full schema.

## Repository layout

```
ntfs-dedupe-scanner/
├── scripts/
│   └── Invoke-NTFSDedupeScan.ps1    # Main entry point
├── docs/
│   ├── ARCHITECTURE.md
│   ├── LOGGING.md
│   ├── OUTPUT_SCHEMA.md
│   ├── SECURITY.md
│   ├── TRANSFER.md
│   ├── FAQ.md
│   └── USAGE.md
├── output/                          # JSON + CSV artefacts
├── logs/                            # Structured run logs (one per session)
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
