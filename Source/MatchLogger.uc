//=============================================================================
// MatchLogger.uc
// Server-side mutator that logs match results to HTML and CSV files
// Compatible with UT99 469e, ACE, and IG+
// Creates detailed scoreboard logs with per-weapon frag statistics
// Rev 13
// Rev 13: also capture mid-game map changes that bypass HandleEndGame (mapvote /
//         admin switch) via a NextURL watchdog + Destroyed() fallback, and report
//         real write success/failure instead of always logging success.
//=============================================================================
class MatchLogger extends Mutator config(MatchLogger);

// Configuration variables
var() config bool bEnabled;
var() config bool bLogHTML;
var() config bool bLogCSV;
var() config string LogPath;
var() config bool bIncludeSpectators;
var() config bool bIncludeBots;
var() config int LogMode;

// Internal tracking
var MLPlayerStats PlayerStats[64];
var int NumTrackedPlayers;
var bool bMatchLogged;
var bool bInitialized;
var string MapName;
var string GameType;
var string ServerName;
var float MatchStartTime;

// Weapon name mappings for clean output
struct WeaponNameMap
{
    var string DamageType;
    var string DisplayName;
};
var WeaponNameMap WeaponNames[32];
var int NumWeaponNames;

function PreBeginPlay()
{
    Super.PreBeginPlay();

    if (LogPath == "")
        LogPath = "../Logs/MatchResults";

    InitWeaponNames();

    bMatchLogged = false;
    NumTrackedPlayers = 0;
}

function PostBeginPlay()
{
    Super.PostBeginPlay();
    Log("MatchLogger: PostBeginPlay initialized");
    // Repeating: the first tick initializes, later ticks watch for a pending map change.
    SetTimer(0.25, true);
}

function Timer()
{
    if (!bInitialized)
    {
        SafeInitialize();
        bInitialized = true;
    }

    // Capture map changes that bypass HandleEndGame (e.g. a mid-game mapvote or admin
    // switch). ServerTravel sets Level.NextURL a short countdown before the actual
    // switch, while all players and their PRIs are still alive, so scores stay readable.
    if (bEnabled && !bMatchLogged && Level != None && Level.NextURL != "")
    {
        LogMatchResults();
        bMatchLogged = true;
    }
}

// Last-resort capture: if the level is torn down (server travel / shutdown) without
// HandleEndGame or the NextURL watchdog having logged, record what can still be read.
function Destroyed()
{
    if (bEnabled && !bMatchLogged && Level != None && Level.Game != None)
    {
        LogMatchResults();
        bMatchLogged = true;
    }

    Super.Destroyed();
}

function SafeInitialize()
{
    if (Level == None || Level.Game == None)
        return;

    MapName = GetURLMap();
    GameType = string(Level.Game.Class.Name);

    if (Level.Game.GameReplicationInfo != None)
        ServerName = Level.Game.GameReplicationInfo.ServerName;
    else
        ServerName = "Unknown Server";

    MatchStartTime = Level.TimeSeconds;

    Log("MatchLogger: Initialized for map " $ MapName $ " (" $ GameType $ ")");
}

function InitWeaponNames()
{
    // Standard UT99 weapons
    AddWeaponName("Decapitated", "Sniper Rifle (Headshot)");
    AddWeaponName("shot", "Sniper Rifle");
    AddWeaponName("RocketDeath", "Rocket Launcher");
    AddWeaponName("GrenadeDeath", "Rocket Launcher (Grenade)");
    AddWeaponName("Corroded", "Bio Rifle");
    AddWeaponName("Burned", "Pulse Gun");
    AddWeaponName("Jolted", "Pulse Gun (Alt)");
    AddWeaponName("Eradicated", "Shock Rifle");
    AddWeaponName("ShockCombo", "Shock Rifle (Combo)");
    AddWeaponName("zapped", "ASMD");
    AddWeaponName("shredded", "Minigun");
    AddWeaponName("FlakDeath", "Flak Cannon");
    AddWeaponName("Gibbed", "Flak Cannon (Alt)");
    AddWeaponName("RipperDeath", "Ripper");
    AddWeaponName("Exploded", "Redeemer");
    AddWeaponName("impact", "Impact Hammer");
    AddWeaponName("Pummelled", "Impact Hammer");
    AddWeaponName("EnforcerDeath", "Enforcer");
    AddWeaponName("Drowned", "Drowned");
    AddWeaponName("Fell", "Fell");
    AddWeaponName("Suicided", "Suicide");

    // InstaGib weapons
    AddWeaponName("intaGib", "InstaGib");
    AddWeaponName("jolted", "InstaGib");
    AddWeaponName("SuperShockBeam", "Super Shock Rifle");

    // Translocator
    AddWeaponName("Gibbed", "Telefrag");
}

