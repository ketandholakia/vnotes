# Security Policy

## Reporting a vulnerability

This is a small desktop application with no server component. If you find a
security issue, please open a private report via GitHub's **Security → Report a
vulnerability** tab rather than a public issue, or contact the maintainer
directly. Please include steps to reproduce and the affected version.

## Scope

V-Notes stores notes locally under `%APPDATA%\StickyNotes` (JSON files by
default, or a single `vnotes.db` when the SQLite backend is selected). It has no
network access and does not transmit note content anywhere.

## Repository hygiene — please read before committing

The following must **never** be committed:

- **AI assistant session exports / transcripts.** These routinely contain the
  local filesystem path, full prompt history, and tool-call logs. They leak far
  more than they look like they do. The root `.gitignore` already blocks the
  `*_4neem*` pattern that a previous leak used — keep that rule in place and do
  not force-add ignored files.
- **Secrets of any kind** — API keys, tokens, passwords, private keys, or
  connection strings. This project needs none of them.
- **Personal or machine-specific paths** that identify the author's environment.

Before pushing, a quick sanity check:

```bash
git status                      # review what is staged/untracked
git diff --cached --stat        # confirm only intended files
git grep -I -n "api[_-]key\|password\|secret\|token" --cached
```

If a secret or transcript is ever committed, deleting the file in a new commit
is **not enough** — it remains in history and recoverable by SHA. The file must
be purged from history (e.g. `git filter-repo`) and, if the repository is
public, the host may also need to garbage-collect unreferenced objects.
