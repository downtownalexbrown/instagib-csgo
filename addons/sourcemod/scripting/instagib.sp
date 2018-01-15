#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <emitsoundany>

#define NULL_VELOCITY Float:{0.0, 0.0, 0.0}

bool lazerwait[MAXPLAYERS + 1];
bool dashwait[MAXPLAYERS + 1];
new _Laser;

public Plugin:myinfo =
{
	name = "Instagib",
	author = "beef",
	description = "A Counter Strike Global Offensive adaption of the Instagib gamemode",
	version = "2.0",
	url = ""
}

public OnPluginStart()
{
	AddNormalSoundHook(SoundHook);

	HookEvent("round_start", onRoundStart);
	HookEvent("player_spawn", onPlayerSpawn);
	HookEvent("player_death", onPlayerDeath);
	HookEvent("player_team", onPlayerTeam);
}

// Hooked events should go down here
public onRoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	StartRoundCommands();
}

public onPlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	// Spawn player on join team, thus avoiding rounds

	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	CreateTimer(1.5, respawnPlayer, client);
}

public OnMapStart()
{
	_Laser = PrecacheModel("materials/sprites/laserbeam.vmt", true);
	PrecacheSoundAny("instagib/kill.mp3");
	AddFileToDownloadsTable("sound/instagib/kill.mp3");

	MapStartCommands();
}

public onPlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	SetEntityHealth(client, 1);
	
	// Remove weapons
	new windex = -1;
	while ((windex = FindEntityByClassname(windex, "weapon_knife")) != -1)
	{
	     	if(IsValidEntity(windex))
        	  	AcceptEntityInput(windex, "kill");
	}

	GiveWeapons(client);
}

public onPlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	new killer = GetClientOfUserId(GetEventInt(event, "attacker"));
	new killed = GetClientOfUserId(GetEventInt(event, "userid"));

	if(killer > 0 && IsClientInGame(killer) && killer != killed)
	{
		EmitSoundToClientAny(killer, "instagib/kill.mp3");
	}
	
	CreateTimer(3.0, respawnPlayer, killed);
}

public Action respawnPlayer(Handle timer, int client) {
	if (client > 0 && IsClientInGame(client))
		CS_RespawnPlayer(client);
}

public OnClientPostAdminCheck(client)
{
	lazerwait[client] = false;
	dashwait[client] = false;

	CreateTimer(2.0, PrintText, client);
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_OnTakeDamage, onTakeDamage);
}

// Actions
public Action PrintText(Handle timer, int client)
{
	PrintToChat(client, " \x04Thanks for joining \x02Instagib\x04!");
}

public Action SoundHook(clients[64], &numClients, String:sound[PLATFORM_MAX_PATH], &Ent, &channel, &Float:volume, &level, &pitch, &flags)
{
    if (StrEqual(sound, "player/damage1.wav", false)) return Plugin_Stop;
    if (StrEqual(sound, "player/damage2.wav", false)) return Plugin_Stop;
    if (StrEqual(sound, "player/damage3.wav", false)) return Plugin_Stop;
    return Plugin_Continue;
}

public Action onTakeDamage(client, &attacker, &inflictor, &Float:damage, &damagetype)
{
	if(damagetype & DMG_FALL) return Plugin_Handled;

	return Plugin_Continue;
}

