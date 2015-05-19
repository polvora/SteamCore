#pragma dynamic 4194304 // Increases stack space to 4mb, needed for encryption

#include <sourcemod>
#include <regex>

// Core includes
#include "steamcore/bigint.sp"
#include "steamcore/rsa.sp"

#define AUTOLOAD_EXTENSIONS
#define REQUIRE_EXTENSIONS
#include <steamworks>

#define PLUGIN_URL ""
#define PLUGIN_VERSION "1.5"
#define PLUGIN_NAME "SteamCore"
#define PLUGIN_AUTHOR "Statik"

public Plugin:myinfo = 
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = "Sourcemod natives to interact with Steam functions.",
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
}

new bool:DEBUG = false;

new const TIMER_UPDATE_TIME = 6;
new const TOKEN_LIFETIME = 50;
new const Float:TIMEOUT_TIME = 5.0;

new Handle:cvarUsername;
new Handle:cvarPassword;
new Handle:cvarDebug;

new String:username[32] = "";
new String:passphrase[32] = "";
new String:sessionToken[32] = "";
new String:sessionCookie[256] = "";
new bool:isLogged = false;
new bool:isBusy = false;
new Handle:request;

new caller;

new timeSinceLastLogin;
new Handle:hTimeIncreaser;

new Handle:timeoutTimer;
new bool:connectionInterrupted;

new Handle:callbackHandle;
new Handle:callbackPlugin;
new Function:callbackFunction;
new Handle:finalRequest;
new SteamWorksHTTPRequestCompleted:finalFunction;

// ===================================================================================
// ===================================================================================

public APLRes:AskPluginLoad2(Handle:plugin, bool:late, String:error[], err_max)
{
	// Native creation
	CreateNative("IsSteamCoreBusy", nativeIsSteamCoreBusy);
	CreateNative("SteamGroupAnnouncement", nativeGroupAnnouncement);
	CreateNative("SteamGroupInvite", nativeGroupInvite);
	
	RegPluginLibrary("steamcore");
	
	return APLRes_Success;
}

