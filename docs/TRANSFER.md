# Transferring to the `manniegreenspan` organization

The repo is currently published at
[`mgreenspan17/ntfs-dedupe-scanner`](https://github.com/mgreenspan17/ntfs-dedupe-scanner).
The intent envelope specified the `manniegreenspan` GitHub **Organization**.
This document lists exactly how to move the repo to that path.

## Prerequisites

You need at least one of:

1. **Org admin** on `manniegreenspan` (Settings → Members, your role is Owner),
2. or a repo-transfer invitation issued by an org admin,
3. or "Members can create repositories" enabled in the org's General settings.

The token used by the agent that scaffolded this project (`mgreenspan17`)
cannot create repos in `manniegreenspan` today. A one-time manual step is
required.

## Method A — Transfer via the GitHub UI (recommended)

1. Open <https://github.com/mgreenspan17/ntfs-dedupe-scanner>.
2. **Settings → Danger Zone → Transfer ownership**.
3. Type `manniegreenspan/ntfs-dedupe-scanner` and confirm.
4. Optionally rename the default branch from `main` if the org's
   default branch policy disagrees (it doesn't here).
5. Done. The commit history, tags, releases, issue/links come with it.
   The repo stays public, just under the new namespace.

A redirect URL (`/mgreenspan17/ntfs-dedupe-scanner → /manniegreenspan/...`)
remains for 90 days.

## Method B — Re-create under the org

If a transfer is blocked (insufficient org role):

1. Have an org admin either create the empty repo
   `manniegreenspan/ntfs-dedupe-scanner` or grant you admin on it
   (Settings → Members → Invite member).
2. Locally:

   ```powershell
   git -C C:\Users\manni\projects\ntfs-dedupe-scanner `
       remote set-url origin `
       https://github.com/manniegreenspan/ntfs-dedupe-scanner.git
   git -C C:\Users\manni\projects\ntfs-dedupe-scanner push -u origin main
   ```

3. When satisfied, archive or delete the old `mgreenspan17/ntfs-dedupe-scanner`.

## Local URL update afterwards

Whichever method you used, align the local checkout:

```powershell
git -C C:\Users\manni\projects\ntfs-dedupe-scanner remote -v
# Confirm 'origin' points at https://github.com/manniegreenspan/ntfs-dedupe-scanner.git
gh repo view manniegreenspan/ntfs-dedupe-scanner --json url,visibility,defaultBranchRef
```

What transfers with the repo:

| Asset                            | Transferred? |
|----------------------------------|--------------|
| Commit graph + Co-authored-by    | yes          |
| Tags / releases                  | yes          |
| Issues, PRs, labels, milestones  | yes          |
| Branch protection rules          | no — review  |
| Secrets, deploy keys, Pages      | no — recreate|
| GitHub Actions secrets/variables | no — recreate|
| Topics, description              | yes          |

## Verifying the move

```powershell
gh repo view manniegreenspan/ntfs-dedupe-scanner --json url,visibility,pushedAt
git -C C:\Users\manni\projects\ntfs-dedupe-scanner log --oneline -1
git -C C:\Users\manni\projects\ntfs-dedupe-scanner ls-remote origin
```

Expected:

- `visibility: "public"`
- `pushedAt` is the latest push timestamp
- `ls-remote` returns commit `baddb33...` on `refs/heads/main`

## If the transfer requests an admin

GitHub emits a one-time transfer token and the new owner has 7 days to
accept. The accepting account must have org ownership. Coordinate with
an existing `manniegreenspan` owner before starting the transfer.
