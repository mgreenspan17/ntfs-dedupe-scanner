# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/).

## [0.3.0] - 2026-07-25

### Added
- Progress UX bundle in `scripts/Invoke-NTFSDedupeScan.ps1`:
  - Real-time **ETA prediction** (rendered as `XXs`, `MM:SS`, or
    `HH:MM:SS`) refreshed from remaining bytes + instantaneous MB/s
    every ~1 s.
  - **Per-folder** `[\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2588\u2588]` ASCII bar with auto-collapse to a committed 100% line on completion.
  - **Live throughput** display: instantaneous 1-s speed, 5-s moving
    average, and peak across the whole run
    (`Speed: 87 MB/s (avg 82 MB/s, peak 104 MB/s)`).
  - **Structured log file** output to `./logs/ntfs-dedupe-scan-<ts>.log`
    with `[YYYY-MM-DD HH:MM:SS] LEVEL : message` rows at INFO / WARN /
    ERROR / DEBUG. Logs the session start, pre-scan counts, per-folder
    start/complete events, throttled speed + ETA snapshots, hashing
    completion, and a one-line final summary.
- New C# helper surface:
  - `PlanEntry` class + `PlanScan(rootPath, skipNames)` method
    materialize `(path, size)` pairs in DFS order so byte accounting
    can drive ETA + throughput without re-walking the tree.
- New PowerShell parameter `-LogDir` (defaults to `./logs`).
- JSON payload gains `totalBytes`, `speedMBps` (instantaneous + 5-s avg
  + peak), and `perFolder` (per-folder stats: files / bytes /
  duration / files-per-second). Existing schema semantics are
  unchanged: `schemaVersion` stays `1.0.0` and the new fields are
  purely additive so older dashboards keep parsing the same fields.
- Documentation: new `docs/LOGGING.md`, expanded `README.md`, plus
  updates to `ARCHITECTURE.md`, `USAGE.md`, and `OUTPUT_SCHEMA.md`.

### Changed
- Per-file loop is now sequential so `Write-Progress`, the ETA, the
  live speed display, and the per-folder bar all update deterministically.
  `-ThrottleLimit` is preserved for API compatibility and reserved for
  a future parallel re-introduction.
- Skip-list behavior, hard-link detection, JSON/CSV output format,
  and dedupe logic are unchanged.

### Notes
- All progress UX updates refresh every ~1 s. Log entries for speed /
  ETA are throttled to once every ~5 s to keep the log readable on
  long full-volume runs.

## [0.2.0] - 2026-07-25

### Added
- Pre-scan file counter + live `Write-Progress` bar.
- Per-file hashing loop driven by the new C# helper
  `NTFSHashScanner.ScanSingleFile(file, blake3Exe)`.
- Public C# `EnumerateFiles` and `CountFiles` helpers used by the
  PowerShell entry point.

## [Unreleased]

## [0.4.0] - 2026-07-25

### Changed
- Make BLAKE3 the primary hash algorithm with explicit, visible SHA256
  fallback. Behaviors:
  - When `-HashAlgorithm BLAKE3` is requested and `b3sum.exe` is on
    PATH, every file is hashed with BLAKE3.
  - If `b3sum.exe` is missing entirely, the whole run downgrades to
    SHA256 (warning printed at start).
  - If a specific file's `b3sum` invocation exits non-zero, times out
    (30 s), prints to stderr, or returns an empty token, the C# helper
    re-hashes that one file with SHA256 and stamps
    `ScanRecord.UsedFallback=true`.
  - The PS layer increments `blake3FallbackCount` for every fallback,
    prints a console warning the FIRST time the count crosses 1, and
    surfaces the count in the JSON report and on the summary line.
- JSON schema bumped additive: `1.0.0 -> 1.0.1`.
  - New fields: `hashAlgorithmFallback` (string|null; `SHA256` when
    fallback occurred, `null` otherwise) and `blake3FallbackCount` (int).
  - Existing field names, types, and meanings are unchanged.

### Added
- C# `ScanRecord.UsedFallback` (bool) — additive field; older code
  paths can ignore it.

## [0.3.0] - 2026-07-25

### Added
- Real-time ETA prediction refreshed every 1 s from remaining bytes and
  current moving-average MB/s speed.
- Per-folder progress bar (10-block ASCII) that commits to a 100% line
  on completion and auto-collapses afterwards.
- Live throughput display (1-s instantaneous, 5-s moving average, peak).
- Structured log file output under `./logs/ntfs-dedupe-scan-<ts>.log`
  with timestamps and INFO/WARN/ERROR/DEBUG levels.
- C# helpers `PlanEntry` and `PlanScan` to materialise `(path, size)`
  pairs for byte accounting and ETA.

## [0.2.0] - 2026-07-25

### Changed
- Replaced bulk `Parallel.ForEach` with a per-file sequential loop.
  Per-folder progress bars + per-file progress activity are now
  deterministic. `ThrottleLimit` is reserved for a future
  parallelism pass.

### Added
- C# helpers `ScanSingleFile`, `CountFiles`, `EnumerateFiles`.

## [0.1.0] - 2026-07-25

### Added
- Initial scaffold of `ntfs-dedupe-scanner` PowerShell tool.
- `scripts/Invoke-NTFSDedupeScan.ps1`:
  - Read-only NTFS enumeration with default Windows skip-list
    (`$Recycle.Bin`, `System Volume Information`, etc.).
  - Embedded C# helper class `NTFSHashScanner` using:
    - `GetFileInformationByHandle` P/Invoke for NTFS File IDs
    - `System.Security.Cryptography.SHA256` (BCL) hashing
    - `b3sum.exe` shelling when `-HashAlgorithm BLAKE3` is requested
    - `System.Threading.Tasks.Parallel.ForEach` for parallel I/O
  - Duplicate grouping by hash + inode, with wasted-byte computation only
    for groups whose member count exceeds their unique-inode count.
  - Warp-dashboard-ready JSON output (schema `1.0.0`) and mirror CSV.
- Documentation: README, ARCHITECTURE.md, OUTPUT_SCHEMA.md, USAGE.md.
- Apache-2.0 / MIT LICENSE.

### Notes
- Each invocation mints a fresh session UUID and bakes it into the output
  filename and JSON `session.id`, satisfying the project's traceability rule.
- Author signature `agent:oz|mannie-greenspan|<sessionId>` is written to JSON
  payload and to the script header so every artefact can be traced.
