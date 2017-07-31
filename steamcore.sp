#pragma dynamic 4194304 // Increases stack space to 4mb, needed for encryption

#include <sourcemod>
#include <steamcore>
#include <regex>

// Core includes
#include "steamcore/bigint.sp"
#include "steamcore/rsa.sp"

#define AUTOLOAD_EXTENSIONS
#define REQUIRE_EXTENSIONS
#include <steamworks>

#define PLUGIN_URL ""
#define PLUGIN_VERSION "1.8"
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
new const Float:TIMEOUT_TIME = 10.0;

new Handle:cvarUsername;
new Handle:cvarPassword;
new Handle:cvarLoginOnMapChange;
new Handle:cvarDebug;

new String:username[32] = "";
new String:passphrase[32] = "";
new String:sessionToken[32] = "";
new String:sessionCookie[256] = "";
new String:autoStoreGroup[128] = "";
new bool:isLogged = false;
new bool:isBusy = false;
new bool:autoStore = false;
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

// Lazy Global
new String:groupCheck[128];

// ===================================================================================
// ===================================================================================

public APLRes:AskPluginLoad2(Handle:plugin, bool:late, String:error[], err_max)
{
	// Native creation
	CreateNative("IsSteamCoreBusy", nativeIsSteamCoreBusy);
	CreateNative("SteamGroupAnnouncement", nativeGroupAnnouncement);
	CreateNative("SteamGroupInvite", nativeGroupInvite);
	CreateNative("SteamGroupCheckMembershipFromProfile", nativeCheckMembershipFromProfile);
	CreateNative("SteamGroupCheckMembershipFromStorage", nativeCheckMembershipFromStorage);
	CreateNative("SteamGroupStoreMembersList", nativeStoreMembersList);
	CreateNative("SteamGroupToggleAutomaticMembersListStoring", nativeToggleAutomaticMembersListStoring);
	
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
	CreateConVar("steamcore_version", PLUGIN_VERSION, "SteamCore Version", FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY);
	cvarUsername = CreateConVar("sc_username", "", "Steam login username.", FCVAR_PROTECTED);
	cvarPassword = CreateConVar("sc_password", "", "Steam login password.", FCVAR_PROTECTED);
	cvarLoginOnMapChange = CreateConVar("sc_loginonmapchange", "1", "Toggles automatic login on every map change.", 0, true, 0.0, true, 1.0);
	cvarDebug = CreateConVar("sc_debug", "0", "Toggles debugging.", 0, true, 0.0, true, 1.0);
	
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
	if (timeSinceLastLogin > 10 && (GetConVarBool(cvarLoginOnMapChange) || autoStore))
	{
		PrintDebug(0, "\n============================================================================\n");
		
		if (autoStore)
		{
			PrintDebug(0, "Logging and storing members list...");
			SteamGroupStoreMembersList(0, autoStoreGroup, INVALID_FUNCTION);
		}
		else
		{
			PrintDebug(0, "Logging in to keep login alive...");
			startRequest(0, INVALID_HANDLE, INVALID_FUNCTION, INVALID_HANDLE, INVALID_FUNCTION); // Starts an empty login request
		}
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
	SteamWorks_SetHTTPRequestGetOrPostParameter(_finalRequest, "languages[0][headline]", title);
	SteamWorks_SetHTTPRequestGetOrPostParameter(_finalRequest, "languages[0][body]", body);
	
	return _:startRequest(client, _finalRequest, cbkGroupAnnouncement, plugin, Function:GetNativeCell(5));
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
	
	return _:startRequest(client, _finalRequest, cbkGroupInvite, plugin, Function:GetNativeCell(4));
}

// ===================================================================================
// ===================================================================================

bool:startRequest(client, Handle:_finalRequest, SteamWorksHTTPRequestCompleted:_finalFunction, Handle:_callbackPlugin, Function:_callbackFunction)
{		
	if (isBusy)
	{
		PrintDebug(client, "\n============================================================================\n");
		PrintDebug(client, "Plugin is busy with other task at this time, rejecting request...");
		if (_finalRequest != INVALID_HANDLE) CloseHandle(_finalRequest);
		return false;
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
			SteamWorks_SetHTTPCallbacks(finalRequest, finalFunction);
			SteamWorks_SendHTTPRequest(finalRequest);
			startTimeoutTimer();
			return true;
		}
	}
	GetConVarString(cvarUsername, username, sizeof(username));
	GetConVarString(cvarPassword, passphrase, sizeof(passphrase));
	
	if (StrEqual(username, "") || StrEqual(passphrase, ""))
	{
		PrintDebug(caller, "Invalid login information, check cvars. ABORTED.");
		onRequestResult(caller, false, 0x03); // Invalid login information
		return true;
	}
	
	request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, "http://steamcommunity.com/login/getrsakey/");
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "username", username);
	SteamWorks_SetHTTPCallbacks(request, cbkRsaKeyRequest);
	SteamWorks_SendHTTPRequest(request);
	startTimeoutTimer();
	
	PrintDebug(caller, "Obtaining RSA Key from steamcommunity.com/login/getrsakey...");
	return true;
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
	if (connectionInterrupted) return;
	
	if (response == INVALID_HANDLE || !requestSuccessful || statusCode != k_EHTTPStatusCode200OK)
	{
		PrintDebug(caller, "Group announcement request failed (%i). Status Code: %i", requestSuccessful, statusCode);
		onRequestResult(caller, false, 0x10); // Failed http group announcement request
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
		return;
	}
	if (strcmp(title, "Steam Community :: Error") == 0)
	{
		PrintDebug(caller, "Form error on request.");
		onRequestResult(caller, false, 0x12); // Form error on request
		return;
	}
	
	onRequestResult(caller, true);
}