public OnPluginStart()
{
	// Callbacks
	callbackHandle = CreateForward(ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	
	// Timers
	hTimeIncreaser = CreateTimer(TIMER_UPDATE_TIME*60.0, timeIncreaser, INVALID_HANDLE, TIMER_REPEAT);
	
	// Convars
	CreateConVar("steamcore_version", PLUGIN_VERSION, "SteamCore Version", FCVAR_PLUGIN | FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY);
	cvarUsername = CreateConVar("sc_username", "", "Steam login username.", FCVAR_PROTECTED | FCVAR_PLUGIN);
	cvarPassword = CreateConVar("sc_password", "", "Steam login password.", FCVAR_PROTECTED | FCVAR_PLUGIN);
	cvarDebug = CreateConVar("sc_debug", "0", "Toggles debugging.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	
	HookConVarChange(cvarUsername, OnLoginInfoChange);
	HookConVarChange(cvarPassword, OnLoginInfoChange);
	HookConVarChange(cvarDebug, OnDebugStatusChange);
	
	timeSinceLastLogin = TOKEN_LIFETIME;
}

public OnLoginInfoChange(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	isLogged = false;
}

public OnDebugStatusChange(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	DEBUG = bool:StringToInt(newVal);
}

public Action:timeIncreaser(Handle:timer)
{
	timeSinceLastLogin += TIMER_UPDATE_TIME;
	PrintDebug(0, "\n============================================================================\n");
	PrintDebug(0, "Time since last login: %i minutes.", timeSinceLastLogin);
	if (timeSinceLastLogin >= TOKEN_LIFETIME)
	{
		isLogged = false;
		PrintDebug(0, "Expired token lifetime (%i)", TOKEN_LIFETIME);
	}
	return Plugin_Continue;
}

public OnConfigsExecuted()
{
	DEBUG = GetConVarBool(FindConVar("sc_debug"));
	if (timeSinceLastLogin > 10)
	{
		PrintDebug(0, "\n============================================================================\n");
		PrintDebug(0, "Logging in to keep login alive...");
		startRequest(0, INVALID_HANDLE, INVALID_FUNCTION, INVALID_HANDLE, INVALID_FUNCTION); // Starts an empty login request
	}
}

// ===================================================================================
// ===================================================================================

public nativeIsSteamCoreBusy(Handle:plugin, numParams)
{
	return _:isBusy;
}

public nativeGroupAnnouncement(Handle:plugin, numParams)
{
	decl String:title[256];
	decl String:body[1024];
	decl String:groupID[64];
	new client = GetNativeCell(1);
	GetNativeString(2, title, sizeof(title));
	GetNativeString(3, body, sizeof(body));
	GetNativeString(4, groupID, sizeof(groupID));
	
	decl String:URL[128];
	Format(URL, sizeof(URL), "http://steamcommunity.com/gid/%s/announcements", groupID);
	
	PrintDebug(client, "\n============================================================================\n");
	PrintDebug(client, "Preparing request to: \n%s...", URL);
	PrintDebug(client, "Title: \n%s", title);
	PrintDebug(client, "Body: \n%s", body);
	PrintDebug(client, "Verifying login...");
	
	new Handle:_finalRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, URL);
	SteamWorks_SetHTTPRequestHeaderValue(_finalRequest, "Cookie", sessionCookie);
	SteamWorks_SetHTTPRequestGetOrPostParameter(_finalRequest, "action", "post");
	SteamWorks_SetHTTPRequestGetOrPostParameter(_finalRequest, "sessionID", sessionToken);
	SteamWorks_SetHTTPRequestGetOrPostParameter(_finalRequest, "headline", title);
	SteamWorks_SetHTTPRequestGetOrPostParameter(_finalRequest, "body", body);
	
	startRequest(client, _finalRequest, cbkGroupAnnouncement, plugin, Function:GetNativeCell(5));
}

public nativeGroupInvite(Handle:plugin, numParams)
{
	decl String:invitee[64];
	decl String:groupID[64];
	new client = GetNativeCell(1);
	GetNativeString(2, invitee, sizeof invitee);
	GetNativeString(3, groupID, sizeof groupID);
	
	decl String:URL[] = "http://steamcommunity.com/actions/GroupInvite";
	
	PrintDebug(client, "\n============================================================================\n");
	PrintDebug(client, "Preparing request to: \n%s...", URL);
	PrintDebug(client, "Invitee community ID: \n%s", invitee);
	PrintDebug(client, "Group community ID: \n%s", groupID);
	PrintDebug(client, "Verifying login...");
	
	new Handle:_finalRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, URL);
	
	SteamWorks_SetHTTPRequestHeaderValue(_finalRequest, "Accept", "*/*");
	SteamWorks_SetHTTPRequestHeaderValue(_finalRequest, "Accept-Encoding", "gzip, deflate");
	SteamWorks_SetHTTPRequestHeaderValue(_finalRequest, "User-Agent", "Mozilla/5.0 (Windows NT 6.3; WOW64)");
	SteamWorks_SetHTTPRequestHeaderValue(_finalRequest, "Cookie", sessionCookie);
	
	//SteamWorks_SetHTTPRequestGetOrPostParameter(_finalRequest, "json", "1");
	SteamWorks_SetHTTPRequestGetOrPostParameter(_finalRequest, "type", "groupInvite");
	SteamWorks_SetHTTPRequestGetOrPostParameter(_finalRequest, "sessionID", sessionToken);
	SteamWorks_SetHTTPRequestGetOrPostParameter(_finalRequest, "group", groupID);
	SteamWorks_SetHTTPRequestGetOrPostParameter(_finalRequest, "invitee", invitee);
	
	startRequest(client, _finalRequest, cbkGroupInvite, plugin, Function:GetNativeCell(4));
}

// ===================================================================================
// ===================================================================================

