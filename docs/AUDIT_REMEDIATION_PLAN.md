# Audit Remediation Plan

**Source audit:** "VNotes — Detailed Code Analysis & Development Roadmap" (9 findings, §6 priority list)
**Repo state at planning time:** `main` @ `57898b3` (17+ commits, Phase 6M "activate SQLite as production storage" landed, Phase 6N componentisation in progress)
**Planned:** 2026-09-25

---

## 0. Reconciliation summary — the audit is a stale snapshot

The audit describes the repo as "Phase 3C complete / 3D not started". The live tree has since advanced
well past that. Before writing new code, the findings must be re-checked against reality — otherwise we
"fix" things that are already correct and miss what actually matters.

| # | Audit finding | Severity in audit | Verified state today | Action |
| --- | --- | --- | --- | --- |
| 1 | Leaked `4neem` session transcripts in repo root | 🔴 High | **STILL PRESENT** — tracked, no `.gitignore` rule | **Fix (P0)** |
| 2 | `TTrayController` dead code | 🟡 Medium | **Already removed** — 0 references in `src/` | Close (no-op) |
| 3 | `Ctrl+Alt+F` search has no backend | 🟡 Medium | **Already implemented** — `uNoteQuery.pas` + `uNotesListForm.pas` do in-memory search | Close (no-op) |
| 4 | `TSQLiteStorage` is an unguarded stub | 🟡 Medium | **Superseded** — now a full FireDAC implementation (tags + checklist) | Close + small hardening |
| 5 | Fragile enum-arithmetic in pin toggle | 🟢 Low | **Already fixed** — `uNoteForm.pas:423-425` uses explicit `if/else` | Close (no-op) |
| 6 | About dialog links to wrong repo | 🟢 Low | **Already fixed** — `ketandholakia/vnotes` in `uAboutForm.pas:67,81` | Close (no-op) |
| 7 | No measured performance baseline | 🟢 Low | **Still absent** — no `TStopwatch`/load-time instrumentation | Fix (P2) |
| — | README architecture drift (audit-adjacent) | 🟢 Low | **Present** — README still lists `TrayController` and "SQLite stub" | Fix (P1) |
| — | No `SECURITY.md` | 🟢 Low | **Absent** | Fix (P2) |

**Net:** 1 critical + ~4 small items remain. Five of the seven numbered audit findings are already resolved
in the current code. This document is therefore a **verification-and-closeout plan**, not a greenfield fix list.

---

## P0 — Critical: purge the leaked AI session transcripts

### Problem
`1788159680651_4neem.html` (147 KB) and `1788159680651_4neem.json` (295 KB) are committed to the **public**
repo `github.com/ketandholakia/vnotes`. They contain the local path `D:\ketan\github\vnotes`, verbatim
prompts, and tool-call logs. Verified:
- Both files are **git-tracked** in the repo root.
- `.gitignore` has **no** `4neem` rule.
- `git log --diff-filter=A` shows both were added in **`1e656ee` "Initial commit"** — i.e. they exist in
  history from commit #1, so a plain delete does not remove them from the public history.
- `.kilo/`, `.opencode/`, and `node_modules` are **not** tracked (83 tracked files total) — good.