function AddWeaponName(string DamageType, string DisplayName)
{
    if (NumWeaponNames < 32)
    {
        WeaponNames[NumWeaponNames].DamageType = DamageType;
        WeaponNames[NumWeaponNames].DisplayName = DisplayName;
        NumWeaponNames++;
    }
}

function string GetWeaponDisplayName(name DamageType)
{
    local int i;
    local string DamageStr;

    DamageStr = string(DamageType);

    for (i = 0; i < NumWeaponNames; i++)
    {
        if (WeaponNames[i].DamageType ~= DamageStr)
            return WeaponNames[i].DisplayName;
    }

    return DamageStr;
}

// LogMode values:
// 0 = Humans and Bots
// 1 = Bots only
// 2 = Humans only
function bool ShouldTrackPRI(PlayerReplicationInfo PRI)
{
    if (PRI == None)
        return False;

    if (!bIncludeBots && PRI.bIsABot)
        return False;

    if (LogMode == 1)
        return PRI.bIsABot;

    if (LogMode == 2)
        return !PRI.bIsABot;

    return True;
}

function bool ShouldIncludeStats(MLPlayerStats Stats)
{
    if (Stats == None)
        return False;

    if (!bIncludeBots && Stats.bIsBot)
        return False;

    if (LogMode == 1)
        return Stats.bIsBot;

    if (LogMode == 2)
        return !Stats.bIsBot;

    return True;
}

// Find or create stats for a player.
function MLPlayerStats GetPlayerStats(Pawn P)
{
    local int i;
    local MLPlayerStats NewStats;

    if (P == None || P.PlayerReplicationInfo == None)
        return None;

    if (!ShouldTrackPRI(P.PlayerReplicationInfo))
        return None;

    for (i = 0; i < NumTrackedPlayers; i++)
    {
        if (PlayerStats[i] != None && PlayerStats[i].TrackedPlayer == P)
            return PlayerStats[i];
    }

    if (NumTrackedPlayers < 64)
    {
        NewStats = Spawn(class'MLPlayerStats');
        if (NewStats != None)
        {
            NewStats.TrackedPlayer = P;
            NewStats.PlayerName = P.PlayerReplicationInfo.PlayerName;
            NewStats.bIsBot = P.PlayerReplicationInfo.bIsABot;
            NewStats.bIsSpectator = P.PlayerReplicationInfo.bIsSpectator;
            PlayerStats[NumTrackedPlayers] = NewStats;
            NumTrackedPlayers++;
            return NewStats;
        }
    }

    return None;
}

// Keep the hook to make sure killer/victim trackers exist, but do not count
// weapon stats here because PreventDeath below already records the authoritative
// damage type. Counting in both places created duplicate / blank weapon rows.
function ScoreKill(Pawn Killer, Pawn Other)
{
    Super.ScoreKill(Killer, Other);

    if (Killer != None)
        GetPlayerStats(Killer);

    if (Other != None)
        GetPlayerStats(Other);
}

// Override to track kills by damage type.
function bool PreventDeath(Pawn Killed, Pawn Killer, name damageType, vector HitLocation)
{
    local MLPlayerStats KillerStats;
    local MLPlayerStats VictimStats;

    if (Killer != None && Killer != Killed && Killed != None)
    {
        KillerStats = GetPlayerStats(Killer);
        if (KillerStats != None)
            KillerStats.AddDamageTypeKill(damageType);
    }

    if (Killed != None)
    {
        VictimStats = GetPlayerStats(Killed);
        if (VictimStats != None)
            VictimStats.Deaths++;
    }

    return Super.PreventDeath(Killed, Killer, damageType, HitLocation);
}

// Hook into game end - this fires before map vote.
function bool HandleEndGame()
{
    if (!bMatchLogged && bEnabled)
    {
        LogMatchResults();
        bMatchLogged = true;
    }

    return Super.HandleEndGame();
}

