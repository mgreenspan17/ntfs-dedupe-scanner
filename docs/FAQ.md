# FAQ

### Why P/Invoke instead of `fsutil`?

`fsutil file queryFileNameID` spawns a process per call which dominates
the runtime on a full-volume scan. The bundled C# class calls
`GetFileInformationByHandle` once per file with no process startup
overhead — orders of magnitude faster on a hot NTFS scan loop.

### Why hard-link aware?

NTFS hard-links share a single inode. Removing one of two hard-linked
files does **not** free disk space — only unlinks the entry. Reporting
those as "wasted" bytes is misleading; the scanner flags them
`hardlinked:true` and excludes them from `totalWastedBytes`.

### Why SHA256 default when BLAKE3 is faster?

`SHA256` ships with the .NET BCL and is always present without
extra dependencies. BLAKE3 is automatically used when `-HashAlgorithm
BLAKE3` is requested *and* `b3sum.exe` is on PATH. The output schema
records which algorithm produced each digest, so consumers don't
have to care which one ran.

### Why 8 threads by default?

That balances I/O contention on consumer NVMe drives while still
keeping all cores warm. Bump to 16 on fast SSDs and you may see
additional throughput at the cost of higher CPU.

### How does it get the NTFS File ID (inode)?

`GetFileInformationByHandle` returns a `BY_HANDLE_FILE_INFORMATION`
struct whose `nFileIndexHigh` and `nFileIndexLow` are concatenated
into a 64-bit integer — the NTFS File ID, equivalent to a POSIX
inode.

### Will it touch WindowsApps or Recycle Bin?

No, those are in the default skip-list. Pass `-IncludeSystemPaths`
to override.

### Is the script safe to kill mid-run?

Yes. The C# scan loop catches all per-file exceptions, drops the
record silently, and continues. Cancel via `Ctrl+C` and partial
JSON/CSV may remain on disk from the previous complete run; they are
not overwritten unless a fresh run finishes.

### The repo is at `mgreenspan17/...` but I want it under `manniegreenspan/...`

That reflects the GitHub account the agent had access to. `manniegreenspan`
is an Organization and the available token lacked admin on it. See
[`TRANSFER.md`](TRANSFER.md) for the one-time UI transfer steps or the
re-create-from-org-admin fallback.
