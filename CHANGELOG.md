# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/).

## [0.4.1] - 2026-07-25

### Changed

Reviewer-driven correctness + docs polish from PR `#1` review findings
(Codex + CodeRabbit + Copilot). No new top-level JSON fields beyond
`logWriteFailed` is required for this drop; behaviour and observability
improve on top of v0.4.0.

### Fixed

- **BLAKE3 + SHA256 records no longer share buckets.** `ScanRecord`
  carries a new `HashAlgorithm` field stamped per record; the dedupe
  pass now groups records by `(HashAlgorithm, Hash)` so a single
  per-file SHA256 fallback can no longer change which BLAKE3 records
  match each other. Schema is unchanged but grouping semantics are
  documented in `docs/OUTPUT_SCHEMA.md` and `docs/ARCHITECTURE.md`.
- **`b3sum` invokes can no longer deadlock on filled redirected
  pipes.** `Blake3Hex` now drains stdout + stderr asynchronously
  (`BeginOutputReadLine` + `OutputDataReceived` / `ErrorDataReceived`)
  with `ManualResetEvent` waits on completion, then applies the 30 s
  `WaitForExit` + `Kill` policy if the process hangs.
- **Lazy enumeration access denials no longer abort the scan.**
  `Enumerate` now passes `EnumerationOptions { IgnoreInaccessible = true }`
  to `Directory.EnumerateFiles` / `EnumerateDirectories` so a single
  locked folder cannot derail a full-volume walk.
- **Final-file correctness.** `$bytesDone` and `$folderBytes` advance
  even on hash failure so the last `100%` line, the remaining-bytes
  number, and the ETA are accurate on the unreadable last file of a
  folder. `$done` and `$attempted` are now tracked separately.
- **First-file speed no longer pollutes peak.** The speed/ETA tick is
  no longer forced on `$done -eq 1`; the first sample is taken at the
  next normal 1-second boundary.
- **Folder-bar auto-collapse renders exactly one 100% line.** The
  in-place `\r + NoNewline` render is skipped on the last file of a
  folder so the committing 100% line is the only row that lands.
- **Log writes no longer silently lost.** `Write-ScanLog` records the
  first append failure into `$Script:LogWriteFailed`, emits a one-time
  `Write-Warning`, and carries the flag into the structured log
  summary line and the script's return `PSCustomObject`.
- **Concurrent runs no longer clobber each other's logs.** The
  log filename now embeds the per-run `SessionId` so two scans started
  in the same second do not truncate one another's audit trail.
- **`Resolve-Path` is null-safe** before `.ProviderPath` is accessed
  for `-LogDir`; an unresolvable log directory now throws a clear
  error instead of a null-valued expression error.
- **`Write-Warning` at the first BLAKE3 fallback is a single string**
  (the previous `+` to concatenate a second sentence leaked the second
  sentence on the success output stream).
- **`EnumerationOptions` swap-in avoids `Add-Type` compile error on
  Windows PowerShell 5.1 / .NET Framework 4.x.** The PS 5.1 C# compiler
  pipeline does not resolve `System.IO.EnumerationOptions` reliably,
  so the script now materialises the file + directory lists and wraps
  each call in typed `try/catch` for `UnauthorizedAccessException`,
  `DirectoryNotFoundException`, and `IOException`. Behaviour is
  equivalent to `EnumerationOptions { IgnoreInaccessible = true }`
  (a single locked folder can no longer abort the whole scan).
- **JSON, CSV, and log file are all written without a UTF-8 BOM.**
  `Out-File -Encoding UTF8`, `Export-Csv -Encoding UTF8`, AND
  `Add-Content -Encoding UTF8` (used by the structured log helper)
  all prepend a BOM (EF BB BF) in PS 5.1, which trips strict
  downstream parsers (`json.load`, `pandas.read_csv` without
  `encoding='utf-8-sig'`, jq, DuckDB csv, anything grepping for
  a leading `[` in the file). The script now uses
  `[System.IO.File]::WriteAllText` for JSON/CSV and
  `[System.IO.File]::AppendAllText` for the log, both with an
  explicit UTF-8-without-BOM encoding.
