#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.2"

bool gB_Late;

public Plugin myinfo =
{
	name = "Simple AFK Kicker",
	author = "shavit & modified by madwayz",
	description = "Checks for AFK players and kicks them if they fail a verification.",
	version = PLUGIN_VERSION,
	url = "http://forums.alliedmods.net/member.php?u=163134"
}

float gF_Position[MAXPLAYERS+1][3];
float gF_Angles[MAXPLAYERS+1][3];
int gI_Buttons[MAXPLAYERS+1];
int gI_Matches[MAXPLAYERS+1];

Handle gT_RoundStart = null;

ConVar gCV_AdminImmune = null;
ConVar gCV_WaitTime = null;
ConVar gCV_Verify = null;
ConVar gCV_CaptchaTime = null;
ConVar gCV_Matches = null;
ConVar gCV_Logging = null;

char gS_LogFile[1024];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	if(gB_Late)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			OnClientPutInServer(i);
		}
	}

	HookEvent("round_start", Round_Start);
	HookEvent("round_end", Round_End);

	CreateConVar("afk_kicker_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY|FCVAR_DONTRECORD);

	gCV_AdminImmune = CreateConVar("afk_kicker_admin_immunity", "1", "Are admins immunable to AFK kicks?");
	gCV_WaitTime = CreateConVar("afk_kicker_wait_time", "30.0", "Time to wait since the round starts before verifying players.");
	gCV_Verify = CreateConVar("afk_kicker_verify", "1", "Verify if a player is AFK by sending a captcha-like menu?\nSetting to 0 will result in an instant kick upon suspicion of an AFK player and may cause false positives.");
	gCV_CaptchaTime = CreateConVar("afk_kicker_captcha_time", "12", "How much time will a player have to answer the captcha?");
	gCV_Matches = CreateConVar("afk_kicker_matches_required", "2", "Amount of matches (same data since the round starts) required before sending verifications.\nMatches:\nKey presses, crosshair position and player position.");
	gCV_Logging = CreateConVar("afk_kicker_logging", "1", "Log kicks to \"addons/sourcemod/logs/afk_kicker.log\"?");

	AutoExecConfig();

	BuildPath(Path_SM, gS_LogFile, 1024, "logs/afk_kicker.log");
}

public void OnClientPutInServer(int client)
{
	gF_Position[client] = view_as<float>({0.0, 0.0, 0.0});
	gF_Angles[client] = view_as<float>({0.0, 0.0, 0.0});
	gI_Buttons[client] = 0;
	gI_Matches[client] = 0;
}	

public void Round_Start(Handle event, const char[] name, bool dB)
{
	if(gT_RoundStart != null)
	{
		delete gT_RoundStart;
	}

	if(!IsPaused() && !IsWarmup() && !IsFreezeTime())
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i, true))
			{
				GetClientAbsOrigin(i, gF_Position[i]);
				GetClientEyeAngles(i, gF_Angles[i]);

				gI_Buttons[i] = GetClientButtons(i);
				gI_Matches[i] = 0;
			}
		}
	}

	gT_RoundStart = CreateTimer(gCV_WaitTime.FloatValue, Timer_AFKCheck);
}

public Action Timer_AFKCheck(Handle Timer)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i, true))
		{
			if(gCV_AdminImmune.BoolValue && CheckCommandAccess(i, "afk-kicker-immunity", ADMFLAG_ROOT))
			{
				continue;
			}

			float fPosition[3];
			GetClientAbsOrigin(i, fPosition);

			float fAngles[3];
			GetClientEyeAngles(i, fAngles);

			int iButtons = GetClientButtons(i);

			int iMatches = 0;

			if(bVectorsEqual(fPosition, gF_Position[i]))
			{
				iMatches++;
			}

			if(bVectorsEqual(fAngles, gF_Angles[i]))
			{
				iMatches++;
			}

			if(iButtons == gI_Buttons[i])
			{
				iMatches++;
			}

			gI_Matches[i] = iMatches;

			if(iMatches >= gCV_Matches.IntValue && !IsPaused() && !IsWarmup() && !IsFreezeTime())
			{
				if(gCV_Verify.BoolValue)
				{
					PopupAFKMenu(i, gCV_CaptchaTime.IntValue);
				}

				else
				{
					NukeClient(i, true, gI_Matches[i], "(instant kick - no verification menu)");
				}
			}
		}
	}

	gT_RoundStart = null;

	return Plugin_Stop;
}

public void PopupAFKMenu(int client, int time)
{
	Menu m = new Menu(MenuHandler_AFKVerification);

	m.SetTitle("Может быть Вас кикнуть?");
	m.AddItem("stay", "Нет! Не кикайте меня, я здесь!");
	m.ExitButton = false;

	m.Display(client, time);
}

public int MenuHandler_AFKVerification(Menu m, MenuAction a, int p1, int p2)
{
	switch(a)
	{
		case MenuAction_Select:
		{
			char buffer[8];
			m.GetItem(p2, buffer, 8);

			if(StrEqual(buffer, "stay"))
			{
				PrintHintText(p1, "AFK верификация пройдена успешно!\n Вы не будете кикнуты.");
			}
		}

		case MenuAction_Cancel:
		{
			// no response
			if(p2 == MenuCancel_Timeout)
			{
				NukeClient(p1, true, gI_Matches[p1], "(Не ответил капче)");
			}
		}

		case MenuAction_End:
		{
			delete m;
		}

	}

	return 0;
}

public void NukeClient(int client, bool bLog, int iMatches, const char[] sLog)
{
	if(IsValidClient(client))
	{
		KickClient(client, "Вы были кикнуты за AFK.");

		if(gCV_Logging.BoolValue && bLog)
		{
			LogToFile(gS_LogFile, "%L - Kicked for being AFK. (Matches: %d) %s", client, iMatches, sLog);
		}
	}
}

public void Round_End(Handle event, const char[] name, bool dB)
{
	if(gT_RoundStart != null)
	{
		delete gT_RoundStart;
		gT_RoundStart = null;
	}
}

stock bool IsValidClient(int client, bool bAlive = false)
{
	return (client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsClientSourceTV(client) && (!bAlive || IsPlayerAlive(client)));
}

stock bool bVectorsEqual(float[3] v1, float[3] v2)
{
	return (v1[0] == v2[0] && v1[1] == v2[1] && v1[2] == v2[2]);
}

stock bool IsPaused() 
{	
	return view_as<bool>(GameRules_GetProp("m_bMatchWaitingForResume"));
}

stock bool IsWarmup() 
{
	return view_as<bool>(GameRules_GetProp("m_bWarmupPeriod"));
}

stock bool IsFreezeTime()
{
	return view_as<bool>(GameRules_GetProp("m_bFreezePeriod"));
}