startRequest(client, Handle:_finalRequest, SteamWorksHTTPRequestCompleted:_finalFunction, Handle:_callbackPlugin, Function:_callbackFunction)
{		
	if (isBusy)
	{
		PrintDebug(client, "\n============================================================================\n");
		PrintDebug(client, "Plugin is busy with other task at this time, rejecting request...");
		
		if (_callbackFunction != INVALID_FUNCTION) // There is an actual function callback
		{
			new pluginIteratorNumber = GetPluginIteratorNumber(_callbackPlugin);
			new Handle:datapack;
			CreateDataTimer(0.1, tmrBusyCallback, datapack);
			WritePackCell(datapack, client);
			WritePackCell(datapack, pluginIteratorNumber);
			WritePackCell(datapack, _callbackFunction);
			
			CloseHandle(_finalRequest);
		}
		return;
	}
	isBusy = true;
	connectionInterrupted = false;
	
	caller = client;
	finalRequest = _finalRequest;
	finalFunction = _finalFunction;
	callbackPlugin = _callbackPlugin;
	callbackFunction = _callbackFunction;
	
	PrintDebug(caller, "\n============================================================================\n");
	
	if (callbackFunction != INVALID_FUNCTION) // There is an actual function callback
	{
		AddToForward(callbackHandle, callbackPlugin, callbackFunction);
		
		if (isLogged)
		{
			PrintDebug(caller, "Already logged in, executing request...");
			SteamWorks_SetHTTPCallbacks(finalRequest, finalFunction)
			SteamWorks_SendHTTPRequest(finalRequest);
			startTimeoutTimer();
			return;
		}
	}
	GetConVarString(cvarUsername, username, sizeof(username));
	GetConVarString(cvarPassword, passphrase, sizeof(passphrase));
	
	if (StrEqual(username, "") || StrEqual(passphrase, ""))
	{
		PrintDebug(caller, "Invalid login information, check cvars. ABORTED.");
		onRequestResult(caller, false, 0x03); // Invalid login information
		return;
	}
	
	request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, "http://steamcommunity.com/login/getrsakey/");
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "username", username);
	SteamWorks_SetHTTPCallbacks(request, cbkRsaKeyRequest);
	SteamWorks_SendHTTPRequest(request);
	startTimeoutTimer();
	
	PrintDebug(caller, "Obtaining RSA Key from steamcommunity.com/login/getrsakey...");
}

startTimeoutTimer()
{
	stopTimeoutTimer();
	timeoutTimer = CreateTimer(TIMEOUT_TIME, tmrTimeout);
}

stopTimeoutTimer()
{
	if (timeoutTimer != INVALID_HANDLE)
	{
		KillTimer(timeoutTimer);
		timeoutTimer = INVALID_HANDLE;
	}
}

public Action:tmrTimeout(Handle:timer)
{
	PrintDebug(caller, "Connection timed out.");
	connectionInterrupted = true;
	onRequestResult(caller, false, 0x02);
	timeoutTimer = INVALID_HANDLE;
}

public Action:tmrBusyCallback(Handle:timer, Handle:pack)
{
	ResetPack(pack);
	new client = ReadPackCell(pack);
	new pluginIteratorNumber = ReadPackCell(pack);
	new Handle:callbackPl = FindPluginFromNumber(pluginIteratorNumber);
	new Function:callbackFunc = ReadPackCell(pack);
	
	new bool:success = RemoveFromForward(callbackHandle, callbackPlugin, callbackFunction);
	new functionCount = GetForwardFunctionCount(callbackHandle);
	PrintDebug(caller, "Removing main callback from forward - Result: %i, - Forward Function Count: %i", success, functionCount);
	
	success = AddToForward(callbackHandle, callbackPl, callbackFunc);
	functionCount = GetForwardFunctionCount(callbackHandle);
	PrintDebug(caller, "Adding temporal callback from forward - Result: %i, - Forward Function Count: %i", success, functionCount);
	
	// Start function call
	Call_StartForward(callbackHandle);
	// Push parameters one at a time
	Call_PushCell(client);
	Call_PushCell(false);
	Call_PushCell(0x01); // Plugin is busy
	Call_PushCell(0);
	// Finish the call
	new result = Call_Finish();
	PrintDebug(caller, "Temporal callback calling error code: %i (0: Success)", result);
	
	success = RemoveFromForward(callbackHandle, callbackPl, callbackFunc);
	functionCount = GetForwardFunctionCount(callbackHandle);
	PrintDebug(caller, "Removing temporal callback from forward - Result: %i, - Forward Function Count: %i", success, functionCount);
	
	success = AddToForward(callbackHandle, callbackPlugin, callbackFunction);
	functionCount = GetForwardFunctionCount(callbackHandle);
	PrintDebug(caller, "Re-adding main callback from forward - Result: %i, - Forward Function Count: %i", success, functionCount);
	
	callbackPl = INVALID_HANDLE;
	callbackFunc = INVALID_FUNCTION;
	
	PrintDebug(caller, "Task rejected.");
}

