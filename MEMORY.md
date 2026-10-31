# MatchLogger — MEMORY

Project-specific findings for the UT99 MatchLogger mutator (all-weapons DM server:
UT469e, IG+, ACE v14e, Nexgen 112N, NFO managed host, FTP/WinSCP only — no SSH).

## CONFIRMED ROOT CAUSES

- **StatLogFile finalize is a move-to-self when temp == final.** `MLFileWriter extends
  StatLogFile`. On `CloseLog()` the engine finalizes by moving `StatLogFile` (working
  file) → `StatLogFinal` (destination), and that move **deletes the destination first**.
  If `StatLogFile == StatLogFinal`, it deletes its own source and the move fails with:
  `Warning: Error moving file 'X' to 'X' (The system cannot find the file specified.)`
  and no output file is produced. **Fix: the two names MUST differ** — write to
  `<name>.tmp`, finalize to `<name>`. This is the Rev 4 / Rev 6 design in
  `MLFileWriter.OpenFile()`. Evidence: server.20260815_0240.log lines 635–637 (Rev 5,
  same-name) vs. the older working `.html`/`.csv` files produced by Rev 4.

- **Target directory must already exist and be writable by the game-server process.**
  StatLogFile does NOT create directories. A folder created over FTP can be owned by the
  FTP login rather than the game process. Fix: duplicate an existing server-created Logs
  subfolder (e.g. `Logs/NSC`) and rename it, so it inherits the correct owner/permissions.

## RULED-OUT THEORIES (do not re-try)

- **`ucc make -All` in the build script** — WRONG. `-All` forces a rebuild of every
  `EditPackages` entry, which on this box also recompiles and overwrites `SmartSB124.u`
  and `PersistentMute.u` (the only other entries with sources present; the stock packages
  have no `.uc` and would just churn). `build.ps1` deletes `MatchLogger.u` at step 2 and
  plain `ucc make` only builds packages whose `.u` is missing — so plain `make` already
  builds exactly this one package. Verified 2026-08-21: after a real run, `SmartSB124.u`,
  `PersistentMute.u` and `Botpack.u` md5s were byte-identical before and after.
  NOTE: `UT99 SmartSB`'s own `build.ps1` also runs plain `ucc make`, with the same NOTE in
  its step 3 — there is no latent `-All` trap there. Verified 2026-10-31; an earlier
  version of this line claimed SmartSB still carried `-All`, which was wrong.
- **Mutator name wrong / not loading** — No. `MatchLogger.MatchLogger` is correct in the
  `.int`, ServerPackages, and the `?mutator=` line; log shows one `Add mutator` per map.
- **Nexgen "Mutators Used" double-loading it** — No. Single load per map confirmed in logs.
  NOTE: that box IS functional (Nexgen re-applies its mutator list on map switches), so
  MatchLogger must stay listed there or it gets dropped after a Nexgen-controlled switch.
- **469 file-write sandbox blocking `.html`/`.csv`** — No. Other loggers write to `../Logs`
  fine, and Rev 4 wrote `.html`/`.csv` successfully.
- **Subdirectory path handling in StatLogFile** — No. Writing to `../Logs` (no subdir)
  also failed under the broken same-name scheme.
- **"Write directly to the final file" (StatLogFile == StatLogFinal)** — WRONG FIX. This
  is what *causes* the move-to-self failure (was Rev 5). Never reintroduce it.

## PROJECT CONVENTIONS

- Source of truth is the repo: `Source/*.uc` in the Dropbox project folder (git,
  `vtak007/UT99-MatchLogger`). Build with `pwsh ./build.ps1`, which wipes and re-copies the
  mirror at `C:\UnrealTournament\MatchLogger\Classes` from `Source/` and runs `ucc make`.
  Never edit the mirror directly — the next build overwrites it.
- Deploy the freshly built `C:\UnrealTournament\System\MatchLogger.u` to the server —
  NOT the stale copy in the Dropbox project folder.