### Step 1 — stop re-committing (local, safe)
```powershell
cd D:\ketan\github\vnotes
git rm 1788159680651_4neem.html 1788159680651_4neem.json
Add-Content .gitignore "`n# Leaked AI session exports — never commit`n*_4neem.*`n*_4neem*"
git add .gitignore
git commit -m "chore: remove leaked session transcript artefacts; ignore *_4neem.*"
```

### Step 2 — purge blobs from all history (rewrites history)
Because the files date to the initial commit, this rewrites **every commit hash**. Use `git filter-repo`
(preferred) or BFG:
```powershell
pip install git-filter-repo
git filter-repo --invert-paths --path 1788159680651_4neem.html --path 1788159680651_4neem.json
# then re-add the remote (filter-repo strips it) and force-push
git remote add origin https://github.com/ketandholakia/vnotes.git
git push origin --force --all
git push origin --force --tags
```

### Step 3 — post-rewrite hygiene
- Anyone with an existing clone must **re-clone** (do not pull) — old objects are invalid after rewrite.
- GitHub keeps unreferenced objects reachable by SHA for a while; to be certain the blobs are unreachable,
  open a **GitHub Support request** to garbage-collect, or (if the repo has no external collaborators/forks)
  consider deleting and recreating the repo. Confirm no forks exist first.
- Rotate nothing — the audit confirmed **no credentials** were in the transcripts — but treat the exposed
  local path as a public fact going forward.

### Acceptance
- `git log --all --oneline -- 1788159680651_4neem.json` returns empty.
- Files absent from a fresh clone of the remote.
- `.gitignore` blocks any `*_4neem*`.

---

## P1 — Small accuracy + robustness fixes

### P1.1 README architecture drift
`README.md` still describes removed/outdated state:
- Line 27: `Controllers/ # ... (NoteManager, TrayController, SettingsController)` → drop `TrayController`.
- Line 29: `Storage/ # Abstract persistence (JSON, SQLite stub)` → SQLite is now production-capable.
- Consider adding `Components/` (note UI widgets) to the tree, which the README currently omits.
- Hotkeys table already says "opens the Notes List with in-memory search" — correct, leave as-is.

### P1.2 Harden storage-backend resolution (residual of audit #4)
`TStorageResolver.ResolveStorage` (`src/Storage/uStorageResolver.pas`) silently falls back to JSON for any
backend string that isn't `SQLite` (case-insensitive). A typo such as `sqlite3` would silently keep using JSON.
- Option A (recommended, minimal): if `StorageBackend` is non-empty and not a recognised value, **raise**
  `EArgumentException` (or log an error + raise) instead of silently choosing JSON.
- Option B: keep the fallback but **log a warning** naming the unrecognised value.
- Either way, add a unit test in `tests/Models/` covering `''`, `'JSON'`, `'SQLite'`, `'SQLITE'`, `'sqlite3'`.

---

## P2 — Low-priority / cross-cutting

### P2.1 Lightweight instrumentation (audit #7)
The SQLite decision gate is only as good as its triggers; today note-count and load-time are unmeasured.
- Log, once per `Initialize`/`LoadAllNotes`: note count and elapsed load time (use `System.Diagnostics.TStopwatch`).
- Reuse the existing `ILogger` (`uILogger.pas`) — no new subsystem.
- This makes the "500+ notes / slow load" trigger detectable in the field.

### P2.2 Add `SECURITY.md`
Short contributor note: never commit AI session exports / transcripts; keep secrets out of the repo;
how to report a leak. Prevents recurrence with a different filename.

### P2.3 Repo-root hygiene (opportunistic)
Root currently holds untracked agent/workspace files (`AGENTS.md`, `SOUL.md`, `USER.md`, `.openclaw*`, etc.).
Confirm none are ever staged alongside product code; extend `.gitignore` if the intent is product-only root.

---

## Suggested commit sequence

| Order | Commit | Risk | Notes |
| --- | --- | --- | --- |
| 1 | `chore: remove leaked transcripts + gitignore` | Low | Reversible locally |
| 2 | `chore(security): purge 4neem blobs from history` | **High** | Force-push; rewrites all hashes; coordinate clones |
| 3 | `fix(storage): fail loudly on unrecognised backend` + test | Low | Independent of 1–2 |
| 4 | `docs: correct README architecture tree` | None | — |
| 5 | `feat(perf): log note count + load time` | Low | Feeds SQLite gate |
| 6 | `docs: add SECURITY.md` | None | — |

Do 3–6 on a normal branch; do 1–2 as a dedicated, announced operation (history rewrite affects everyone).

---

## Regression check after all fixes
```powershell
build.bat          # Win32 Debug build must succeed
build_tests.bat    # DUnitX suite must pass
```
Confirm the suite still covers storage resolution + search after the resolver change.