public cbkGroupInvite(Handle:response, bool:failure, bool:requestSuccessful, EHTTPStatusCode:statusCode)
{
	stopTimeoutTimer();
	if (connectionInterrupted) return;
	
	if (response == INVALID_HANDLE || !requestSuccessful || statusCode != k_EHTTPStatusCode200OK)
	{
		PrintDebug(caller, "Group invite request failed (%i). Status Code: %i", requestSuccessful, statusCode);
		onRequestResult(caller, false, 0x20); // Failed http group invite request
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
		PrintDebug(caller, "Error: ");
		PrintDebug(caller, result);
		
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
}

public cbkGetProfile(Handle:response, bool:failure, bool:requestSuccessful, EHTTPStatusCode:statusCode)
{
	stopTimeoutTimer();
	if (connectionInterrupted) return;
	
	if (response == INVALID_HANDLE || !requestSuccessful || statusCode != k_EHTTPStatusCode200OK)
	{
		PrintDebug(caller, "Membership check request failed (%i). Status Code: %i", requestSuccessful, statusCode);
		onRequestResult(caller, false, 0x30); // Failed http group invite request
		return;
	}
	
	new bodySize;
	SteamWorks_GetHTTPResponseBodySize(response, bodySize);
	decl String:responseBody[bodySize];
	SteamWorks_GetHTTPResponseBodyData(response, responseBody, bodySize);
	
	new Handle:regex;
	regex = CompileRegex("<customURL><!\\[CDATA\\[(.*?)\\]\\]><\\/customURL>", PCRE_DOTALL);
	MatchRegex(regex, responseBody);
	decl String:result[128];
	GetRegexSubString(regex, 1, result, sizeof(result));
	CloseHandle(regex);
	regex = INVALID_HANDLE;
	
	CloseHandle(finalRequest);
	finalRequest = INVALID_HANDLE;
	
	decl String:URL[128];
	Format(URL, sizeof URL, "http://steamcommunity.com/id/%s/?xml=1", result);
	
	PrintDebug(caller, "Found custom URL: %s", URL);
	
	finalRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, URL);
	//SteamWorks_SetHTTPCallbacks(finalRequest, cbkCheckMembership);
	SteamWorks_SendHTTPRequest(finalRequest);
	startTimeoutTimer();
}

public nativeCheckMembershipFromProfile(Handle:plugin, numParams)
{
	decl String:account[64];
	decl String:groupID[64];
	new client = GetNativeCell(1);
	GetNativeString(2, account, sizeof account);
	GetNativeString(3, groupID, sizeof groupID);
	
	strcopy(groupCheck, sizeof groupCheck, groupID);
	
	decl String:URL[64];
	Format(URL, sizeof URL, "http://steamcommunity.com/profiles/%s/?xml=1", account);
	
	PrintDebug(client, "Getting: %s", URL);
	
	new Handle:_finalRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, URL);
	
	return _:startRequest(client, _finalRequest, cbkCheckMembershipFromProfile, plugin, Function:GetNativeCell(4));
}

