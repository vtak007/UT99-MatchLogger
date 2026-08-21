# MatchLogger for UT99

Server-side mutator that automatically logs match results at the end of each game — both
natural end-of-game and matches ended early by a MapVote or admin map switch. It captures
the full scoreboard including per-weapon frag statistics.

Compatible with UT99 469e (OldUnreal), ACE, and InstaGib Plus (IG+).

**Output formats**

- **HTML** — styled scoreboard viewable in any web browser
- **CSV** — spreadsheet-compatible data for analysis

## Features

- Captures complete scoreboard data (player names, scores, deaths, K/D, ping)
- Tracks per-weapon kill statistics via damage type detection
- Generates timestamped files: `MapName_YYYY-MM-DD_HH-MM-SS.html` / `.csv`
- Logs matches ended mid-game by MapVote or admin switch, not just natural end-of-game
- Configurable via INI file
- Minimal server performance impact

## Building

From the repo root:

```powershell
pwsh ./build.ps1              # normal: requires clean Source/, builds, verifies
pwsh ./build.ps1 -AllowDirty  # build with uncommitted Source/ (local iteration only)
pwsh ./build.ps1 -DryRun      # run the guards + print the plan, no changes/build
```

The script mirrors `Source/` to `C:\UnrealTournament\MatchLogger\Classes`, runs `ucc make`
in `C:\UnrealTournament\System`, and copies the built package back to the repo as
`MatchLogger_built.u`.

**Commit before deploy.** Normal mode refuses to build if `Source/` has uncommitted changes,
so anything you upload to the VPS comes from a committed state. `-AllowDirty` is for
throwaway local test builds only.

Requires `EditPackages=MatchLogger` under `[Editor.EditorEngine]` in
`C:\UnrealTournament\System\UnrealTournament.ini` — the script checks this and aborts if
it's missing.

> [!WARNING]
> The script runs plain `ucc make`, **not** `ucc make -All`. `-All` forces a rebuild of every
> package listed in `EditPackages`, which on this box would also recompile and overwrite
> `SmartSB124.u` and `PersistentMute.u`. Because the script deletes `MatchLogger.u` first and
> plain `make` only builds packages whose `.u` is missing, exactly one package gets built.
> Don't add `-All`.

## Installation

**1. Install files** — copy to the server's `System\` folder:

- `MatchLogger.u` (compiled package)
- `MatchLogger.int` (localization file)
- `MatchLogger.ini` (or let it auto-generate on first run)

**2. Create the log directory**

The output directory must **already exist** and be writable by the game-server process — it
is **not** auto-created. On a managed host, a folder created over FTP may be owned by the
FTP login rather than the game process; duplicate an existing server-created `Logs`
subfolder (e.g. `Logs/NSC`) and rename it, so it inherits the correct ownership.

**3. Configure the server**

Add to your server launch parameters:

```
?mutator=MatchLogger.MatchLogger
```

Full example:

```
ucc server DM-Deck16][?game=Botpack.DeathMatchPlus?mutator=MatchLogger.MatchLogger,InstaGibPlus.InstaGibPlus
```

Add `MatchLogger` to `ServerPackages` under `[Engine.GameEngine]`.

> [!IMPORTANT]
> If you run Nexgen, MatchLogger must also be listed in Nexgen's **Mutators Used** box.
> Nexgen re-applies its own mutator list on map switches and will otherwise drop the
> mutator after a Nexgen-controlled switch.

## Configuration

Edit `MatchLogger.ini` in the server's `System\` folder:

```ini
[MatchLogger.MatchLogger]
bEnabled=True                   ; Master enable/disable switch
bLogHTML=True                   ; Generate HTML scoreboard files
bLogCSV=True                    ; Generate CSV data files
LogPath=../Logs/MatchResults/   ; Output directory (relative to System)
bIncludeSpectators=False        ; Include spectators in logs
bIncludeBots=False              ; Include bots in logs
LogMode=2                       ; 0 = HumansAndBots, 1 = BotsOnly, 2 = HumansOnly
```

## Output files

Files are named `MapName_YYYY-MM-DD_HH-MM-SS.html` / `.csv`.

**HTML contents** — server name, map, game type, match duration, date/time, full scoreboard
(rank, player, score, deaths, K/D ratio, ping), and a per-player weapon kill breakdown.

**CSV contents** — match metadata header, scoreboard rows in standard CSV format, and weapon
statistics in a parseable form (`WeaponName:Kills;WeaponName:Kills`).

## Weapon tracking

Kills are attributed by damage type, which allows accurate weapon identification.

| Category | Weapons |
|---|---|
| Standard UT99 | Sniper Rifle (incl. headshots), Rocket Launcher (incl. grenades), Shock Rifle (incl. combos), Pulse Gun, Minigun, Flak Cannon, Ripper, Bio Rifle, Impact Hammer, Enforcer, Redeemer |
| InstaGib | InstaGib Rifle, Super Shock Rifle |
| Miscellaneous | Telefrag, environmental deaths (drowning, falling) |

## Troubleshooting

**Files aren't being created**

- The `LogPath` directory must already exist and be writable by the server process — see
  installation step 2.
- Check `server.log` for `MatchLogger: ERROR` or `write INCOMPLETE` messages.
- If `server.log` shows `Warning: Error moving file 'X' to 'X'`, the working and final
  filenames were identical. `StatLogFile`'s finalize deletes the destination before moving,
  so identical names delete the source and the move fails. The writer must use a distinct
  `<name>.tmp` working file. (Fixed in the current build and guarded against recurring —
  see `MEMORY.md`.)
- Ensure `bEnabled=True`.

**Weapon stats show "Unknown"** — some custom weapons have unmapped damage types; the raw
damage type name is shown instead.

**Mutator doesn't appear in the mutator list** — verify `MatchLogger.int` is in `System\`,
that `MatchLogger.u` compiled without errors, and restart the server.

**Logs are created but empty** — the match may have ended before any players joined, or all
players were filtered out by `bIncludeSpectators` / `bIncludeBots` / `LogMode`.

## Compatibility

Tested with UT99 469e (OldUnreal), ACE (Anti-Cheat Engine), InstaGib Plus (IG+), MapVote,
Nexgen, and most standard game types (DM, TDM, CTF, DOM, AS, LMS).

## Changelog

**v1.1** — 2026-08-15 — Reliability + map-change capture

- Fixed: no output files, caused by `StatLogFile` finalize "move-to-self" when the working
  file and final file shared the same name. The writer now writes to `<name>.tmp` and
  finalizes to `<name>` (the two MUST differ).
- Added: capture matches ended mid-game by MapVote or admin map switch, via a
  `Level.NextURL` watchdog plus a `Destroyed()` fallback (previously only a natural
  end-of-game was logged).
- Changed: reports an explicit `write INCOMPLETE` ERROR instead of always logging success;
  `OpenFile` guards against the same-name regression and empty filenames; flushes before
  close.

**v1.0** — Initial release: HTML and CSV export, per-weapon kill tracking, INI configuration.

## Credits

Created for the UT99 community. Compatible with Unreal Tournament 469e by OldUnreal.
