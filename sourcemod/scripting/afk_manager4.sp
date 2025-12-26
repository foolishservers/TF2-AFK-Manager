#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <tf2>

//#define DEBUG_MODE
#if defined DEBUG_MODE
stock void  DEBUG_LOG(int client, const char[] format, any...)
{
    if (!IsValidClient(client) || IsFakeClient(client))
    {
        return;
    }

    char buffer[512];
    VFormat(buffer, sizeof(buffer), format, 3);
    PrintToChat(client, "[AFK Manager DEBUG] %s", buffer);
}
#else
stock void DEBUG_LOG(int client, const char[] format, any...)
{
    #pragma unused client, format
}
#endif

#define AFKM_VERSION         "5.0.0"
#define AFK_WARNING_INTERVAL 5
#define AFK_CHECK_INTERVAL   1.0
#define MAX_MESSAGE_LENGTH   250

enum
{
    OBS_MODE_NONE,
    OBS_MODE_DEATHCAM,
    OBS_MODE_FREEZECAM
}

enum AFKImmunity
{
    AFKImmunity_None,
    AFKImmunity_Kick,
    AFKImmunity_Full
};

enum
{
    CONVAR_VERSION,
    CONVAR_ENABLED,
    CONVAR_MOD_AFK,
    CONVAR_PREFIXSHORT,
    CONVAR_MINPLAYERSKICK,
    CONVAR_ADMINS_IMMUNE,
    CONVAR_TIMETOKICK,
    CONVAR_ARRAY_SIZE
}

AFKImmunity g_iPlayerImmunity[MAXPLAYERS + 1];
char        g_Prefix[16];

int         g_iPlayerUserID[MAXPLAYERS + 1];
int         g_iAFKTime[MAXPLAYERS + 1] = { -1, ... };
int         iButtons[MAXPLAYERS + 1];
int         g_iPlayerTeam[MAXPLAYERS + 1];
int         iObserverMode[MAXPLAYERS + 1]   = { -1, ... };
int         iObserverTarget[MAXPLAYERS + 1] = { -1, ... };
int         g_iMapEndTime                   = -1;
int         g_iAdminsImmunue                = -1;
int         g_iTimeToKick;
int         g_iTimeToMove;
int         g_iSpec_Team                 = 1;

bool        bPlayerAFK[MAXPLAYERS + 1]   = { true, ... };
bool        bPlayerMoved[MAXPLAYERS + 1] = { false, ... };
bool        g_bEnabled;
bool        bKickPlayers;
bool        bMovePlayers;

Handle      g_hAFKTimer[MAXPLAYERS + 1];

ConVar      hCvarAFK;
ConVar      hCvarEnabled;
ConVar      hCvarPrefixShort;
ConVar      hCvarMinPlayersKick;
ConVar      hCvarMinPlayersMove;
ConVar      hCvarAdminsImmune;
ConVar      hCvarAdminsFlag;
ConVar      hCvarKickPlayers;
ConVar      hCvarMoveSpec;
ConVar      hCvarTimeToKick;
ConVar      hCvarTimeToMove;
ConVar      hCvarWarnTimeToKick;
ConVar      hCvarWarnTimeToMove;

// Plugin Information
public Plugin myinfo =
{
    name        = "[TF2] AFK Manager",
    author      = "Rothgar, JoinedSenses",
    description = "Takes action on AFK players",
    version     = AFKM_VERSION,
    url         = "http://www.dawgclan.net"
};