public cbkCheckMembershipFromProfile(Handle:response, bool:failure, bool:requestSuccessful, EHTTPStatusCode:statusCode)
{
	stopTimeoutTimer();
	if (connectionInterrupted) return;
	
	if (response == INVALID_HANDLE || !requestSuccessful || statusCode != k_EHTTPStatusCode200OK)
	{
		PrintDebug(caller, "Membership check request failed (%i). Status Code: %i", requestSuccessful, statusCode);
		onRequestResult(caller, false, 0x30); // Failed http group invite request
		return;
	}
	
	new bodySize;
	SteamWorks_GetHTTPResponseBodySize(response, bodySize);
	decl String:responseBody[bodySize];
	SteamWorks_GetHTTPResponseBodyData(response, responseBody, bodySize);
	
	decl String:search[64];
	Format(search, sizeof search, "<groupID64>%s</groupID64>", groupCheck);
	
	if (StrContains(responseBody, groupCheck, false) != -1)
	{
		PrintDebug(caller, "Client %s belongs to group %s.", caller, groupCheck);
		onRequestResult(caller, true, 0, true);
	}
	else
	{
		PrintDebug(caller, "Client %s does NOT belong to group %s.", caller, groupCheck);
		onRequestResult(caller, true, 0, false);
	}
}

new Handle:checkMembershipFromStorage_Plugin;
new Function:checkMembershipFromStorage_Function;
new bool:checkMembershipFromStorage_busy;
public nativeCheckMembershipFromStorage(Handle:plugin, numParams)
{
	decl String:account[64];
	decl String:groupID[64];
	new client = GetNativeCell(1);
	GetNativeString(2, account, sizeof account);
	GetNativeString(3, groupID, sizeof groupID);
	
	if (checkMembershipFromStorage_busy)
	{
		plugin = INVALID_HANDLE;
		return _:false;
	}
	
	checkMembershipFromStorage_Plugin = plugin;
	checkMembershipFromStorage_Function = Function:GetNativeCell(4);
	
	decl String:error[256];
	new Handle:db = SQL_Connect("steamcore", true, error, sizeof error);
	if (db == INVALID_HANDLE)
	{
		PrintDebug(client, "Error Connecting to DB: %s", error);
		onRequestResult(client, false, 0x32); 
		return _:true;
	}
	PrintDebug(client, "Checking if member is in database...");
	
	decl String:SELECT[256];
	Format(SELECT, sizeof SELECT, "SELECT 1 FROM `%s` WHERE member = %s", groupID, account);
	SQL_TQuery(db, cbkCheckMembershipFromStorage, SELECT, client);
	
	checkMembershipFromStorage_busy = true;
	return _:true;
}

public cbkCheckMembershipFromStorage(Handle:connection, Handle:query, const String:error[], any:client)
{
	checkMembershipFromStorage_busy = false;
	
	new bool:success;
	new errorCode;
	new bool:isMember;
	if (query == INVALID_HANDLE)
	{
		PrintDebug(client, "Error retrieving members from database: %s", error);
		success = false;
		errorCode = 0x33;
		isMember = false;
	}
	else
	{
		success = true;
		errorCode = 0;
		isMember = bool:SQL_GetRowCount(query);
	}
	PrintDebug(client, "Member %sfound in database.", isMember?"":"NOT ");
	
	if (checkMembershipFromStorage_Plugin != INVALID_HANDLE && checkMembershipFromStorage_Function != INVALID_FUNCTION)
	{
		// Start function call
		Call_StartFunction(checkMembershipFromStorage_Plugin, checkMembershipFromStorage_Function);
		// Push parameters one at a time
		Call_PushCell(client); // Client
		Call_PushCell(success); // Success
		Call_PushCell(errorCode); // Error code
		Call_PushCell(isMember); // Extra data
		// Finish the call
		Call_Finish();
	}
	CloseHandle(connection);
	connection = INVALID_HANDLE;
	CloseHandle(query);
	query = INVALID_HANDLE;
	checkMembershipFromStorage_Plugin = INVALID_HANDLE;
	checkMembershipFromStorage_Function = INVALID_FUNCTION;
}

