//=============================================================================
// MLPlayerStats.uc
// Rev 9
// Tracks per-player statistics including weapon kills
// Part of the MatchLogger mutator package
//=============================================================================
class MLPlayerStats extends Info;

// Player reference
var Pawn TrackedPlayer;
var PlayerReplicationInfo TrackedPRI;
var string PlayerName;

// Final stats (captured at end of game)
var int FinalScore;
var int Deaths;
var int Ping;
var byte Team;
var bool bIsBot;
var bool bIsSpectator;

// Weapon kill tracking
struct WeaponKillData
{
    var name DamageTypeName;
    var string WeaponClass;
    var int Kills;
};

var WeaponKillData WeaponKills[24];
var int NumWeaponTypes;

// Track a kill by damage type (preferred) with optional weapon-class context.
function AddDamageTypeKill(name DamageName, optional string WeaponClassName)
{
    local int i;

    for (i = 0; i < NumWeaponTypes; i++)
    {
        if (WeaponKills[i].DamageTypeName == DamageName &&
            WeaponKills[i].WeaponClass ~= WeaponClassName)
        {
            WeaponKills[i].Kills++;
            return;
        }
    }

    if (NumWeaponTypes < 24)
    {
        WeaponKills[NumWeaponTypes].DamageTypeName = DamageName;
        WeaponKills[NumWeaponTypes].WeaponClass = WeaponClassName;
        WeaponKills[NumWeaponTypes].Kills = 1;
        NumWeaponTypes++;
    }
}

// Accessors to avoid oversized context expressions in older UnrealScript compilers
function name GetDamageTypeNameAt(int Index)
{
    if (Index >= 0 && Index < NumWeaponTypes)
        return WeaponKills[Index].DamageTypeName;

    return '';
}

function int GetWeaponKillsAt(int Index)
{
    if (Index >= 0 && Index < NumWeaponTypes)
        return WeaponKills[Index].Kills;

    return 0;
}

function string GetWeaponClassAt(int Index)
{
    if (Index >= 0 && Index < NumWeaponTypes)
        return WeaponKills[Index].WeaponClass;

    return "";
}

// Get total kills across all weapons
function int GetTotalKills()
{
    local int i;
    local int Total;

    for (i = 0; i < NumWeaponTypes; i++)
        Total += WeaponKills[i].Kills;

    return Total;
}

// Get kills for a specific weapon/damage type
function int GetKillsForWeapon(string WeaponOrDamageType)
{
    local int i;

    for (i = 0; i < NumWeaponTypes; i++)
    {
        if (WeaponKills[i].WeaponClass ~= WeaponOrDamageType ||
            string(WeaponKills[i].DamageTypeName) ~= WeaponOrDamageType)
        {
            return WeaponKills[i].Kills;
        }
    }

    return 0;
}

defaultproperties
{
    bHidden=True
    bAlwaysRelevant=False
    RemoteRole=ROLE_None
}
