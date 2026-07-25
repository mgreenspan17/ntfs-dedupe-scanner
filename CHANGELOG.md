# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/) and the project adheres to
[Semantic Versioning](https://semver.org/).

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