public cbkRsaKeyRequest(Handle:response, bool:failure, bool:requestSuccessful, EHTTPStatusCode:statusCode)
{
	stopTimeoutTimer();
	if (connectionInterrupted)
	{
		CloseHandle(request);
		request = INVALID_HANDLE;
		return;
	}
	
	if (response == INVALID_HANDLE || !requestSuccessful || statusCode != k_EHTTPStatusCode200OK)
	{
		PrintDebug(caller, "RSA Key request failed (%i). Status Code: %i. ABORTED", requestSuccessful, statusCode);
		onRequestResult(caller, false, 0x04); // Failed http RSA Key request
		CloseHandle(request);
		request = INVALID_HANDLE;
		return;
	}
	new bodySize;
	SteamWorks_GetHTTPResponseBodySize(request, bodySize);
	decl String:responseBody[bodySize];
	SteamWorks_GetHTTPResponseBodyData(request, responseBody, bodySize);
	PrintDebug(caller, responseBody);
	
	if (StrContains(responseBody, "\"success\":true", false) == -1)
	{
		PrintDebug(caller, "Could not get RSA Key, aborting...");
		onRequestResult(caller, false, 0x05); // RSA Key response failed, unknown reason
		CloseHandle(request);
		request = INVALID_HANDLE;
		return;
	}
	new Handle:regex;
	regex = CompileRegex("\"publickey_mod\":\"(.*?)\"");
	MatchRegex(regex, responseBody);
	decl String:rsaPublicMod[1024];
	GetRegexSubString(regex, 1, rsaPublicMod, sizeof(rsaPublicMod));
	CloseHandle(regex);
	regex = INVALID_HANDLE;
	
	PrintDebug(caller, "RSA KEY MODULUS (%i): \n%s", strlen(rsaPublicMod), rsaPublicMod);
	
	regex = CompileRegex("\"publickey_exp\":\"(.*?)\"");
	MatchRegex(regex, responseBody);
	decl String:rsaPublicExp[16];
	GetRegexSubString(regex, 1, rsaPublicExp, sizeof(rsaPublicExp));
	CloseHandle(regex);
	regex = INVALID_HANDLE;
	
	PrintDebug(caller, "RSA KEY EXPONENT (%i): %s", strlen(rsaPublicExp), rsaPublicExp);
	
	regex = CompileRegex("\"timestamp\":\"(.*?)\"");
	MatchRegex(regex, responseBody);
	decl String:steamTimestamp[16];
	GetRegexSubString(regex, 1, steamTimestamp, sizeof(steamTimestamp));
	CloseHandle(regex);
	regex = INVALID_HANDLE;
	
	PrintDebug(caller, "STEAM TIMESTAMP (%i): %s", strlen(steamTimestamp), steamTimestamp);
	
	PrintDebug(caller, "\n============================================================================\n");
	
	PrintDebug(caller, "Encrypting passphrase ******** with RSA public key...");
	decl String:encryptedPassword[1024];
	rsaEncrypt(rsaPublicMod, rsaPublicExp, passphrase, encryptedPassword, sizeof(encryptedPassword));
	PrintDebug(caller, "Encrypted passphrase with RSA cryptosystem (%i): \n%s", strlen(encryptedPassword), encryptedPassword);
	
	decl numericPassword[1024];
	hexString2BigInt(encryptedPassword, numericPassword, sizeof(numericPassword));
	encodeBase64(numericPassword, strlen(rsaPublicMod),encryptedPassword, sizeof(encryptedPassword));
	PrintDebug(caller, "Encoded encrypted passphrase with base64 algorithm (%i): \n%s", strlen(encryptedPassword), encryptedPassword);
	
	CloseHandle(request);
	request = INVALID_HANDLE;
	
	PrintDebug(caller, "\n============================================================================\n");
	
	PrintDebug(caller, "Logging in to steamcommunity.com/login/dologin/...");
	request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, "https://steamcommunity.com/login/dologin/");
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "password", encryptedPassword);
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "username", username);
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "twofactorcode", "");
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "emailauth", "");
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "loginfriendlyname", "");
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "captchagid", "");
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "captcha_text", "");
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "emailsteamid", "");
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "rsatimestamp", steamTimestamp);
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "remember_login", "false");
	SteamWorks_SetHTTPCallbacks(request, cbkLoginRequest);
	SteamWorks_SendHTTPRequest(request);
	startTimeoutTimer();
}

