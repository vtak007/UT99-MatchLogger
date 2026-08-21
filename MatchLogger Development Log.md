================================================================================
                    UT99 MATCHLOGGER MUTATOR - DEVELOPMENT LOG
                              2026-01-25
================================================================================

This document captures the full conversation for creating a MatchLogger mutator
for Unreal Tournament 99 (469e) that logs match results to HTML and CSV files.

================================================================================
                              REQUIREMENTS
================================================================================

USER REQUEST:
I need a mod or mutator that will snap a screenshot after each map/game is
completed on my online server.

CLARIFICATION QUESTIONS & ANSWERS:

1. Screenshot timing:
   A: Need to capture the scoreboard before the MapVote screen appears.

2. Screenshot subject:
   A: The scoreboard screen.

3. File naming:
   A: Map name + timestamp.

4. Server-side only:
   A: Yes, server-side only for server administration/logging purposes.

5. Additional data:
   A: Yes, include a log file with match results (scores, player names, etc.)

6. UT99 version:
   A: Running UT 469e with ACE and IG+ on the server.

ADDITIONAL TECHNICAL CLARIFICATION:

Since UT99 servers have limited screenshot capabilities server-side, the
solution uses detailed log files (HTML and CSV) that reconstruct the scoreboard
data rather than actual image files.

Requested features:
- HTML and CSV output formats
- Track frags per weapon for each player
- Save to ../Logs/MatchResults/ directory

================================================================================
                           TECHNICAL RESEARCH
================================================================================

Key UnrealScript hooks identified:

1. HandleEndGame() - Mutator hook that fires when game ends, before map vote
2. ScoreKill(Pawn Killer, Pawn Other) - Hook to track kills
3. PreventDeath() - Access to damage type for weapon identification
4. PlayerReplicationInfo - Contains Score, Deaths, Ping, PlayerName, Team, etc.

Weapon tracking approach:
- Use damage type names to identify weapons (more reliable than weapon class)
- Map damage types to human-readable weapon names

================================================================================
                           FILES CREATED
================================================================================

Location: C:\UnrealTournament\MatchLogger\

1. Classes/MatchLogger.uc
   - Main mutator class
   - Hooks into HandleEndGame() to trigger logging
   - Hooks into ScoreKill() and PreventDeath() for weapon tracking
   - Exports HTML and CSV files
   - Configurable via INI file

2. Classes/MLPlayerStats.uc
   - Per-player statistics tracking
   - Stores weapon kill data by damage type
   - Supports up to 24 different weapon types per player

3. Classes/MLFileWriter.uc
   - File I/O utility extending StatLogFile
   - Handles writing to HTML and CSV files

4. Classes/MatchLogger.int
   - Localization file
   - Makes mutator visible in server mutator list

5. Classes/MatchLogger.ini
   - Default configuration file
   - Settings for enable/disable, output formats, paths, filters

6. README.txt
   - Full documentation
   - Installation instructions
   - Configuration guide
   - Troubleshooting tips

================================================================================
                        INSTALLATION INSTRUCTIONS
================================================================================

1. COMPILE THE MUTATOR

   a) The MatchLogger folder should be in your UT root directory:
      C:\UnrealTournament\MatchLogger\

   b) Edit UnrealTournament.ini and add to [Editor.EditorEngine] section:
      EditPackages=MatchLogger

   c) Open command prompt in System folder and run:
      ucc make

   d) This creates MatchLogger.u in the System folder.

2. INSTALL FILES

   Copy to your UT System folder:
   - MatchLogger.u   (compiled package)
   - MatchLogger.int (localization file)
   - MatchLogger.ini (configuration - or let it auto-generate)

3. CREATE LOG DIRECTORY

   Create: C:\UnrealTournament\Logs\MatchResults\

4. CONFIGURE SERVER

   Add to server startup parameters:
   ?mutator=MatchLogger.MatchLogger

   Or with other mutators:
   ?mutator=MatchLogger.MatchLogger,InstaGibPlus.InstaGibPlus

================================================================================
                           CONFIGURATION
================================================================================

Edit MatchLogger.ini:

[MatchLogger.MatchLogger]
bEnabled=True              ; Master enable/disable switch
bLogHTML=True              ; Generate HTML scoreboard files
bLogCSV=True               ; Generate CSV data files
LogPath=../Logs/MatchResults   ; Output directory (relative to System)
bIncludeSpectators=False   ; Include spectators in logs
bIncludeBots=True          ; Include bots in logs

================================================================================
                           OUTPUT FORMAT
================================================================================

Files are named: MapName_YYYY-MM-DD_HH-MM-SS.html and .csv

HTML includes:
- Server name, map, game type
- Match duration
- Date and time
- Styled scoreboard with rank colors (gold/silver/bronze for top 3)
- Per-player weapon kill breakdown

CSV includes:
- Match metadata header section
- Scoreboard data columns: Rank, PlayerName, Score, Deaths, KDRatio, Ping, IsBot
- Weapon statistics in parseable format: WeaponName:Kills;WeaponName:Kills

================================================================================
                        SUPPORTED WEAPONS
================================================================================

Standard UT99:
- Sniper Rifle (Decapitated = headshot, shot = body shot)
- Rocket Launcher (RocketDeath, GrenadeDeath)
- Shock Rifle (Eradicated, ShockCombo)
- Pulse Gun (Burned, Jolted)
- Minigun (shredded)
- Flak Cannon (FlakDeath, Gibbed)
- Ripper (RipperDeath)
- Bio Rifle (Corroded)
- Impact Hammer (impact, Pummelled)
- Enforcer (EnforcerDeath)
- Redeemer (Exploded)

InstaGib:
- InstaGib Rifle (intaGib, jolted)
- Super Shock Rifle (SuperShockBeam)

Other:
- Telefrag (Gibbed from translocator)
- Drowned, Fell, Suicided

================================================================================
                         SOURCE CODE
================================================================================

[Full source code for all .uc files was provided in the conversation above]

================================================================================
                           END OF LOG
================================================================================
