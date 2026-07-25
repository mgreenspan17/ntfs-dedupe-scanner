# Output schema

Every run produces:

| File                                         | Type             |
|----------------------------------------------|------------------|
| `output/dedupe-<sessionId>.json`             | JSON             |
| `output/dedupe-<sessionId>.csv`              | UTF-8            |
| `logs/ntfs-dedupe-scan-<timestamp>.log`      | ASCII text log   |

`sessionId` is a fresh UUID per run.
`timestamp` is `yyyyMMddTHHmmss` of the run start.

## JSON v1.0.0 (current)

```json
{
  "schemaVersion": "1.0.0",
  "session": {
    "id":   "019f99b3-6809-7dd8-b347-9ae1ae9e3fbc",
    "name": "dedupe-43182",
    "author": "agent:oz|mannie-greenspan|019f99b3-6809-7dd8-b347-9ae1ae9e3fbc",
    "host":  "WIN-ABCD1234",
    "agentRunId": "019f99b3-6809-7dd8-b347-9ae1ae9e3fbc"
  },
  "scannedAt": "2026-07-25T14:34:58Z",
  "completedAt": "2026-07-25T14:39:12Z",
  "durationSeconds": 254,
  "path": "C:\\",
  "hashAlgorithm": "SHA256",
  "includeSystemPaths": false,
  "throttleLimit": 8,
  "skippedFolders": [ "$Recycle.Bin", "System Volume Information", ... ],
  "scannedFiles": 482103,
  "duplicateGroups": 3127,
  "totalBytes": 12482981023,
  "totalWastedBytes": 18429384711,
  "speedMBps": {
    "instantaneous": 87.0,
    "average5s":     82.4,
    "peak":          104.1
  },
  "perFolder": [
    {
      "path":        "C:\\Users\\manni\\Photos",
      "files":       1234,
      "bytes":       5129381,
      "durationSec": 12.4,
      "filesPerSec": 99.5
    }
  ],
  "topByWastedBytes": [ /* 50 groups, descending by wastedBytes */ ],
  "groups": [
    {
      "hash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      "fileCount": 4,
      "uniqueInodes": 2,
      "wastedBytes": 8294123,
      "hardlinked": false,
      "files": [
        { "path": "C:\\Users\\manni\\Pictures\\IMG_0001.jpg", "inode": 1234567890, "size": 8294123 },
        { "path": "D:\\Backup\\Pictures\\IMG_0001.jpg",       "inode": 9876543210, "size": 8294123 }
      ]
    }
  ]
}
```

## v0.3.0 additions

The schemaVersion stayed at `1.0.0`. v0.3.0 added three purely additive
fields:

- `totalBytes` — sum of bytes across all enumerated files
- `speedMBps` — instantaneous, 5-s moving average, peak MB/s during the run
- `perFolder` — array of one entry per folder (DFS order) with files / bytes
  / wall-clock duration / files-per-second

Older consumers ignore these. The `schemaVersion` does **not** roll for
additive field changes; it rolls only for breaking changes. See
`../CHANGELOG.md` for the full changelog and
`../docs/LOGGING.md` for the structured-log vocabulary that mirrors
these counters.

### Field reference

| Field                       | Type     | Meaning                                          |
|-----------------------------|----------|--------------------------------------------------|
| `schemaVersion`             | string   | Stable; only bumped on breaking change           |
| `session.id`                | UUID     | Per-run identifier                               |
| `session.name`              | string   | Friendly name (`dedupe-<rand>`)                  |
| `session.author`            | string   | Signature shape: `agent:<harness>|<user>|<id>`   |
| `agentRunId`                | UUID     | Mirrors `session.id` for downstream dashboards   |
| `scannedAt` / `completedAt` | ISO-8601 | UTC start / end timestamps                       |
| `durationSeconds`           | int      | Wall-clock elapsed                               |
| `path`                      | string   | Root that was scanned                            |
| `hashAlgorithm`             | string   | `SHA256` or `BLAKE3`                             |
| `includeSystemPaths`        | bool     | Whether the skip-list was bypassed               |
| `throttleLimit`             | int      | Worker count reserved (sequential in 0.3.0)     |
| `skippedFolders`            | string[] | Resolved leaf names that were skipped            |
| `scannedFiles`              | int      | Hashable files examined                          |
| `duplicateGroups`           | int      | Hash-groups with `fileCount > 1`                 |
| `totalBytes`                | int      | Sum of bytes across all enumerated files         |
| `totalWastedBytes`          | int      | Sum of `wastedBytes` across non-hardlinked groups |
| `speedMBps.instantaneous`   | float    | MB/s over the most recent ~1 s window            |
| `speedMBps.average5s`       | float    | MB/s 5-s moving average                          |
| `speedMBps.peak`            | float    | Highest instantaneous speed observed             |
| `perFolder[]`               | object[] | One entry per folder (DFS order)                 |
| `perFolder[].path`          | string   | Absolute path                                    |
| `perFolder[].files`         | int      | Files in that folder                             |
| `perFolder[].bytes`         | int      | Total bytes for that folder                      |
| `perFolder[].durationSec`   | float    | Wall-clock seconds spent on that folder          |
| `perFolder[].filesPerSec`   | float    | `files / durationSec`                            |
| `topByWastedBytes`          | object[] | Top 50 group summaries for dashboards            |
| `groups`                    | object[] | Full set, one entry per hash-group               |
| `groups[].hardlinked`       | bool     | `true` when all files share one inode            |
| `groups[].wastedBytes`      | int      | Sum minus one canonical copy                     |

## CSV columns

| Column         | Type | Meaning                              |
|----------------|------|--------------------------------------|
| `Hash`         | str  | Content hash (lower hex)             |
| `FileCount`    | int  | Files in this group                  |
| `UniqueInodes` | int  | Distinct NTFS File IDs               |
| `WastedBytes`  | int  | 0 if `Hardlinked=true`                |
| `Hardlinked`   | bool | True if all members share inode      |
| `Path`         | str  | File path                            |
| `Size`         | int  | File size in bytes                   |
| `Inode`        | int  | NTFS File ID                         |

One row per file. CSV is suitable for spreadsheet review or piping
into Excel / DuckDB / pandas.

## Versioning rules

- **Patch** — extra optional fields, no field rename or removal
  (v0.3.0 is of this kind: `totalBytes`, `speedMBps`, `perFolder`
  are all additive).
- **Minor** — additive semantic change (new group, new top-level array).
- **Major** — renaming, removal, or semantically-different field
  (e.g. `WastedBytes` semantics change).

Dashboards should ignore fields they do not understand and rely only
on the fields they care about.