public cbkLoginRequest(Handle:response, bool:failure, bool:requestSuccessful, EHTTPStatusCode:statusCode)
{
	stopTimeoutTimer();
	if (connectionInterrupted)
	{
		CloseHandle(request);
		request = INVALID_HANDLE;
		return;
	}
	
	if (response == INVALID_HANDLE || !requestSuccessful || statusCode != k_EHTTPStatusCode200OK)
	{
		PrintDebug(caller, "Login request failed (%i). Status Code: %i. ABORTED", requestSuccessful, statusCode);
		onRequestResult(caller, false, 0x06); // Failed htpps login request
		CloseHandle(request);
		request = INVALID_HANDLE;
		return;
	}
	new bodySize;
	SteamWorks_GetHTTPResponseBodySize(response, bodySize);
	decl String:responseBody[bodySize];
	SteamWorks_GetHTTPResponseBodyData(response, responseBody, bodySize);
	
	new Handle:regex;
	regex = CompileRegex("\"success\":(.*?),");
	MatchRegex(regex, responseBody);
	decl String:successString[20];
	GetRegexSubString(regex, 1, successString, sizeof(successString));
	CloseHandle(regex);
	regex = INVALID_HANDLE;
	
	if (strcmp(successString, "true") != 0) // successString != true
	{
		PrintDebug(caller, "Aborted logging, incorrect response body (%i): \n%s", strlen(responseBody), responseBody);
		onRequestResult(caller, false, 0x07); // Incorrect login data, required captcha or e-mail confirmation (Steam Guard)
		CloseHandle(request);
		request = INVALID_HANDLE;
		return;
	}
	new cookieSize;
	SteamWorks_GetHTTPResponseHeaderSize(response, "Set-Cookie", cookieSize);
	SteamWorks_GetHTTPResponseHeaderValue(response, "Set-Cookie", sessionCookie, cookieSize);
	
	// Cleaning cookie
	ReplaceString(sessionCookie, sizeof sessionCookie, "path=/,", "");
	ReplaceString(sessionCookie, sizeof sessionCookie, "path=/; httponly,", "");
	ReplaceString(sessionCookie, sizeof sessionCookie, "path=/; secure; httponly", "");
	
	PrintDebug(caller, "Success, got response (%i): \n%s", strlen(responseBody), responseBody);
	PrintDebug(caller, "Stored Cookie (%i): \n%s", strlen(sessionCookie), sessionCookie);
	
	
	CloseHandle(request);
	request = INVALID_HANDLE;
	
	PrintDebug(caller, "\n============================================================================\n");
	
	PrintDebug(caller, "Logging successful, obtaining session token...");
	
	request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, "http://steamcommunity.com/profiles/RedirectToHome");
	SteamWorks_SetHTTPRequestHeaderValue(request, "Cookie", sessionCookie);
	SteamWorks_SetHTTPCallbacks(request, cbkTokenRequest);
	SteamWorks_SendHTTPRequest(request);
	startTimeoutTimer();
}