- **`logWriteFailed=...` is now JSON-style lowercase** in the summary
  log line. PowerShell's default `[bool].ToString()` returns
  `"True"/"False"` (capitalized), so the v0.4.1 first cut produced
  `logWriteFailed=False`. The script now resolves the value into
  `$summaryLogWriteFailed` (`"true"` or `"false"`) before formatting
  so log parsers reading for `logWriteFailed=true` keep working
  without PowerShell-language special-casing.
- **Bare `(if ...) ` value expression replaced with a local variable.**
  PowerShell 5.1 does not support `(if A { 'a' } else { 'b' })` as a
  value expression (that is a PowerShell 7+ feature). The summary log
  line's `hashAlgorithmFallback` ternary is now resolved into
  `$summaryAlgoFallback` first.
- **Group `hash` field no longer carries an `"algo|" prefix`.** When
  the duplicate pass was first switched to a `(HashAlgorithm, Hash)`
  bucket key in the v0.4.1 draft, the script assigned the entire key
  string (`"blake3|<hash>"`) to the JSON `groups[].hash` field. The
  field is now split into `groups[].hashAlgorithm` (string) +
  `groups[].hash` (64 hex chars) and `groups[]` returns clean values
  dashboards can compare directly.

### Added

- `ScanRecord.HashAlgorithm` (`"blake3"` or `"sha256"`, additive; older
  consumers can ignore it).
- New top-level `attemptedFiles` field in the JSON payload
  (`scannedFiles` keeps meaning "successful record count";
  `attemptedFiles` includes per-file hash failures).
- `$Script:LogWriteFailed` propagated into the summary log line as
  `logWriteFailed=true` and into the script's return `PSCustomObject`
  as a `logWriteFailed` boolean.
- `$Script:Blake3FallbackCount` propagated into the return
  `PSCustomObject` so callers can branch on fallback count without
  re-reading the JSON.

### Corrected

- `README.md`, `docs/ARCHITECTURE.md`, `docs/OUTPUT_SCHEMA.md`,
  `docs/USAGE.md`, and `docs/LOGGING.md` all updated so that:
  - Markdown parameter + skipping tables no longer carry an extra
    leading `|` per row.
  - The example JSON `schemaVersion` is `1.0.1`, not `1.0.0`, and
    the embedded embedded JSON example surfaces
    `hashAlgorithmFallback`, `blake3FallbackCount`, and
    `attemptedFiles`.
  - The example `perFolder` entry uses lowercase keys (which is what
    `ConvertTo-Json` actually emits), not PascalCase.
  - The console + log cadence is documented accurately: console +
    `Write-Progress` refresh every ~1 s; the structured log file
    throttles speed + ETA snapshots to every ~5 s.
  - The CSV `ConvertFrom-Csv` example passes
    `-Header Timestamp, Level, Message` so the first log row is
    treated as data, not as a header.
  - Log files are described as **UTF-8 text** (BOM-free), not ASCII;
    the per-folder progress bar is described as a Unicode
    block-character bar (`█` U+2588 + `░` U+2591), not ASCII.
  - `docs/ARCHITECTURE.md` no longer carries the duplicate
    **Skipped paths** section that the codebase-cleanup linter
    flagged.

### Notes

- Still read-only / Windows PowerShell 5.1 safe.
- The JSON `schemaVersion` stays at `1.0.1` from v0.4.0: v0.4.1 is
  additive, so consumers parsing `schemaVersion=1.0.1` output from
  this branch keep working without changes.

## [0.4.0] - 2026-07-25

### Changed
- BLAKE3 is now the primary hash algorithm with explicit, visible SHA256
  fallback. Behaviors:
  - When `-HashAlgorithm BLAKE3` is requested and `b3sum.exe` is on
    PATH, every file is hashed with BLAKE3.
  - If `b3sum.exe` is missing entirely, the whole run downgrades to
    SHA256 (warning printed at start).
  - If a specific file's `b3sum` invocation exits non-zero, times out
    (30 s), prints to stderr, or returns an empty token, the C# helper
    re-hashes that one file with SHA256 and stamps
    `ScanRecord.UsedFallback=true`. The PS layer increments
    `blake3FallbackCount` for every fallback, prints a console warning
    the FIRST time the count crosses 1, and surfaces the count in the
    JSON report and on the summary line.
- JSON schema bumped additive: `1.0.0 -> 1.0.1`.
  - New top-level fields: `hashAlgorithmFallback` (string|null; set to
    `"SHA256"` whenever any file fell back, `null` otherwise) and
    `blake3FallbackCount` (int).
  - Existing field names, types, and meanings are unchanged.