public void OnPluginStart()
{
    LoadTranslations("common.phrases");
    LoadTranslations("afk_manager.phrases");

    CreateConVar("sm_afkm_version", AFKM_VERSION, "Current version of the AFK Manager", FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);
    hCvarEnabled        = CreateConVar("sm_afk_enable", "1", "Is the AFK Manager enabled or disabled? [0 = FALSE, 1 = TRUE, DEFAULT: 1]", FCVAR_NONE, true, 0.0, true, 1.0);
    hCvarPrefixShort    = CreateConVar("sm_afk_prefix_short", "0", "Should the AFK Manager use a short prefix? [0 = FALSE, 1 = TRUE, DEFAULT: 0]", FCVAR_NONE, true, 0.0, true, 1.0);
    hCvarMinPlayersKick = CreateConVar("sm_afk_kick_min_players", "6", "Minimum number of connected clients required for AFK kick to be enabled. [DEFAULT: 6]");
    hCvarMinPlayersMove = CreateConVar("sm_afk_move_min_players", "4", "Minimum number of connected clients required for AFK move to spectator to be enabled. [DEFAULT: 4]");
    hCvarAdminsImmune   = CreateConVar("sm_afk_admins_immune", "1", "Should admins be immune to the AFK Manager? [0 = DISABLED, 1 = COMPLETE IMMUNITY, 2 = KICK IMMUNITY");
    hCvarAdminsFlag     = CreateConVar("sm_afk_admins_flag", "", "Admin Flag for immunity? Leave Blank for any flag.");
    hCvarKickPlayers    = CreateConVar("sm_afk_kick_players", "1", "Should the AFK Manager kick AFK clients? [0 = DISABLED, 1 = KICK ALL, 2 = ALL EXCEPT SPECTATORS, 3 = SPECTATORS ONLY]");
    hCvarMoveSpec       = CreateConVar("sm_afk_move_spec", "1", "Should the AFK Manager move AFK clients to spectator team? [0 = FALSE, 1 = TRUE, DEFAULT: 1]", FCVAR_NONE, true, 0.0, true, 1.0);
    hCvarTimeToKick     = CreateConVar("sm_afk_kick_time", "120.0", "Time in seconds (total) client must be AFK before being kicked. [0 = DISABLED, DEFAULT: 120.0 seconds]");
    hCvarTimeToMove     = CreateConVar("sm_afk_move_time", "60.0", "Time in seconds (total) client must be AFK before being moved to spectator. [0 = DISABLED, DEFAULT: 60.0 seconds]");
    hCvarWarnTimeToKick = CreateConVar("sm_afk_kick_warn_time", "30.0", "Time in seconds remaining, player should be warned before being kicked for AFK. [DEFAULT: 30.0 seconds]");
    hCvarWarnTimeToMove = CreateConVar("sm_afk_move_warn_time", "30.0", "Time in seconds remaining, player should be warned before being moved for AFK. [DEFAULT: 30.0 seconds]");
    hCvarAFK            = FindConVar("mp_idledealmethod");

    hCvarEnabled.AddChangeHook(CvarChange_Status);
    hCvarAFK.AddChangeHook(CvarChange_Status);
    hCvarPrefixShort.AddChangeHook(CvarChange_Status);
    hCvarAdminsImmune.AddChangeHook(CvarChange_Status);
    hCvarTimeToKick.AddChangeHook(CvarChange_Status);
    hCvarTimeToMove.AddChangeHook(CvarChange_Status);

    g_Prefix         = hCvarPrefixShort.BoolValue ? "AFK" : "AFK Manager";
    g_iAdminsImmunue = hCvarAdminsImmune.IntValue;
    g_iTimeToKick    = hCvarTimeToKick.IntValue;
    g_iTimeToMove    = hCvarTimeToMove.IntValue;
    hCvarAFK.SetInt(0);

    HookEvent("player_disconnect", Event_PlayerDisconnectPost, EventHookMode_Post);
    HookEvent("player_team", Event_PlayerTeam);
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeathPost, EventHookMode_Post);
    AutoExecConfig(true, "afk_manager");

    // Initialize g_bEnabled from ConVar
    g_bEnabled = hCvarEnabled.BoolValue;

    // Reinitialize all existing players (for hot reload support)
    if (g_bEnabled)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && !IsFakeClient(i))
            {
                InitializePlayer(i);
            }
        }
        int clientCount = AFK_GetClientCount();
        bKickPlayers    = (clientCount >= hCvarMinPlayersKick.IntValue);
        bMovePlayers    = (clientCount >= hCvarMinPlayersMove.IntValue);
    }
}

