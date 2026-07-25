# Output schema

Every run produces:

| File                                      | Type   |
|-------------------------------------------|--------|
| `output/dedupe-<sessionId>.json`          | JSON   |
| `output/dedupe-<sessionId>.csv`           | UTF-8  |

## JSON v1.0.0

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
  "skippedFolders": [ ... ],
  "scannedFiles": 482103,
  "duplicateGroups": 3127,
  "totalWastedBytes": 18429384711,
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

### Field reference

| Field                | Type     | Meaning                                       |
|----------------------|----------|-----------------------------------------------|
| `schemaVersion`      | string   | Stable; bump on additive change               |
| `session.id`         | UUID     | Per-run identifier                            |
| `session.name`       | string   | Friendly name (`dedupe-<rand>`)               |
| `session.author`     | string   | Signature shape: `agent:<harness>|<user>|<id>`|
| `scannedAt/...`      | ISO-8601 | UTC start / end timestamps                    |
| `durationSeconds`    | int      | Wall-clock elapsed                            |
| `path`               | string   | Root that was scanned                         |
| `hashAlgorithm`      | string   | `SHA256` or `BLAKE3`                          |
| `includeSystemPaths` | bool     | Whether the skip-list was bypassed            |
| `throttleLimit`      | int      | Worker count used                             |
| `skippedFolders`     | string[] | Resolved leaf names that were skipped         |
| `scannedFiles`       | int      | Hashable files examined                       |
| `duplicateGroups`    | int      | Hash-groups with `fileCount > 1`              |
| `totalWastedBytes`   | int      | Sum of `wastedBytes` across non-hardlinked groups |
| `topByWastedBytes`   | object[] | Top 50 group summaries for dashboards         |
| `groups`             | object[] | Full set, one entry per hash-group            |
| `groups[].hardlinked`| bool     | `true` when all files share one inode         |
| `groups[].wastedBytes`| int     | Sum minus one canonical copy                 |

## CSV columns

| Column        | Type | Meaning                              |
|---------------|------|--------------------------------------|
| `Hash`        | str  | Content hash (lower hex)             |
| `FileCount`   | int  | Files in this group                  |
| `UniqueInodes`| int  | Distinct NTFS File IDs               |
| `WastedBytes` | int  | 0 if `Hardlinked=true`                |
| `Hardlinked`  | bool | True if all members share inode      |
| `Path`        | str  | File path                            |
| `Size`        | int  | File size in bytes                   |
| `Inode`       | int  | NTFS File ID                         |

One row per file. CSV is suitable for spreadsheet review or piping
into Excel / DuckDB / pandas.

## Versioning rules

- **Patch** — extra optional fields, no field rename or removal
- **Minor** — additive semantic change (new group, new top-level array)
- **Major** — renaming, removal, or semantically-different field
  (e.g. `WastedBytes` semantics change)