### Added
- C# `ScanRecord.UsedFallback` (bool) - additive field; older code
  paths can ignore it.
- `docs/OUTPUT_SCHEMA.md`: schema-version bumped to `1.0.1`, with a
  new *v0.4.0 additions* section, expanded field-reference table
  covering `hashAlgorithmFallback` and `blake3FallbackCount`,
  versioning-rule clarification (minor = additive observability signal
  with optional `schemaVersion` roll), and a v1.0.0 -> v1.0.1
  migration guide for downstream dashboards.
- Structured-log vocabulary: `summary; ... blake3FallbackCount=...,
  hashAlgorithmFallback=...` line emitted on every run, plus a
  one-time `WARN blake3 fallbacks detected` log row when the count
  is non-zero. See `docs/LOGGING.md` for the full vocabulary.

## [0.3.0] - 2026-07-25

### Added
- Progress UX bundle in `scripts/Invoke-NTFSDedupeScan.ps1`:
  - Real-time **ETA prediction** (rendered as `XXs`, `MM:SS`, or
    `HH:MM:SS`) refreshed from remaining bytes + instantaneous MB/s
    every ~1 s.
  - **Per-folder** Unicode block-character bar (`█` U+2588 + `░`
    U+2591) with auto-collapse to a committed 100% line on
    completion.
  - **Live throughput** display: instantaneous 1-s speed, 5-s moving
    average, and peak across the whole run
    (`Speed: 87 MB/s (avg 82 MB/s, peak 104 MB/s)`).
  - **Structured log file** output to `./logs/ntfs-dedupe-scan-<ts>.log`
    with `[YYYY-MM-DD HH:MM:SS] LEVEL : message` rows at INFO / WARN /
    ERROR / DEBUG. Logs session start, pre-scan counts, per-folder
    start/complete events, throttled speed + ETA snapshots, hashing
    completion, and a one-line final summary.
- New C# helper surface:
  - `PlanEntry` class + `PlanScan(rootPath, skipNames)` method
    materialize `(path, size)` pairs in DFS order so byte accounting
    can drive ETA + throughput without re-walking the tree.
  - `ScanSingleFile`, `CountFiles`, `EnumerateFiles` for the hashing
    loop.
- New PowerShell parameter `-LogDir` (defaults to `./logs`).
- JSON payload gains `totalBytes`, `speedMBps` (instantaneous + 5-s
  avg + peak), and `perFolder` (per-folder stats: files / bytes /
  duration / files-per-second).
- Documentation: new `docs/LOGGING.md`, plus updates to `README.md`,
  `ARCHITECTURE.md`, `USAGE.md`, and `OUTPUT_SCHEMA.md`.

### Changed
- Per-file loop is now sequential so `Write-Progress`, the ETA, the
  live speed display, and the per-folder bar all update deterministically.
  `-ThrottleLimit` is preserved for API compatibility and reserved for
  a future parallel re-introduction.
- Replaced the earlier `Parallel.ForEach` bulk scan with a sequential
  per-file loop.
- Skip-list behavior, hard-link detection, JSON/CSV output format, and
  dedupe logic are unchanged.

### Notes
- Progress UX updates refresh every ~1 s. Log entries for speed /
  ETA are throttled to once every ~5 s to keep the log readable on
  long full-volume runs.

## [0.2.0] - 2026-07-25

### Added
- Pre-scan file counter + live `Write-Progress` bar.
- Per-file hashing loop driven by the new C# helper
  `NTFSHashScanner.ScanSingleFile(file, blake3Exe)`.
- Public C# `EnumerateFiles` and `CountFiles` helpers used by the
  PowerShell entry point.

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
  - Duplicate grouping by hash + inode, with wasted-byte computation
    only for groups whose member count exceeds their unique-inode
    count.
  - Warp-dashboard-ready JSON output (schema `1.0.0`) and mirror CSV.
- Documentation: README, ARCHITECTURE.md, OUTPUT_SCHEMA.md, USAGE.md.
- Apache-2.0 / MIT LICENSE.

### Notes
- Each invocation mints a fresh session UUID and bakes it into the
  output filename and JSON `session.id`, satisfying the project's
  traceability rule.
- Author signature `agent:oz|mannie-greenspan|<sessionId>` is written
  to the JSON payload and to the script header so every artefact can
  be traced.