public void OnMapStart()
{
    if (!g_bEnabled)
    {
        return;
    }
    AutoExecConfig(true, "afk_manager");
    if (g_iMapEndTime == -1)
    {
        return;
    }
    int iMapChangeTime = GetTime() - g_iMapEndTime;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (g_iAFKTime[i] != -1)
        {
            g_iAFKTime[i] = g_iAFKTime[i] + iMapChangeTime;
        }
    }
    g_iMapEndTime = -1;
}

public void OnMapEnd()
{
    if (!g_bEnabled)
    {
        return;
    }
    g_iMapEndTime = GetTime();
}

public void OnClientPostAdminCheck(int client)
{
    if (!g_bEnabled || IsFakeClient(client))
    {
        return;
    }
    InitializePlayer(client);
    int clientCount = AFK_GetClientCount();
    bKickPlayers    = (clientCount >= hCvarMinPlayersKick.IntValue);
    bMovePlayers    = (clientCount >= hCvarMinPlayersMove.IntValue);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if (!g_bEnabled || !IsClientConnected(client) || IsFakeClient(client) || g_hAFKTimer[client] == null)
    {
        return Plugin_Continue;
    }
    if (cmdnum <= 0)
    {
        return Plugin_Handled;
    }

    // No button change AND no mouse movement = still AFK
    if (iButtons[client] == buttons)
    {
        return Plugin_Continue;
    }

    // Observer: update buttons but don't reset AFK
    if (IsClientObserver(client))
    {
        iButtons[client] = buttons;
        return Plugin_Continue;
    }

    // Living player activity (button or mouse) = not AFK
    iButtons[client]   = buttons;
    bPlayerAFK[client] = false;
    return Plugin_Continue;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
    if (g_bEnabled && g_hAFKTimer[client] != null)
    {
        DEBUG_LOG(client, "Player %N sent chat message, resetting AFK", client);
        ResetPlayer(client, false);
    }
    return Plugin_Continue;
}

public Action Event_PlayerDisconnectPost(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bEnabled)
    {
        return Plugin_Continue;
    }

    int userID = event.GetInt("userid");
    int client = GetClientOfUserId(userID);

    if (0 < client <= MaxClients)
    {
        UnInitializePlayer(client);
    }
    else {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (g_iPlayerUserID[i] == userID)
            {
                UnInitializePlayer(i);
            }
        }
    }
    bKickPlayers = (AFK_GetClientCount() >= hCvarMinPlayersKick.IntValue);
    bMovePlayers = (AFK_GetClientCount() >= hCvarMinPlayersMove.IntValue);
    return Plugin_Continue;
}

public Action Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bEnabled)
    {
        return Plugin_Continue;
    }
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && IsValidClient(client) && g_hAFKTimer[client] != null)
    {
        int newTeam = event.GetInt("team");
        DEBUG_LOG(client, "Player %N changed team to %d (Spectator team: %d)", client, newTeam, g_iSpec_Team);
        g_iPlayerTeam[client] = newTeam;
        if (g_iPlayerTeam[client] != g_iSpec_Team)
        {
            // Player joined a non-spectator team - reset AFK state completely
            DEBUG_LOG(client, "Player %N joined active team, resetting AFK state");
            ResetObserver(client);
            ResetPlayer(client, false);
            bPlayerMoved[client] = false;    // Allow move-to-spec to work again
        }
    }
    return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bEnabled)
    {
        return Plugin_Continue;
    }
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && IsValidClient(client) && g_hAFKTimer[client] != null)
    {
        if (g_iPlayerTeam[client] == 0)
        {
            return Plugin_Continue;
        }
        if (!IsClientObserver(client) && IsPlayerAlive(client) && GetClientHealth(client) > 0)
        {
            DEBUG_LOG(client, "Player %N spawned, resetting AFK time", client);
            ResetObserver(client);
            // Reset AFK time on spawn to prevent false AFK from accumulated dead time
            ResetPlayer(client, false);
        }
    }
    return Plugin_Continue;
}

public Action Event_PlayerDeathPost(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bEnabled)
    {
        return Plugin_Continue;
    }
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0 && IsValidClient(client) && g_hAFKTimer[client] != null)
    {
        if (IsClientObserver(client))
        {
            iObserverMode[client]   = GetEntProp(client, Prop_Send, "m_iObserverMode");
            iObserverTarget[client] = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
        }
    }
    return Plugin_Continue;
}

