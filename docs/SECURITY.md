# Security & safety

The scanner is **strictly read-only**. No file is opened in write mode,
modified, moved, renamed, or deleted. The script refuses to follow
write-class instructions and never invokes any API that could mutate
filesystem state.

## What is read

- File contents (read access only, streamed)
- NTFS metadata via `GetFileInformationByHandle`
- File attributes, sizes, timestamps

## What is *not* done

- No `CreateFile` with `GENERIC_WRITE`
- No `Move-Item`, `Remove-Item`, `Rename-Item`, `Set-Content`
- No registry writes
- No remote network calls
- No execution of user-supplied paths as code
- No symbolic link traversal that could escape the requested `-Path`

## File-handle hygiene

Every open is paired with `SafeFileHandle` disposal and wraps the
`using`/`try-finally` pattern. Even on per-file exceptions the handle
is closed; threads never leak. Each handle is opened with
`FILE_SHARE_READ|WRITE|DELETE` so background services (e.g. indexer,
defender) are not blocked.

## Provenance & traceability

To satisfy the project's "every uploaded file gets a session id and
author signature" rule, every JSON payload carries:

- `session.id`        — a fresh UUID v4 per invocation
- `session.name`      — `dedupe-<rand>`
- `session.author`    — `agent:oz|mannie-greenspan|<id>`

These are embedded in the JSON itself (not only the filename) so a
copy-pasted payload always carries who produced it.

## Reuse on shared systems

- The script is safe to run on multi-user NTFS volumes
- It does not enumerate across drive boundaries beyond the requested
  `-Path` (drive roots accept only a single letter)
- Permission errors are caught per-file and recorded silently; no
  crash, no escalation

## Reporting vulnerabilities

Please open a GitHub issue or contact via the repo's `SECURITY.md`
contact instructions once you fork the project.
