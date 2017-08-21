#pragma dynamic 4194304 // Increases stack space to 4mb, needed for encryption

#include <sourcemod>
#include <regex>

#define AUTOLOAD_EXTENSIONS
#define REQUIRE_EXTENSIONS
#include <steamworks>
#include <smjansson>

#include "steamcore/bigint.sp"
#include "steamcore/rsa.sp"
#include "steamcore/login.sp"
#include "steamcore/community.sp"
#include "steamcore/chat.sp"

#define PLUGIN_NAME "SteamCore"
#define PLUGIN_AUTHOR "Statik"
#define PLUGIN_VERSION "2.0"
#define PLUGIN_URL "https://github.com/polvora/SteamCore"

/**
TO-DO:
- More efficient enryption
- Updater support ?
- Add message queue
- IsFriend()
- Http wrapper
- "personarelationship"
- Separate machine cookie from login
- Steam account handle ?? 
- Trade ???
- More configs (timeouts, retrys, etc.)
*/

public Plugin:myinfo = 
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = "Sourcemod natives to interact with Steam functions.",
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
}

#define DEBUG_FILE_NAME "steamcore_debug"

new bool:isDebugEnabled = false;
new String:debugFilePath[128];
new Handle:cvarDebug;

//new bool:areSteamServersUp = true;

public APLRes:AskPluginLoad2(Handle:plugin, bool:late, String:error[], err_max)
{
	RegPluginLibrary("steamcore");
	
	AskLoginPluginLoad2();
	AskCommunityPluginLoad2();
	AskChatPluginLoad2();
	
	return APLRes_Success;
}

public OnPluginStart()
{
	// Convars
	CreateConVar("steamcore_version", PLUGIN_VERSION, "SteamCore Version", FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY);
	cvarDebug = CreateConVar("sc_debug", "0", "Toggles debugging.", 0, true, 0.0, true, 1.0);
	
	HookConVarChange(cvarDebug, OnDebugStatusChange);
	
	new String:date[32];
	FormatTime(date, sizeof date, "%Y%m%d");
	BuildPath(Path_SM, debugFilePath, sizeof debugFilePath, "logs/%s_%s.log", DEBUG_FILE_NAME, date);
	
	OnLoginPluginStart();
	OnCommunityPluginStart();
	OnChatPluginStart();
	
	SteamLogIn();
}

public OnDebugStatusChange(Handle:cvar, const String:oldVal[], const String:newVal[]) { isDebugEnabled = bool:StringToInt(newVal); }
public OnConfigsExecuted() { isDebugEnabled = GetConVarBool(FindConVar("sc_debug")); }

//public SteamWorks_SteamServersConnected() { areSteamServersUp = true; }
//public SteamWorks_SteamServersDisconnected(EResult:result) { areSteamServersUp = false; }
//AreSteamServersUp() { return areSteamServersUp; }

/** All Functions with prefixes (ex: Prefix_Function()) are called from other files **/
/** For convenience all callings between different files pass through this file. **/

GetCookie(String:cookie[], maxlength) { Login_GetCookie(cookie, maxlength); }
GetSessionId(String:sessionId[], maxlength) { Login_GetSessionId(sessionId, maxlength); }
GetChatToken(String:token[], maxlength) { Login_GetChatToken(token, maxlength); }

bool:IsAccountLogged() { return Login_IsAccountLogged(); }
SteamLogIn() { Login_SteamLogIn(); }

OnSteamLogIn()
{
	Chat_OnSteamLogIn();
}

LogDebug(const String:format[], any:...)
{
	if (isDebugEnabled)
	{
		decl String:text[2048];
		VFormat(text, sizeof(text), format, 2);
		if (FindCharInString(text, '\n') != 0) // If string doesn't start with a new line
		{
			Format(text, sizeof text, "\n%s", text);
		}
		LogToFile(debugFilePath, text);
	}
}