Action Timer_CheckPlayer(Handle Timer, int client)
{
    if (!g_bEnabled)
    {
        return Plugin_Stop;
    }
    if (!IsClientInGame(client) || (GetEntityFlags(client) & FL_FROZEN))
    {
        g_iAFKTime[client]++;
        return Plugin_Continue;
    }
    // Skip AFK check for dead players (not spectators) - they're waiting to respawn
    int clientTeam = GetClientTeam(client);
    if (!IsPlayerAlive(client) && clientTeam != g_iSpec_Team && !IsClientObserver(client))
    {
        // Dead on RED/BLU team - reset AFK time and skip
        g_iAFKTime[client] = GetTime();
        return Plugin_Continue;
    }
    if (IsClientObserver(client))
    {
        int m_iObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");
        if (iObserverMode[client] == -1)
        {
            iObserverMode[client] = m_iObserverMode;
            // Don't return - continue to kick logic
        }
        else if (iObserverMode[client] != m_iObserverMode)
        {
            // Observer mode changed - this counts as activity, reset AFK
            if (iObserverMode[client] != OBS_MODE_DEATHCAM && iObserverMode[client] != OBS_MODE_FREEZECAM)
            {
                SetClientAFK(client);
            }
            iObserverMode[client] = m_iObserverMode;
            if (iObserverMode[client] != 7)
            {
                iObserverTarget[client] = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
            }
        }
        else if (iObserverMode[client] != 7)
        {
            int m_hObserverTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
            if (iObserverTarget[client] != m_hObserverTarget)
            {
                // Target changed manually - this counts as activity
                if (IsValidClient(iObserverTarget[client]) && iObserverTarget[client] != client && IsPlayerAlive(iObserverTarget[client]))
                {
                    SetClientAFK(client);
                }
                iObserverTarget[client] = m_hObserverTarget;
            }
        }
        // Don't return - continue to kick logic below
    }
    int Time = GetTime();

    if (!bPlayerAFK[client])
    {
        SetClientAFK(client, (!IsPlayerAlive(client) && iObserverTarget[client] == client) ? false : true);
        return Plugin_Continue;
    }

    // If neither kick nor move is enabled, just track AFK time
    if (!bKickPlayers && !bMovePlayers)
    {
        g_iAFKTime[client]++;
        return Plugin_Continue;
    }

    int AFKTime = (g_iAFKTime[client] >= 0) ? (Time - g_iAFKTime[client]) : 0;
    DEBUG_LOG(client, "Player %N AFK time: %d seconds (Move threshold: %d, Kick threshold: %d)", client, AFKTime, g_iTimeToMove, g_iTimeToKick);

    // Move to spectator logic (only for non-spectators/alive players who haven't been moved yet)
    // Use IsClientObserver() and IsPlayerAlive() for accurate detection instead of g_iPlayerTeam
    bool isActivePlayer = IsPlayerAlive(client) && !IsClientObserver(client);
    if (bMovePlayers && hCvarMoveSpec.BoolValue && g_iTimeToMove > 0 && !bPlayerMoved[client] && isActivePlayer)
    {
        int AFKMoveTimeleft = g_iTimeToMove - AFKTime;
        if (AFKMoveTimeleft < 0 || AFKTime >= g_iTimeToMove)
        {
            return MoveAFKClient(client);
        }
        else if (AFKTime % AFK_WARNING_INTERVAL == 0 && (g_iTimeToMove - AFKTime) <= hCvarWarnTimeToMove.IntValue) {
            PrintToChat(client, "%t", "Move_Warning", AFKMoveTimeleft);
        }
    }

    // Kick logic
    int iKickPlayers = hCvarKickPlayers.IntValue;
    if (!bKickPlayers || iKickPlayers <= 0)
    {
        return Plugin_Continue;
    }

    // Check kick mode restrictions using real-time team check
    bool isSpectator = (clientTeam == g_iSpec_Team || IsClientObserver(client));

    bool canKick     = false;
    if (iKickPlayers == 1)
    {
        canKick = true;    // KICK ALL
    }
    else if (iKickPlayers == 2 && !isSpectator) {
        canKick = true;    // ALL EXCEPT SPECTATORS
    }
    else if (iKickPlayers == 3 && isSpectator) {
        canKick = true;    // SPECTATORS ONLY
    }

    if (!canKick)
    {
        return Plugin_Continue;
    }

    int AFKKickTimeleft = g_iTimeToKick - AFKTime;
    if (AFKKickTimeleft < 0 || AFKTime >= g_iTimeToKick)
    {
        return KickAFKClient(client);
    }
    else if (AFKTime % AFK_WARNING_INTERVAL == 0 && (g_iTimeToKick - AFKTime) <= hCvarWarnTimeToKick.IntValue) {
        PrintToChat(client, "%t", "Kick_Warning", AFKKickTimeleft);
    }
    return Plugin_Continue;
}

