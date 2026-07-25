# Logging

As of **v0.3.0**, every `Invoke-NTFSDedupeScan.ps1` run writes a
structured text log in addition to the JSON/CSV artefacts.

## Where

| File                                         | Default |
|----------------------------------------------|---------|
| `./logs/ntfs-dedupe-scan-<timestamp>.log`    | `./logs` |

`timestamp` is `yyyyMMddTHHmmss` (UTC-naive, local time machine clock).
A second parameter `-LogDir` lets you redirect the log to any folder.

If a log with the same timestamp already exists (rare machine-clock
collision), the file is truncated before writing so each run starts
with a fresh stream.

## Format

Each line is a flat ASCII record, one per event:

```
[YYYY-MM-DD HH:MM:SS] LEVEL : message
```

Example:

```
[2026-07-25 11:29:19] INFO  : ntfs-dedupe-scan starting; session=dedupe-12543 id=18d7a88f-...
[2026-07-25 11:29:19] INFO  : log path resolved; logFile=C:\...ntfs-dedupe-scan-20260725T112919.log
[2026-07-25 11:29:19] INFO  : pre-scan complete; candidates=6 bytesTotal=135046 elapsedSec=0.03
[2026-07-25 11:29:19] INFO  : hashing start; total=6 bytesTotal=135046 folders=1
[2026-07-25 11:29:19] INFO  : folder start; path=C:\...sample-data files=6
[2026-07-25 11:29:19] INFO  : folder complete; path=C:\...sample-data files=6 bytes=135046 durationSec=0.23
[2026-07-25 11:29:19] INFO  : hashing complete; hashed=6 records=6 errors=0 bytesDone=135046 elapsedSec=0.30
[2026-07-25 11:29:19] INFO  : summary; scannedFiles=6 duplicateGroups=1 hardlinkedGroups=0 wastedBytes=108020 totalBytes=135046 ...
[2026-07-25 11:29:19] INFO  : ntfs-dedupe-scan end
```

## Levels

The script emits at the following severities:

| Level   | When                                                              |
|---------|-------------------------------------------------------------------|
| INFO    | Session start, lifecycle events, throttled metric snapshots, end  |
| WARN    | Reserved for recoverable hiccups; emitted today only on the b3sum fallback |
| ERROR   | Reserved; not currently emitted by the script itself                |
| DEBUG   | Reserved; not currently emitted (set `-Verbose` upstream to inspect) |

The console mirrors the file but colour-coded by level (Cyan / Yellow / Red / DarkGray).

## Event vocabulary

The log vocabulary is stable so dashboards can parse end events
predictably. Each message is a free-form string followed by a `;`-separated
list of `key=value` pairs that are trivial to grep.

| Logical event         | `key=value` pairs (in addition to level/free-text)               |
|-----------------------|-------------------------------------------------------------------|
| session start         | `session`, `id`, `path`, `algo`, `threads`, `dryRun`             |
| log path resolved     | `logFile`                                                        |
| pre-scan start        | `path`                                                           |
| pre-scan complete     | `candidates`, `bytesTotal`, `elapsedSec`                         |
| hashing start         | `total`, `bytesTotal`, `folders`                                 |
| folder start          | `path`, `files`                                                  |
| folder complete       | `path`, `files`, `bytes`, `durationSec`                          |
| speed update          | (verbatim `Speed: ... MB/s (avg ... MB/s, peak ... MB/s)`)        |
| eta update            | `remainingBytes`, `eta`                                          |
| hashing complete      | `hashed`, `records`, `errors`, `bytesDone`, `elapsedSec`         |
| summary               | `scannedFiles`, `duplicateGroups`, `hardlinkedGroups`, `wastedBytes`, `totalBytes`, `errors`, `folders`, `elapsedSec`, `avgSpeedMBps`, `peakSpeedMBps`, `jsonPath`, `csvPath`, `logPath` |
| session end           | (literal `ntfs-dedupe-scan end`)                                 |

## Throttling

Speed and ETA snapshots refresh at most once every ~5 s in the log
file so a 5-minute full-volume scan produces a manageable stream. The
console `Write-Progress` panel, however, is refreshed every ~1 s so the
operator's view stays smooth.

## Relationship to the JSON payload

Each summary event carries the same counters that land in
`output/dedupe-<sessionId>.json` so the log file is a text-mirrored
manifest of the run. Differences are intentional:

- The log carries the *transition* events (`folder start`,
  `folder complete`, speed/ETA snapshots) that the JSON does not.
- The JSON carries the duplicate groups; the log does not list every
  group, just the high-level totals in the `summary` event.

## Failures

The `Write-ScanLog` helper wraps `Add-Content` in a `try/catch` so a
locked/unwritable log file does not abort the scan. Look for the line
prefix `[timestamp] ERROR : ...` only when the script emits WARN or
ERROR directly (none today); the *missing* log file itself is the
canonical signal that the run could not write the log.
