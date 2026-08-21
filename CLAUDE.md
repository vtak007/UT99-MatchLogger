# UT99 MatchLogger — Project Instructions

Server-side mutator that logs end-of-match scoreboards (with per-weapon frag stats) to HTML
and CSV. See `README.md` for full details. Follow the shared rules in `../CLAUDE.md` and the
global `~/.claude/CLAUDE.md`; do not duplicate them here.

## Key Files

| File | Purpose |
|---|---|
| `Source/MatchLogger.uc` | The mutator — tracks players/damage types during the match, detects end-of-game (natural, mapvote, or admin switch), and drives the HTML/CSV export. |
| `Source/MLFileWriter.uc` | `StatLogFile` subclass that does the actual file writing. Writes to `<name>.tmp` and finalizes to `<name>` — the two names MUST differ (see `MEMORY.md`). |
| `Source/MLPlayerStats.uc` | Per-player stat record: score, deaths, ping, and the per-damage-type kill tally. |
| `build.ps1` | Guarded build: mirrors `Source/` to `C:\UnrealTournament\MatchLogger\Classes`, runs `ucc make`, verifies output. Refuses to build uncommitted source. |
| `MatchLogger.int` | Localization/package descriptor — must be deployed to the server's `System\` alongside the `.u`. |
| `MEMORY.md` | Persistent project memory (root causes, ruled-out theories, conventions, change log). |
| `MatchLogger Development Log.md` | Original 2026-01-25 requirements conversation and design rationale. |

## Project Notes

- This is a **Mutator** (`extends Mutator config(MatchLogger)`), loaded via
  `?mutator=MatchLogger.MatchLogger` and listed in `ServerPackages`. It must also stay in
  Nexgen's "Mutators Used" list — Nexgen re-applies its mutator list on map switches and
  will otherwise drop it after a Nexgen-controlled switch.
- **Build with `build.ps1`, not by hand.** `ucc make` compiles from the mirror at
  `C:\UnrealTournament\MatchLogger\Classes`, which the script wipes and re-copies from
  `Source/` on every run so the deployed binary cannot drift from tracked source.
- Deploy the freshly built `C:\UnrealTournament\System\MatchLogger.u` to the VPS — never a
  stale copy from this folder.
- `MatchLogger.ini` is untracked (global `*.ini` rule). The local copy mirrors the live VPS
  config; re-download from the server rather than assuming this folder is current.