public cbkTokenRequest(Handle:response, bool:failure, bool:requestSuccessful, EHTTPStatusCode:statusCode)
{
	stopTimeoutTimer();
	if (connectionInterrupted)
	{
		CloseHandle(request);
		request = INVALID_HANDLE;
		return;
	}
	
	if (response == INVALID_HANDLE || !requestSuccessful || statusCode != k_EHTTPStatusCode200OK)
	{
		PrintDebug(caller, "Session Token request failed (%i). Status Code: %i. ABORTED", requestSuccessful, statusCode);
		onRequestResult(caller, false, 0x08); // Failed http token request
		CloseHandle(request);
		request = INVALID_HANDLE;
		return;
	}
	new bodySize;
	SteamWorks_GetHTTPResponseBodySize(response, bodySize);
	decl String:responseBody[bodySize];
	SteamWorks_GetHTTPResponseBodyData(response, responseBody, bodySize);
	
	new Handle:regex;
	regex = CompileRegex("g_steamID = (.*?);");
	MatchRegex(regex, responseBody);
	decl String:steamId[20];
	GetRegexSubString(regex, 1, steamId, sizeof(steamId));
	CloseHandle(regex);
	regex = INVALID_HANDLE;
	
	regex = CompileRegex("g_sessionID = \"(.*?)\"");
	MatchRegex(regex, responseBody);
	GetRegexSubString(regex, 1, sessionToken, sizeof(sessionToken));
	CloseHandle(regex);
	regex = INVALID_HANDLE;
	
	if (strcmp(steamId, "false") == 0) // steamId == false
	{
		PrintDebug(caller, "Could not get session token. Got: \"%s\". Incorrect Cookie?", steamId);
		onRequestResult(caller, false, 0x09); // Invalid session token. Incorrect cookie?
		CloseHandle(request);
		request = INVALID_HANDLE;
		return;
	}
	isLogged = true;
	
	// Cleaning cookie
	ReplaceString(sessionCookie, sizeof sessionCookie, "path=/; httponly,", "");
	ReplaceString(sessionCookie, sizeof sessionCookie, "path=/; secure; httponly", "");
	
	Format(sessionCookie, sizeof sessionCookie, "Steam_Language=english; sessionid=%s; %s", sessionToken, sessionCookie);
	
	PrintDebug(caller, "Session token successfully acquired (%i): %s", strlen(sessionToken), sessionToken);
	PrintDebug(caller, "Current session for Steam ID (%i): %s", strlen(steamId), steamId);
	PrintDebug(caller, "Appended session token to clean cookie, actual cookie (%i): \n%s", strlen(sessionCookie), sessionCookie);
	
	if (finalRequest != INVALID_HANDLE)
	{
		PrintDebug(caller, "\n============================================================================\n");
		
		PrintDebug(caller, "Executing final request...");
		SteamWorks_SetHTTPCallbacks(finalRequest, finalFunction);
		SteamWorks_SendHTTPRequest(finalRequest);
		startTimeoutTimer();
	}
	else 
	{
		PrintDebug(caller, "There is no final request, logged in successfully.");
		onRequestResult(caller, true);
	}
	
	CloseHandle(request);
	request = INVALID_HANDLE;
}

public cbkGroupAnnouncement(Handle:response, bool:failure, bool:requestSuccessful, EHTTPStatusCode:statusCode)
{
	stopTimeoutTimer();
	if (connectionInterrupted)
	{
		CloseHandle(finalRequest);
		finalRequest = INVALID_HANDLE;
		finalFunction = INVALID_FUNCTION;
		return;
	}
	
	if (response == INVALID_HANDLE || !requestSuccessful || statusCode != k_EHTTPStatusCode200OK)
	{
		PrintDebug(caller, "Group announcement request failed (%i). Status Code: %i", requestSuccessful, statusCode);
		onRequestResult(caller, false, 0x10); // Failed http group announcement request
		CloseHandle(finalRequest);
		finalRequest = INVALID_HANDLE;
		finalFunction = INVALID_FUNCTION;
		return;
	}
	new cookieSize;
	SteamWorks_GetHTTPResponseHeaderSize(response, "Set-Cookie", cookieSize);
	decl String:cookie[cookieSize];
	SteamWorks_GetHTTPResponseHeaderValue(response, "Set-Cookie", cookie, cookieSize);
	
	new bodySize;
	SteamWorks_GetHTTPResponseBodySize(response, bodySize);
	decl String:responseBody[bodySize];
	SteamWorks_GetHTTPResponseBodyData(response, responseBody, bodySize);
	
	new Handle:regex;
	regex = CompileRegex("steamLogin=(.*?);");
	MatchRegex(regex, cookie);
	decl String:steamLogin[20];
	GetRegexSubString(regex, 1, steamLogin, sizeof(steamLogin));
	CloseHandle(regex);
	regex = INVALID_HANDLE;
	
	regex = CompileRegex("<title>(.*?)</title>");
	MatchRegex(regex, responseBody);
	decl String:title[40];
	GetRegexSubString(regex, 1, title, sizeof(title));
	CloseHandle(regex);
	regex = INVALID_HANDLE;
	
	if (strcmp(steamLogin, "deleted") == 0)
	{
		isLogged = false;
		PrintDebug(caller, "Invalid steam login token.");
		onRequestResult(caller, false, 0x11); // Invalid steam login token
		CloseHandle(finalRequest);
		finalRequest = INVALID_HANDLE;
		finalFunction = INVALID_FUNCTION;
		return;
	}
	if (strcmp(title, "Steam Community :: Error") == 0)
	{
		PrintDebug(caller, "Form error on request.");
		onRequestResult(caller, false, 0x12); // Form error on request
		CloseHandle(finalRequest);
		finalRequest = INVALID_HANDLE;
		finalFunction = INVALID_FUNCTION;
		return;
	}
	
	onRequestResult(caller, true);
	
	CloseHandle(finalRequest);
	finalRequest = INVALID_HANDLE;
	finalFunction = INVALID_FUNCTION;
}