- `MatchLogger.ini` is untracked (global `*.ini` rule). The live VPS config uses
  `LogPath=../Logs/MatchResults/` (**with** trailing slash, relative to `System`) and
  `LogMode=2` (HumansOnly).
- As of Rev 13, output is written at a natural end-of-game (`HandleEndGame`) **and** on
  mapvote/admin map changes (`Level.NextURL` watchdog + `Destroyed()` fallback). The older
  note that mapvote-ended maps do not log is obsolete.
- Write validation (as of Rev 13): `OpenFile()` now rejects empty names and the temp==final
  case with a logged error; `ExportHTML`/`ExportCSV` return real success and
  `LogMatchResults` logs `write INCOMPLETE` on failure. Remaining limitation: UnrealScript
  cannot detect a native `OpenLog()` failure directly — a finalize failure only shows as an
  engine `Warning: Error moving file` line, so watch for that in server.log.

## CHANGE LOG

- 2026-10-31 — `MEMORY.md`: corrected the RULED-OUT THEORIES note that claimed `UT99
  SmartSB`'s `build.ps1` still carried `-All` — it runs plain `ucc make` too, with the same
  NOTE in its step 3. No build-script change was needed anywhere. Also cleared the stray
  untracked `MatchLogger.u` / `MatchLogger_built.u` copies from the project root (the live
  VPS copy and the build output remain in their own locations).
- 2026-08-21 — `build.ps1`: dropped the `-All` flag from `ucc make` (branch
  `fix/build-drop-all-flag`). First real run of the script verified: `Success - 0 error(s),
  0 warnings`, mirror repopulated from `Source/`, `MatchLogger.u` rebuilt, and no other
  package touched. Note: a rebuilt `.u` will not md5-match the previous one even from
  identical source — `ucc` output is not byte-reproducible.
- 2026-08-21 — Set up as a git repo (`vtak007/UT99-MatchLogger`, public). Source moved from
  `C:\UnrealTournament\MatchLogger\Classes` to `Source/`; `Build_MatchLogger.bat` replaced by
  the guarded `build.ps1` (mirror re-sync + commit-before-deploy check, SmartSB pattern);
  added `README.md`, `CLAUDE.md`, `.gitignore`; superseded rev11/rev12/rev13 snapshots, zips
  and summary .txt files dropped from tracking (git is the history now).
- 2026-08-15 — Hardening (MatchLogger Rev 13 / MLFileWriter Rev 6+): (a) capture mid-game
  map changes that bypass HandleEndGame (mapvote / admin switch) via a `Level.NextURL`
  watchdog on the repeating timer + a `Destroyed()` fallback; (b) `ExportHTML`/`ExportCSV`
  now return real success, `LogMatchResults` logs an ERROR line instead of always claiming
  success; (c) `OpenFile` hard-guards against temp==final and empty names; (d) `FileFlush()`
  before `CloseLog()`. NOTE: script still cannot directly detect a native `OpenLog()`
  failure — the engine surfaces a finalize failure as a `Warning: Error moving file` line.
  Rebuilt and deployed 2026-08-15.
- 2026-08-15 — VERIFIED FIXED. Rev 6 deployed; a bot test match at natural end-of-game
  produced both `.html` and `.csv` in `Logs/MatchResults/` with no `Error moving file`
  warning. Restored temp-file design (MLFileWriter **Rev 6** = Rev 4 logic:
  `StatLogFile = <name>.tmp`, `StatLogFinal = <name>`). Root cause was the move-to-self
  from the same-name scheme (`Error moving file 'X' to 'X'` in server.20260815_0240.log).
- 2026-08-14 — Mistakenly reverted MLFileWriter to same-name scheme (Rev 5); broke logging
  (move-to-self). Root-caused and reverted the revert.
- 2026-08-14 — Folder/permissions troubleshooting: duplicated `Logs/NSC` to give
  `Logs/MatchResults` the correct ownership; ruled out permissions as the active cause.