Action KickAFKClient(int client)
{
    char clientName[MAX_NAME_LENGTH];
    GetClientName(client, clientName, sizeof(clientName));
    DEBUG_LOG(client, "Kicking AFK player %N (%s)", client, clientName);
    KickClient(client, "[%s] %t", g_Prefix, "Kick_Message");
    PrintToChatAll("%t", "Kick_Announce", clientName);
    return Plugin_Handled;
}

Action MoveAFKClient(int client)
{
    // Mark player as moved to prevent repeated move attempts
    bPlayerMoved[client] = true;

    // Move client to spectator team
    DEBUG_LOG(client, "Moving AFK player %N to spectator", client);
    ChangeClientTeam(client, g_iSpec_Team);

    // Announce move to all players
    char clientName[MAX_NAME_LENGTH];
    GetClientName(client, clientName, sizeof(clientName));
    PrintToChatAll("%t", "Move_Announce", clientName);

    // Reset AFK time for kick timer (starts fresh from when they were moved)
    g_iAFKTime[client] = GetTime();

    return Plugin_Continue;
}

void SetPlayerImmunity(int client, int type, bool AFKImmunityType = false)
{
    if (AFKImmunityType && (AFKImmunity_None <= view_as<AFKImmunity>(type) <= AFKImmunity_Full))
    {
        g_iPlayerImmunity[client] = view_as<AFKImmunity>(type);
        if (g_iPlayerImmunity[client] == AFKImmunity_Full)
        {
            ResetAFKTimer(client);
        }
        else {
            InitializeAFK(client);
        }
    }
    else if (!AFKImmunityType && (0 <= type <= 2)) {
        switch (type)
        {
            case 1:
            {
                g_iPlayerImmunity[client] = AFKImmunity_Full;
                ResetAFKTimer(client);
                return;
            }
            case 2:
            {
                g_iPlayerImmunity[client] = AFKImmunity_Kick;
            }
            default:
            {
                g_iPlayerImmunity[client] = AFKImmunity_None;
            }
        }
        InitializeAFK(client);
    }
}

void ResetAFKTimer(int index)
{
    delete g_hAFKTimer[index];
    ResetPlayer(index);
}

void ResetObserver(int index)
{
    iObserverMode[index]   = -1;
    iObserverTarget[index] = -1;
}

void ResetPlayer(int index, bool FullReset = true)
{
    bPlayerAFK[index] = true;

    if (FullReset)
    {
        g_iPlayerUserID[index] = -1;
        g_iAFKTime[index]      = -1;
        g_iPlayerTeam[index]   = -1;
        bPlayerMoved[index]    = false;
        ResetObserver(index);
    }
    else {
        g_iAFKTime[index] = GetTime();
    }
}

void SetClientAFK(int client, bool Reset = true)
{
    if (Reset)
    {
        DEBUG_LOG(client, "Player %N AFK status reset", client);
        ResetPlayer(client, false);
    }
    else {
        DEBUG_LOG(client, "Player %N marked as AFK", client);
        bPlayerAFK[client] = true;
    }
}