public cbkGroupInvite(Handle:response, bool:failure, bool:requestSuccessful, EHTTPStatusCode:statusCode)
{
	stopTimeoutTimer();
	if (connectionInterrupted)
	{
		CloseHandle(finalRequest);
		finalRequest = INVALID_HANDLE;
		finalFunction = INVALID_FUNCTION;
		return;
	}
	
	if (response == INVALID_HANDLE || !requestSuccessful || statusCode != k_EHTTPStatusCode200OK)
	{
		PrintDebug(caller, "Group invite request failed (%i). Status Code: %i", requestSuccessful, statusCode);
		onRequestResult(caller, false, 0x20); // Failed http group invite request
		CloseHandle(finalRequest);
		finalRequest = INVALID_HANDLE;
		finalFunction = INVALID_FUNCTION;
		return;
	}
	new bodySize;
	SteamWorks_GetHTTPResponseBodySize(response, bodySize);
	decl String:responseBody[bodySize];
	SteamWorks_GetHTTPResponseBodyData(response, responseBody, bodySize);
	
	new Handle:regex;
	regex = CompileRegex("<results><!\\[CDATA\\[(.*?)\\]\\]><\\/results>", PCRE_DOTALL);
	MatchRegex(regex, responseBody);
	decl String:result[2048];
	GetRegexSubString(regex, 1, result, sizeof(result));
	CloseHandle(regex);
	regex = INVALID_HANDLE;
	
	if (!StrEqual(result, "OK"))
	{
		if (StrEqual(result, "The invitation to that player failed. Please try again.\n\nError code: 19"))
		{
			PrintDebug(caller, "Invite failed. Incorrect invitee id on request or another error.");
			onRequestResult(caller, false, 0x21); // Incorrect invitee or another error
		}
		else if (StrEqual(result, "Missing Data"))
		{
			PrintDebug(caller, "Invite failed. Incorrect group id or missing data on request.");
			onRequestResult(caller, false, 0x22); // Incorrect Group ID or missing data.
		}
		else if (StrEqual(result, "Missing or invalid form session key"))
		{
			isLogged = false;
			PrintDebug(caller, "Invite failed. Plugin is not logged in. Try again to login.");
			onRequestResult(caller, false, 0x23); // Logged out. Retry to login
		}
		else if (StrEqual(result, "You do not have permission to invite to the group specified."))
		{
			PrintDebug(caller, "Invite failed. Inviter account is not a member of the group or does not have permissions to invite.");
			onRequestResult(caller, false, 0x24); // Account does not have permissions to invite.
		}
		else if (StrEqual(result, "Your account does not meet the requirements to use this feature. <a class=\"whiteLink\" target=\"_blank\" href=\"https://support.steampowered.com/kb_article.php?ref=3330-IAGK-7663\">Visit Steam Support</a> for more information."))
		{
			PrintDebug(caller, "Invite failed. Account is limited, only full Steam accounts can send group invites.");
			onRequestResult(caller, false, 0x25); // Limited account. Only full Steam accounts can send Steam group invites
		}
		else
		{
			PrintDebug(caller, "Invite failed. Unknown error response received when sending the group invite.");
			onRequestResult(caller, false, 0x26); // Unknown error
		}
	}
	else
	{
		if (StrContains(responseBody, "<duplicate><![CDATA[1]]></duplicate>") != -1)
		{
			PrintDebug(caller, "Invite failed. Invitee has already received an invite or is already on the group.");
			onRequestResult(caller, false, 0x27); // Invitee has already received an invite or is already on the group.
		}
		else
		{
			PrintDebug(caller, "Group invite sent.");
			onRequestResult(caller, true); // Success
		}	
	}
	PrintDebug(caller, "Response body (%i):\n %s", strlen(responseBody), responseBody);
	
	CloseHandle(finalRequest);
	finalRequest = INVALID_HANDLE;
	finalFunction = INVALID_FUNCTION;
}