// Main logging function.
function LogMatchResults()
{
    local string Timestamp;
    local string BaseFileName;
    local Pawn P;
    local PlayerReplicationInfo PRI;
    local MLPlayerStats Stats;
    local bool bHtmlOK, bCsvOK;

    Timestamp = GenerateTimestamp();
    BaseFileName = LogPath $ "/" $ MapName $ "_" $ Timestamp;

    for (P = Level.PawnList; P != None; P = P.NextPawn)
    {
        if (P.bIsPlayer && P.PlayerReplicationInfo != None && ShouldTrackPRI(P.PlayerReplicationInfo))
        {
            Stats = GetPlayerStats(P);
            if (Stats != None)
            {
                PRI = P.PlayerReplicationInfo;
                Stats.FinalScore = PRI.Score;
                Stats.Deaths = PRI.Deaths;
                Stats.Ping = PRI.Ping;
                Stats.Team = PRI.Team;
                Stats.PlayerName = PRI.PlayerName;
                Stats.bIsBot = PRI.bIsABot;
                Stats.bIsSpectator = PRI.bIsSpectator;
            }
        }
    }

    SortPlayersByScore();

    // Treat a not-requested format as "ok" so it doesn't count as a failure.
    bHtmlOK = !bLogHTML;
    if (bLogHTML)
        bHtmlOK = ExportHTML(BaseFileName $ ".html");

    bCsvOK = !bLogCSV;
    if (bLogCSV)
        bCsvOK = ExportCSV(BaseFileName $ ".csv");

    if (bHtmlOK && bCsvOK)
        Log("MatchLogger: Logged match results to " $ BaseFileName);
    else
        Log("MatchLogger: ERROR - match results write INCOMPLETE for " $ BaseFileName $ " (HTML ok=" $ string(bHtmlOK) $ ", CSV ok=" $ string(bCsvOK) $ ") - check for a 'Error moving file' warning above");
}

function string GenerateTimestamp()
{
    local string Year, Month, Day, Hour, Minute, Second;

    Year = string(Level.Year);
    Month = PadNumber(Level.Month);
    Day = PadNumber(Level.Day);
    Hour = PadNumber(Level.Hour);
    Minute = PadNumber(Level.Minute);
    Second = PadNumber(Level.Second);

    return Year $ "-" $ Month $ "-" $ Day $ "_" $ Hour $ "-" $ Minute $ "-" $ Second;
}

function string PadNumber(int Num)
{
    if (Num < 10)
        return "0" $ string(Num);
    return string(Num);
}

function string PadLeftZero(int Num, int Digits)
{
    local string S;

    S = string(Num);
    while (Len(S) < Digits)
        S = "0" $ S;

    return S;
}

function SortPlayersByScore()
{
    local int i, j;
    local MLPlayerStats Temp;

    for (i = 0; i < NumTrackedPlayers - 1; i++)
    {
        for (j = 0; j < NumTrackedPlayers - i - 1; j++)
        {
            if (PlayerStats[j] != None && PlayerStats[j+1] != None)
            {
                if (PlayerStats[j].FinalScore < PlayerStats[j+1].FinalScore)
                {
                    Temp = PlayerStats[j];
                    PlayerStats[j] = PlayerStats[j+1];
                    PlayerStats[j+1] = Temp;
                }
            }
        }
    }
}