void InitializeAFK(int index)
{
    if (g_hAFKTimer[index] == null)
    {
        DEBUG_LOG(index, "Starting AFK timer for player %N (Team: %d)", index, GetClientTeam(index));
        g_iAFKTime[index]    = GetTime();
        g_iPlayerTeam[index] = GetClientTeam(index);
        g_hAFKTimer[index]   = CreateTimer(AFK_CHECK_INTERVAL, Timer_CheckPlayer, index, TIMER_REPEAT);
    }
}

void InitializePlayer(int index)
{
    if (!IsValidClient(index))
    {
        return;
    }
    int iClientUserID = GetClientUserId(index);
    if (iClientUserID != g_iPlayerUserID[index])
    {
        DEBUG_LOG(index, "Initializing player %N (UserID: %d)", index, iClientUserID);
        ResetAFKTimer(index);
        g_iPlayerUserID[index] = iClientUserID;
    }
    if (g_iAdminsImmunue > 0 && g_iPlayerImmunity[index] == AFKImmunity_None && CheckAdminImmunity(index))
    {
        DEBUG_LOG(index, "Player %N has admin immunity (type: %d)", index, g_iAdminsImmunue);
        SetPlayerImmunity(index, g_iAdminsImmunue);
    }
    if (g_iPlayerImmunity[index] != AFKImmunity_Full)
    {
        InitializeAFK(index);
    }
}

void UnInitializePlayer(int index)
{
    ResetAFKTimer(index);
    g_iPlayerImmunity[index] = AFKImmunity_None;
}

void CvarChange_Status(ConVar cvar, const char[] oldvalue, const char[] newvalue)
{
    if (StrEqual(oldvalue, newvalue))
    {
        return;
    }
    if (cvar == hCvarEnabled)
    {
        hCvarEnabled.BoolValue ? EnablePlugin() : DisablePlugin();
    }
    else if (cvar == hCvarAdminsImmune) {
        g_iAdminsImmunue = StringToInt(newvalue);
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsValidClient(i) && CheckAdminImmunity(i))
            {
                SetPlayerImmunity(i, g_iAdminsImmunue);
            }
        }
    }
    else if (cvar == hCvarTimeToKick) {
        g_iTimeToKick = StringToInt(newvalue);
    }
    else if (cvar == hCvarTimeToMove) {
        g_iTimeToMove = StringToInt(newvalue);
    }
    else if (cvar == hCvarPrefixShort) {
        g_Prefix = hCvarPrefixShort.BoolValue ? "AFK" : "AFK Manager";
    }
    else if (cvar == hCvarAFK && StringToInt(newvalue) != 0) {
        cvar.SetInt(0);
    }
}

void EnablePlugin()
{
    g_bEnabled = true;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
        {
            InitializePlayer(i);
        }
    }
    int clientCount = AFK_GetClientCount();
    bKickPlayers    = (clientCount >= hCvarMinPlayersKick.IntValue);
    bMovePlayers    = (clientCount >= hCvarMinPlayersMove.IntValue);
}

void DisablePlugin()
{
    g_bEnabled = false;

    for (int i = 1; i <= MaxClients; i++)
    {
        UnInitializePlayer(i);
    }
}

int AFK_GetClientCount(bool inGameOnly = true)
{
    int clients = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (((inGameOnly) ? IsClientInGame(i) : IsClientConnected(i)) && !IsClientSourceTV(i) && !IsFakeClient(i))
        {
            clients++;
        }
    }
    return clients;
}

stock bool IsValidClient(int client, bool replaycheck = true)
{
    return (0 < client && client <= MaxClients && IsClientInGame(client) && !GetEntProp(client, Prop_Send, "m_bIsCoaching")
            && !(replaycheck && (IsClientSourceTV(client) || IsClientReplay(client))));
}

bool CheckAdminImmunity(int client)
{
    int iUserFlagBits = GetUserFlagBits(client);
    if (iUserFlagBits > 0)
    {
        char sFlags[32];
        hCvarAdminsFlag.GetString(sFlags, sizeof(sFlags));
        return (StrEqual(sFlags, "") || (iUserFlagBits & (ReadFlagString(sFlags) | ADMFLAG_ROOT) > 0));
    }
    return false;
}