public nativeStoreMembersList(Handle:plugin, numParams)
{
	decl String:groupID[64];
	new client = GetNativeCell(1);
	GetNativeString(2, groupID, sizeof groupID);
	strcopy(groupCheck, sizeof groupCheck, groupID);
	
	decl String:URL[128];
	Format(URL, sizeof URL, "http://steamcommunity.com/gid/%s/memberslistxml/?xml=1", groupID);
	
	PrintDebug(client, "Requesting: %s", URL);
	
	new Handle:_finalRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, URL);
	
	return _:startRequest(client, _finalRequest, cbkStoreMembersList, plugin, Function:GetNativeCell(3));
}

public cbkStoreMembersList(Handle:response, bool:failure, bool:requestSuccessful, EHTTPStatusCode:statusCode)
{
	stopTimeoutTimer();
	if (connectionInterrupted) return;
	
	if (response == INVALID_HANDLE || !requestSuccessful || statusCode != k_EHTTPStatusCode200OK)
	{
		PrintDebug(caller, "Members List request failed (%i). Status Code: %i", requestSuccessful, statusCode);
		onRequestResult(caller, false, 0x30); // Failed http group invite request
		return;
	}
	
	new bodySize;
	SteamWorks_GetHTTPResponseBodySize(response, bodySize);
	decl String:responseBody[bodySize];
	SteamWorks_GetHTTPResponseBodyData(response, responseBody, bodySize);
	
	decl String:match[128];
	new Handle:regex;
	regex = CompileRegex("<totalPages>(.*?)<\\/totalPages>");
	MatchRegex(regex, responseBody);
	if (!GetRegexSubString(regex, 1, match, sizeof(match)))
	{
		PrintDebug(caller, "Members List indexing failed. Could not parse 'totalPages' from group XML.");
		onRequestResult(caller, false, 0x31);
		return;
	}
	new totalPages = StringToInt(match);
	CloseHandle(regex);
	regex = CompileRegex("<currentPage>(.*?)<\\/currentPage>");
	MatchRegex(regex, responseBody);
	if (!GetRegexSubString(regex, 1, match, sizeof(match)))
	{
		PrintDebug(caller, "Members List indexing failed. Could not parse 'currentPage' from group XML.");
		onRequestResult(caller, false, 0x31);
		return;
	}
	new currentPage = StringToInt(match);
	CloseHandle(regex);
	regex = CompileRegex("<memberCount>(.*?)<\\/memberCount>");
	MatchRegex(regex, responseBody);
	if (!GetRegexSubString(regex, 1, match, sizeof(match)))
	{
		PrintDebug(caller, "Members List indexing failed. Could not parse 'memberCount' from group XML.");
		onRequestResult(caller, false, 0x31);
		return;
	}
	new memberCount = StringToInt(match);
	CloseHandle(regex);
	
	PrintDebug(caller, "Indexing members: Page %i of %i", currentPage, totalPages);
	
	// SQLite allows a max of 500 inertions and group pages display up to 1000 members
	decl String:INSERT1[12000];
	decl String:INSERT2[12000];
	Format(INSERT1, sizeof INSERT1, "INSERT INTO `%s` (`member`) VALUES", groupCheck);
	Format(INSERT2, sizeof INSERT2, "INSERT INTO `%s` (`member`) VALUES", groupCheck);
	
	new a = StrContains(responseBody[0], "<steamID64>");
	new i = a + 11; // Plus the number of chars of the search
	new counter = 0;
	decl String:steamId[32];
	
	while (a != -1)
	{
		a = StrContains(responseBody[i], "<steamID64>");
		strcopy(steamId, 18, responseBody[i]);
		if (counter < 500) 
		{
			if (counter == 0) StrCat(INSERT1, sizeof INSERT1, " (");
			else StrCat(INSERT1, sizeof INSERT1, ", (");
			StrCat(INSERT1, sizeof INSERT1, steamId);
			StrCat(INSERT1, sizeof INSERT1, ")");
		}
		else
		{
			if (counter == 500) StrCat(INSERT2, sizeof INSERT2, " (");
			else StrCat(INSERT2, sizeof INSERT2, ", (");
			StrCat(INSERT2, sizeof INSERT2, steamId);
			StrCat(INSERT2, sizeof INSERT2, ")");
		}
		counter++;
		i += (a + 11);
	}
	StrCat(INSERT1, sizeof INSERT1, ";");
	StrCat(INSERT2, sizeof INSERT2, ";");
	
	PrintDebug(caller, "Storing %i members from a total of %i into database...", counter+(currentPage*1000), memberCount);
	
	if (counter)
	{
		decl String:error[256];
		new Handle:dbConnection = SQL_Connect("steamcore", true, error, sizeof error);
		
		if (dbConnection == INVALID_HANDLE) 
		{
			PrintDebug(caller, "Error Connecting to DB: %s", error);
			onRequestResult(caller, false, 0x32); 
			return;
		}
		
		SQL_LockDatabase(dbConnection);
		if (currentPage == 1)
		{
			decl String:TABLE[128];
			Format(TABLE, sizeof TABLE, "DROP TABLE IF EXISTS `%s`;", groupCheck);
			if (!SQL_FastQuery(dbConnection, TABLE))
			{
				SQL_GetError(dbConnection, error, sizeof error );
				PrintDebug(caller, "Error dropping table from DB: %s.", error);
				CloseHandle(dbConnection);
				dbConnection = INVALID_HANDLE;
				onRequestResult(caller, false, 0x32); 
				return;
			}
			Format(TABLE, sizeof TABLE, "CREATE TABLE `%s` (`member` bigint);", groupCheck);
			if (!SQL_FastQuery(dbConnection, TABLE))
			{
				SQL_GetError(dbConnection, error, sizeof error );
				PrintDebug(caller, "Error creating table in DB: %s.", error);
				CloseHandle(dbConnection);
				dbConnection = INVALID_HANDLE;
				onRequestResult(caller, false, 0x32);
				return;
			}
		}
		if (!SQL_FastQuery(dbConnection, INSERT1))
		{
			SQL_GetError(dbConnection, error, sizeof error);
			PrintDebug(caller, "Error inserting first half of values into DB: %s.", error);
			CloseHandle(dbConnection);
			dbConnection = INVALID_HANDLE;
			onRequestResult(caller, false, 0x32);
			return;
		}
		
		if (counter >= 500 && !SQL_FastQuery(dbConnection, INSERT2))
		{
			SQL_GetError(dbConnection, error, sizeof error);
			PrintDebug(caller, "Error inserting second half of values into DB: %s.", error);
			CloseHandle(dbConnection);
			dbConnection = INVALID_HANDLE;
			onRequestResult(caller, false, 0x32);
			return;
		}
		SQL_UnlockDatabase(dbConnection);
		CloseHandle(dbConnection);
		dbConnection = INVALID_HANDLE;
		PrintDebug(caller, "Success.");
		
		if (totalPages != currentPage)
		{
			CloseHandle(finalRequest);
			finalRequest = INVALID_HANDLE;
			
			decl String:URL[128];
			Format(URL, sizeof URL, "http://steamcommunity.com/gid/%s/memberslistxml/?xml=1&p=%i", groupCheck, currentPage + 1);

			PrintDebug(caller, "Requesting: %s", URL);

			finalRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, URL);
			SteamWorks_SetHTTPCallbacks(finalRequest, finalFunction);
			SteamWorks_SendHTTPRequest(finalRequest); // Recursive call
			return;
		}
		onRequestResult(caller, true);
	}
}

public nativeToggleAutomaticMembersListStoring(Handle:plugin, numParams)
{
	new client = GetNativeCell(1);
	GetNativeString(2, autoStoreGroup, sizeof autoStoreGroup);
	autoStore = bool:GetNativeCell(3);
	
	PrintDebug(client, "Toggling automatic storing of group '%s' to state: %i", autoStoreGroup, autoStore);
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
	// In case there was an error before the last request was executed, those are freed.
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
		Call_PushCell(data); // Extra data
		// Finish the call
		new result = Call_Finish();
		PrintDebug(caller, "Callback calling error code: %i (0: Success)", result);
		
		removeCallback();
	}
	caller = 0;
	CloseHandle(finalRequest);
	finalRequest = INVALID_HANDLE;
	finalFunction = INVALID_FUNCTION;
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