onRequestResult(client, bool:success, errorCode=0, any:data=0)
{
	isBusy = false;
	
	PrintDebug(caller, "\n============================================================================\n");
	
	PrintDebug(caller, "Final request result: %i - Error Code : %i", success, errorCode);
	
	if (success)
	{
		timeSinceLastLogin = 0;
		KillTimer(hTimeIncreaser);
		hTimeIncreaser = CreateTimer(TIMER_UPDATE_TIME*60.0, timeIncreaser, INVALID_HANDLE, TIMER_REPEAT);
	}
	// In case there was an error before the last request was executed, they are freed.
	else if (errorCode > 0 && errorCode <= 0x0A)
	{
		if (finalRequest != INVALID_HANDLE) CloseHandle(finalRequest);
		finalRequest = INVALID_HANDLE;
		finalFunction = INVALID_FUNCTION;
	}
	if (callbackFunction != INVALID_FUNCTION)
	{
		PrintDebug(caller, "Calling callback...");
		// Start function call
		Call_StartForward(callbackHandle);
		// Push parameters one at a time
		Call_PushCell(client); // Client
		Call_PushCell(success); // Success
		Call_PushCell(errorCode); // Error code
		Call_PushCell(data); // Extra data, in this case nothing
		// Finish the call
		new result = Call_Finish();
		PrintDebug(caller, "Callback calling error code: %i (0: Success)", result);
		
		removeCallback();
	}
	caller = 0;
}

removeCallback()
{
	new bool:removed = RemoveFromForward(callbackHandle, callbackPlugin, callbackFunction);
	new functionCount = GetForwardFunctionCount(callbackHandle);
	PrintDebug(caller, "Removing callback from forward - Result: %i, - Forward Function Count: %i", removed, functionCount);
	callbackFunction = INVALID_FUNCTION;
}

// ===================================================================================
// ===================================================================================

// Obtains the plugin index in a plugin iterator
GetPluginIteratorNumber(Handle:plugin)
{
	new pluginNumber = 0;
	decl String:pluginName[256];
	decl String:auxPluginName[256];
	GetPluginFilename(plugin, pluginName, sizeof(pluginName));
	new Handle:pluginIterator = GetPluginIterator();
	while (MorePlugins(pluginIterator))
	{
		pluginNumber++;
		GetPluginFilename(ReadPlugin(pluginIterator), auxPluginName, sizeof(auxPluginName));
		if (StrEqual(pluginName, auxPluginName)) break;
	}
	CloseHandle(pluginIterator);
	pluginIterator = INVALID_HANDLE;
	
	return pluginNumber;
}

Handle:FindPluginFromNumber(pluginNumber)
{
	new Handle:pluginIterator = GetPluginIterator();
	new Handle:plugin;
	for (new i = 0; i < pluginNumber; i++)
	{
		if (!MorePlugins(pluginIterator))
		{
			plugin = INVALID_HANDLE;
			break;
		}
		plugin = ReadPlugin(pluginIterator);
	}
	CloseHandle(pluginIterator);
	pluginIterator = INVALID_HANDLE;
	
	return plugin;
}

// ===================================================================================
// ===================================================================================

PrintDebug(client, const String:format[], any:...)
{
	if (DEBUG)
	{
		decl String:text[1024];
		VFormat(text, sizeof(text), format, 3);
		if (client == 0) PrintToServer(text);
		else if (IsClientInGame(client)) PrintToConsole(client, text);
	}
}

stock GetCaller()
{
	return caller;
}