function bool ExportHTML(string FileName)
{
    local MLFileWriter F;
    local int i;
    local MLPlayerStats Stats;
    local string MatchDuration;
    local int DurationSecs;
    local string DateStr;
    local string TimeStr;
    local string DateTimeLine;

    F = Spawn(class'MLFileWriter');
    if (F == None)
    {
        Log("MatchLogger: ERROR - Could not create FileWriter for HTML export");
        return False;
    }

    if (!F.OpenFile(FileName))
    {
        Log("MatchLogger: ERROR - Could not open file " $ FileName);
        F.Destroy();
        return False;
    }

    DurationSecs = int(Level.TimeSeconds - MatchStartTime);
    MatchDuration = string(DurationSecs / 60) $ "m " $ string(DurationSecs % 60) $ "s";
    DateStr = string(Level.Year) $ "-" $ PadNumber(Level.Month) $ "-" $ PadNumber(Level.Day);
    TimeStr = PadNumber(Level.Hour) $ ":" $ PadNumber(Level.Minute) $ ":" $ PadNumber(Level.Second);
    DateTimeLine = "        <p><strong>Date:</strong> " $ DateStr $ " " $ TimeStr $ "</p>";

    F.WriteLine("<!DOCTYPE html>");
    F.WriteLine("<html lang=\"en\">");
    F.WriteLine("<head>");
    F.WriteLine("    <meta charset=\"UTF-8\">");
    F.WriteLine("    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">");
    F.WriteLine("    <title>" $ EscapeHTML(MapName) $ " - Match Results</title>");
    F.WriteLine("    <style>");
    F.WriteLine("        body { font-family: 'Courier New', monospace; background: #1a1a2e; color: #eee; padding: 20px; }");
    F.WriteLine("        .container { max-width: 1200px; margin: 0 auto; }");
    F.WriteLine("        h1 { color: #ff6b35; text-align: center; text-shadow: 2px 2px 4px #000; }");
    F.WriteLine("        .match-info { background: #16213e; padding: 15px; border-radius: 8px; margin-bottom: 20px; }");
    F.WriteLine("        .match-info p { margin: 5px 0; }");
    F.WriteLine("        table { width: 100%; border-collapse: collapse; background: #0f0f23; }");
    F.WriteLine("        th { background: #e94560; color: white; padding: 12px; text-align: left; }");
    F.WriteLine("        td { padding: 10px; border-bottom: 1px solid #333; }");
    F.WriteLine("        tr:nth-child(even) { background: #1a1a2e; }");
    F.WriteLine("        tr:hover { background: #2a2a4e; }");
    F.WriteLine("        .rank-1 { color: #ffd700; font-weight: bold; }");
    F.WriteLine("        .rank-2 { color: #c0c0c0; }");
    F.WriteLine("        .rank-3 { color: #cd7f32; }");
    F.WriteLine("        .bot { color: #888; font-style: italic; }");
    F.WriteLine("        .weapon-stats { font-size: 0.85em; color: #aaa; }");
    F.WriteLine("        .section { margin-top: 30px; }");
    F.WriteLine("        .section h2 { color: #ff6b35; border-bottom: 2px solid #e94560; padding-bottom: 10px; }");
    F.WriteLine("    </style>");
    F.WriteLine("</head>");
    F.WriteLine("<body>");
    F.WriteLine("<div class=\"container\">");

    F.WriteLine("    <h1>UNREAL TOURNAMENT - MATCH RESULTS</h1>");
    F.WriteLine("    <div class=\"match-info\">");
    F.WriteLine("        <p><strong>Server:</strong> " $ EscapeHTML(ServerName) $ "</p>");
    F.WriteLine("        <p><strong>Map:</strong> " $ EscapeHTML(MapName) $ "</p>");
    F.WriteLine("        <p><strong>Game Type:</strong> " $ EscapeHTML(GameType) $ "</p>");
    F.WriteLine("        <p><strong>Duration:</strong> " $ MatchDuration $ "</p>");
    F.WriteLine(DateTimeLine);
    F.WriteLine("    </div>");

    F.WriteLine("    <div class=\"section\">");
    F.WriteLine("        <h2>SCOREBOARD</h2>");
    F.WriteLine("        <table>");
    F.WriteLine("            <tr><th>Rank</th><th>Player</th><th>Score</th><th>Deaths</th><th>K/D</th><th>Ping</th></tr>");

    for (i = 0; i < NumTrackedPlayers; i++)
    {
        Stats = PlayerStats[i];
        if (Stats == None)
            continue;

        if (!bIncludeSpectators && Stats.bIsSpectator)
            continue;

        if (!ShouldIncludeStats(Stats))
            continue;

        WritePlayerHTMLRow(F, Stats, i + 1);
    }

    F.WriteLine("        </table>");
    F.WriteLine("    </div>");

    F.WriteLine("    <div class=\"section\">");
    F.WriteLine("        <h2>WEAPON STATISTICS</h2>");
    F.WriteLine("        <table>");
    F.WriteLine("            <tr><th>Player</th><th>Weapon Kills Breakdown</th></tr>");

    for (i = 0; i < NumTrackedPlayers; i++)
    {
        Stats = PlayerStats[i];
        if (Stats == None)
            continue;

        if (!bIncludeSpectators && Stats.bIsSpectator)
            continue;
        if (!ShouldIncludeStats(Stats))
            continue;

        WriteWeaponStatsHTMLRow(F, Stats);
    }

    F.WriteLine("        </table>");
    F.WriteLine("    </div>");

    F.WriteLine("    <p style=\"text-align: center; margin-top: 30px; color: #666;\">Generated by MatchLogger Mutator</p>");
    F.WriteLine("</div>");
    F.WriteLine("</body>");
    F.WriteLine("</html>");

    F.CloseFile();
    F.Destroy();
    return True;
}

function WritePlayerHTMLRow(MLFileWriter F, MLPlayerStats Stats, int Rank)
{
    local string RankClass;
    local string PlayerClass;
    local float KDRatio;
    local string PlayerCell;

    if (Rank == 1)
        RankClass = " class=\"rank-1\"";
    else if (Rank == 2)
        RankClass = " class=\"rank-2\"";
    else if (Rank == 3)
        RankClass = " class=\"rank-3\"";
    else
        RankClass = "";

    if (Stats.bIsBot)
        PlayerClass = " class=\"bot\"";
    else
        PlayerClass = "";

    KDRatio = GetKDRatio(Stats);
    PlayerCell = "                <td" $ PlayerClass $ ">" $ EscapeHTML(Stats.PlayerName $ GetBotTag(Stats)) $ "</td>";

    F.WriteLine("            <tr" $ RankClass $ ">");
    F.WriteLine("                <td>" $ Rank $ "</td>");
    F.WriteLine(PlayerCell);
    F.WriteLine("                <td>" $ Stats.FinalScore $ "</td>");
    F.WriteLine("                <td>" $ Stats.Deaths $ "</td>");
    F.WriteLine("                <td>" $ FormatFloat(KDRatio, 2) $ "</td>");
    F.WriteLine("                <td>" $ Stats.Ping $ "</td>");
    F.WriteLine("            </tr>");
}

function WriteWeaponStatsHTMLRow(MLFileWriter F, MLPlayerStats Stats)
{
    local string WeaponBreakdown;
    local string OutLine;
    local int i;
    local name TempDamageTypeName;
    local int TempKills;

    WeaponBreakdown = "";
    for (i = 0; i < Stats.NumWeaponTypes; i++)
    {
        TempDamageTypeName = Stats.GetDamageTypeNameAt(i);
        TempKills = Stats.GetWeaponKillsAt(i);

        if (i > 0)
            WeaponBreakdown = WeaponBreakdown $ ", ";
        WeaponBreakdown = WeaponBreakdown $ GetWeaponDisplayName(TempDamageTypeName) $ ": " $ string(TempKills);
    }

    if (WeaponBreakdown == "")
        WeaponBreakdown = "No kills recorded";

    F.WriteLine("            <tr>");
    F.WriteLine("                <td>" $ EscapeHTML(Stats.PlayerName) $ "</td>");
    OutLine = "                <td class=\"weapon-stats\">" $ EscapeHTML(WeaponBreakdown) $ "</td>";
    F.WriteLine(OutLine);
    F.WriteLine("            </tr>");
}

function string GetBotTag(MLPlayerStats Stats)
{
    if (Stats.bIsBot)
        return " [BOT]";
    return "";
}

function string FormatFloat(float Value, int Decimals)
{
    local int IntPart;
    local int DecPart;
    local float Multiplier;
    local int Digits;

    if (Decimals < 0)
        Decimals = 0;

    Digits = Decimals;
    Multiplier = 1.0;
    while (Decimals > 0)
    {
        Multiplier *= 10.0;
        Decimals--;
    }

    IntPart = int(Value);
    DecPart = int(Abs((Value - IntPart) * Multiplier) + 0.5);

    if (DecPart >= int(Multiplier))
    {
        IntPart++;
        DecPart = 0;
    }

    if (Digits == 0)
        return string(IntPart);

    return string(IntPart) $ "." $ PadLeftZero(DecPart, Digits);
}

function bool ExportCSV(string FileName)
{
    local MLFileWriter F;
    local int i, j;
    local MLPlayerStats Stats;
    local string WeaponBreakdown;
    local int DurationSecs;
    local name TempDamageTypeName;
    local int TempKills;
    local string TempWeaponName;
    local string TempWeaponEntry;
    local string DateStr;
    local string TimeStr;
    local string CSVLine;

    F = Spawn(class'MLFileWriter');
    if (F == None)
    {
        Log("MatchLogger: ERROR - Could not create FileWriter for CSV export");
        return False;
    }

    if (!F.OpenFile(FileName))
    {
        Log("MatchLogger: ERROR - Could not open file " $ FileName);
        F.Destroy();
        return False;
    }

    DurationSecs = int(Level.TimeSeconds - MatchStartTime);
    DateStr = string(Level.Year) $ "-" $ PadNumber(Level.Month) $ "-" $ PadNumber(Level.Day);
    TimeStr = PadNumber(Level.Hour) $ ":" $ PadNumber(Level.Minute) $ ":" $ PadNumber(Level.Second);

    F.WriteLine("# Match Information");
    F.WriteLine("Server," $ EscapeCSV(ServerName));
    F.WriteLine("Map," $ EscapeCSV(MapName));
    F.WriteLine("GameType," $ EscapeCSV(GameType));
    F.WriteLine("Duration," $ string(DurationSecs));
    F.WriteLine("Date," $ DateStr);
    F.WriteLine("Time," $ TimeStr);
    F.WriteLine("");

    F.WriteLine("# Scoreboard");
    F.WriteLine("Rank,PlayerName,Score,Deaths,KDRatio,Ping,IsBot,WeaponStats");

    for (i = 0; i < NumTrackedPlayers; i++)
    {
        Stats = PlayerStats[i];
        if (Stats == None)
            continue;

        if (!bIncludeSpectators && Stats.bIsSpectator)
            continue;
        if (!ShouldIncludeStats(Stats))
            continue;

        WeaponBreakdown = "";
        for (j = 0; j < Stats.NumWeaponTypes; j++)
        {
            TempDamageTypeName = Stats.GetDamageTypeNameAt(j);
            TempKills = Stats.GetWeaponKillsAt(j);
            TempWeaponName = GetWeaponDisplayName(TempDamageTypeName);
            TempWeaponEntry = TempWeaponName $ ":" $ string(TempKills);

            if (j > 0)
                WeaponBreakdown = WeaponBreakdown $ ";";

            WeaponBreakdown = WeaponBreakdown $ TempWeaponEntry;
        }

        CSVLine = string(i + 1)
            $ "," $ EscapeCSV(Stats.PlayerName)
            $ "," $ string(Stats.FinalScore)
            $ "," $ string(Stats.Deaths)
            $ "," $ FormatFloat(GetKDRatio(Stats), 2)
            $ "," $ string(Stats.Ping)
            $ "," $ string(Stats.bIsBot)
            $ "," $ EscapeCSV(WeaponBreakdown);

        F.WriteLine(CSVLine);
    }

    F.CloseFile();
    F.Destroy();
    return True;
}

function string EscapeCSV(string Input)
{
    if (InStr(Input, ",") >= 0 || InStr(Input, Chr(34)) >= 0 || InStr(Input, Chr(10)) >= 0 || InStr(Input, Chr(13)) >= 0)
    {
        Input = ReplaceString(Input, Chr(34), Chr(34) $ Chr(34));
        return Chr(34) $ Input $ Chr(34);
    }
    return Input;
}

function string EscapeHTML(string Input)
{
    Input = ReplaceString(Input, "&", "&amp;");
    Input = ReplaceString(Input, "<", "&lt;");
    Input = ReplaceString(Input, ">", "&gt;");
    Input = ReplaceString(Input, Chr(34), "&quot;");
    return Input;
}

function string ReplaceString(string Source, string Find, string With)
{
    local int Pos;
    local string Result;

    if (Find == "")
        return Source;

    Result = "";
    Pos = InStr(Source, Find);

    while (Pos >= 0)
    {
        Result = Result $ Left(Source, Pos) $ With;
        Source = Mid(Source, Pos + Len(Find));
        Pos = InStr(Source, Find);
    }

    return Result $ Source;
}

function float GetKDRatio(MLPlayerStats Stats)
{
    if (Stats == None)
        return 0.0;

    if (Stats.Deaths > 0)
        return float(Stats.FinalScore) / float(Stats.Deaths);
    return float(Stats.FinalScore);
}


defaultproperties
{
    bEnabled=True
    bLogHTML=True
    bLogCSV=True
    LogPath="../Logs/MatchResults"
    bIncludeSpectators=False
    bIncludeBots=True
    LogMode=0
}