public Action OnPlayerRunCmd(int client, int &iButtons, int &iImpulse, float fVelocity[3], float fAngles[3], int &iWeapon)
{
	// autobhop
	if((iButtons & IN_JUMP))
	{
		if(!(GetEntityFlags(client) & FL_ONGROUND))
		{
			if (!(GetEntityMoveType(client) & MOVETYPE_LADDER))
			{
				iButtons &= ~IN_JUMP;
			}
		}
	}

	if(!lazerwait[client])
	{
		if (IsClientInGame(client) && (iButtons & IN_ATTACK))
		{
			// Get position of client and their viewmodel angles
			float pos[3], clientEye[3], clientAngle[3];
			GetClientEyePosition(client, clientEye);
			GetClientEyeAngles(client, clientAngle);

			TR_TraceRayFilter(clientEye, clientAngle, MASK_SOLID, RayType_Infinite, TraceRayDontHitSelf, client);
			if (TR_DidHit(INVALID_HANDLE)) // global
				{
					decl Float:vecPosition[3];
					GetClientAbsOrigin(client, vecPosition);

					// TE_SetupBeamPoints is defined here: https://sm.alliedmods.net/new-api/sdktools_tempents_stocks/TE_SetupBeamPoints

					if(GetClientTeam(client) == CS_TEAM_T)
					{
						TR_GetEndPosition(pos);
						TE_SetupBeamPoints(clientEye, pos, _Laser, 0, 0, 0, 1.4, 2.0, 2.0, 1, 0.0, {255, 0, 0, 255}, 15);
						TE_SendToAll(0.0);
					}

					if(GetClientTeam(client) == CS_TEAM_CT)
					{
						TR_GetEndPosition(pos);
						TE_SetupBeamPoints(clientEye, pos, _Laser, 0, 0, 0, 1.4, 2.0, 2.0, 1, 0.0, {0, 0, 255, 255}, 15);
						TE_SendToAll(0.0);
					}

  					Client_SetArmor(client, 0);
					CreateTimer(1.4, fullArmor, client);
					CreateTimer(0.2, setAmmoFn, client);

					lazerwait[client] = true;
					CreateTimer(1.4, ChangeLazerWait, client);

				}
			}
	}

	if(!dashwait[client])
	{
			if(IsClientInGame(client) && (iButtons & IN_ATTACK2))
			{
				float EyeAngles[3], Push[3], vec[3];

				GetClientEyeAngles(client, EyeAngles);
				GetClientAbsOrigin(client, vec);

				// Fancy trig stuff which finds a location ahead of the client based on their viewmodel angles. Props to Eric Edson for help on this.
				Push[0] = (950.0 * Cosine(DegToRad(EyeAngles[1])));
				Push[1] = (950.0 * Sine(DegToRad(EyeAngles[1])));
				Push[2] = (-950.0 * Sine(DegToRad(EyeAngles[0])));

				TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, Push); // Uses the location found above to teleport the player there, giving the "boost" effect

				dashwait[client] = true;
				CreateTimer(2.5, ChangeDashWait, client);
			}
	}
}

public Action ChangeDashWait(Handle timer, int client)
{
	dashwait[client] = false;
}

public Action ChangeLazerWait(Handle timer, int client)
{
	new weapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");

	if(lazerwait[client] == true)
	{
		lazerwait[client] = false;

		if(IsValidEntity(weapon))
		{
			SetReserveAmmo(client, weapon, 0);
			SetClipAmmo(client, weapon, 1);
		}
	}
}

public Action setAmmoFn(Handle timer, int client)
{
	new weapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");

	if(IsValidEntity(weapon))
	{
		SetReserveAmmo(client, weapon, 0);
		SetClipAmmo(client, weapon, 0);
	}
}

public Action fullArmor(Handle timer, int client)
{
        Client_SetArmor(client, 100);
}

// Stocks for cleanliness
stock StartRoundCommands()
{
	ServerCommand("mp_free_armor 1");
	ServerCommand("mp_playercashawards 0");
	ServerCommand("mp_teamcashawards 0");
	ServerCommand("sv_staminajumpcost 0");
	ServerCommand("sv_staminalandcost 0");
	ServerCommand("sv_accelerate 6.5");
	ServerCommand("mp_falldamage 0");
}

stock MapStartCommands()
{
	ServerCommand("mp_death_drop_gun 0");
	ServerCommand("sv_enablebunnyhopping 1");
	ServerCommand("sm_cvar weapon_accuracy_nospread 1");
	ServerCommand("sv_airaccelerate 1000");
	ServerCommand("bot_kick");
	ServerCommand("mp_warmuptime 0");
	ServerCommand("sv_full_alltalk 1");
	ServerCommand("mp_solid_teammates 0");
}

stock Client_SetArmor(client, value)
{
	SetEntProp(client, Prop_Data, "m_ArmorValue", value);
}

stock SetClipAmmo(client, weapon, ammo)
{
	SetEntProp(weapon, Prop_Send, "m_iClip1", ammo);
	SetEntProp(weapon, Prop_Send, "m_iClip2", ammo);
}

stock SetReserveAmmo(client, weapon, ammo)
{
	SetEntProp(weapon, Prop_Send, "m_iPrimaryReserveAmmoCount", ammo); // Set reserve ammo to 0

	// Get ammotype and confirm it is valid
	new ammotype = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
	if(ammotype == -1)
		return;

	SetEntProp(client, Prop_Send, "m_iAmmo", ammo, _, ammotype);
}

public GiveWeapons(client){
	// Remove the weapon from every slot, then give the player a p250
	// This needs to be called before setting any ammo, preferably at the start of the round
	new weapon = -1;
	for (new i = 0; i <= 6; i++)	{
    		if ((weapon = GetPlayerWeaponSlot(client, i)) != -1)	{
       			RemovePlayerItem(client, weapon);
    		}
	}

	GivePlayerItem(client, "weapon_p250");
	new hWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
	if(IsValidEntity(hWeapon))
		SetReserveAmmo(client, hWeapon, 0); // TODO: eventually make sure that this is a p250 so you don't set the reserve ammo of a c4 or something
}

public bool TraceRayDontHitSelf(entity, mask, any:data)
{
	if(entity == data)
		return false;

  	return true;
}
