#pragma dynamic 4194304 // Increases stack space to 4mb, needed for encryption

#include <sourcemod>
#include <regex>

// Core includes
#include "steamcore/bigint.sp"

#define AUTOLOAD_EXTENSIONS
#define REQUIRE_EXTENSIONS
#include <steamtools>

#define PLUGIN_URL ""
#define PLUGIN_VERSION "1.0"
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

new bool:steamToolsLoaded = false;

new Handle:cvarUsername;
new Handle:cvarPassword;
new Handle:cvarDebug;

new String:username[32] = "";
new String:passphrase[32] = "";
new String:sessionToken[32] = "";
new String:sessionCookie[256] = "";
new bool:isLogged = false;
new bool:isBusy = false;
new HTTPRequestHandle:request;

new caller;

new timeSinceLastLogin;
new Handle:hTimeIncreaser;
new bool:firstRunLogin = false;

new Handle:callbackHandle;
new Handle:callbackPlugin;
new Function:callbackFunction;
new HTTPRequestHandle:finalRequest;
new HTTPRequestComplete:finalFunction;

// ===================================================================================
// ===================================================================================

public APLRes:AskPluginLoad2(Handle:plugin, bool:late, String:error[], err_max)
{
	// Native creation
	CreateNative("steamGroupAnnounce", nativeGroupAnnounce);
	
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
	if (firstRunLogin && timeSinceLastLogin > 10 && steamToolsLoaded)
	{
		PrintDebug(0, "\n============================================================================\n");
		PrintDebug(0, "Logging in to keep login alive...");
		startRequest(0, INVALID_HTTP_HANDLE, INVALID_FUNCTION, INVALID_HANDLE, INVALID_FUNCTION); // Starts an empty login request
	}
	firstRunLogin = true;
}

public Steam_FullyLoaded()
{
	steamToolsLoaded = true;
	if (firstRunLogin)
		startRequest(0, INVALID_HTTP_HANDLE, INVALID_FUNCTION, INVALID_HANDLE, INVALID_FUNCTION); // Starts an empty login request
	firstRunLogin = true;
}

// ===================================================================================
// ===================================================================================

public nativeGroupAnnounce(Handle:plugin, numParams)
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
	
	new HTTPRequestHandle:_finalRequest = Steam_CreateHTTPRequest(HTTPMethod_POST, URL);
	Steam_SetHTTPRequestHeaderValue(_finalRequest, "Cookie", sessionCookie);
	Steam_SetHTTPRequestGetOrPostParameter(_finalRequest, "action", "post");
	Steam_SetHTTPRequestGetOrPostParameter(_finalRequest, "sessionID", sessionToken);
	Steam_SetHTTPRequestGetOrPostParameter(_finalRequest, "headline", title);
	Steam_SetHTTPRequestGetOrPostParameter(_finalRequest, "body", body);
	
	startRequest(client, _finalRequest, cbkGroupAnnouncement, plugin, Function:GetNativeCell(5)); // Stars a empty login request
}

// ===================================================================================
// ===================================================================================

startRequest(client, HTTPRequestHandle:_finalRequest, HTTPRequestComplete:_finalFunction, Handle:_callbackPlugin, Function:_callbackFunction)
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
		}
		return;
	}
	isBusy = true;
	
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
			Steam_SendHTTPRequest(finalRequest, finalFunction);
			return;
		}
	}
	GetConVarString(cvarUsername, username, sizeof(username));
	GetConVarString(cvarPassword, passphrase, sizeof(passphrase));
	
	if (StrEqual(username, "") || StrEqual(passphrase, ""))
	{
		PrintDebug(caller, "Invalid login information, check cvars. ABORTED.");
		onRequestResult(caller, false, 0x02); // Invalid login information
		return;
	}
	
	request = Steam_CreateHTTPRequest(HTTPMethod_POST, "http://steamcommunity.com/login/getrsakey/");
	Steam_SetHTTPRequestGetOrPostParameter(request, "username", username);
	Steam_SendHTTPRequest(request, cbkRsaKeyRequest);
	
	PrintDebug(caller, "Obtaining RSA Key from steamcommunity.com/login/getrsakey...");
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

public cbkRsaKeyRequest(HTTPRequestHandle:response, bool:requestSuccessful, HTTPStatusCode:statusCode)
{
	if (response == INVALID_HTTP_HANDLE || !requestSuccessful || statusCode != HTTPStatusCode_OK)
	{
		PrintDebug(caller, "RSA Key request failed (%i). Status Code: %i. ABORTED", requestSuccessful, statusCode);
		onRequestResult(caller, false, 0x03); // Failed http RSA Key request
		return;
	}
	decl String:responseBody[30024];
	Steam_GetHTTPResponseBodyData(response, responseBody, sizeof(responseBody));
	
	if (StrContains(responseBody, "\"success\":true", false) == -1)
	{
		PrintDebug(caller, "Could not get RSA Key, aborting...");
		onRequestResult(caller, false, 0x04); // RSA Key response failed, unknown reason
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
	
	Steam_ReleaseHTTPRequest(request);
	request = INVALID_HTTP_HANDLE;
	
	PrintDebug(caller, "\n============================================================================\n");
	
	PrintDebug(caller, "Logging in to steamcommunity.com/login/dologin/...");
	request = Steam_CreateHTTPRequest(HTTPMethod_GET, "https://steamcommunity.com/login/dologin/");
	Steam_SetHTTPRequestGetOrPostParameter(request, "username", username);
	Steam_SetHTTPRequestGetOrPostParameter(request, "password", encryptedPassword);
	Steam_SetHTTPRequestGetOrPostParameter(request, "rsatimestamp", steamTimestamp);
	Steam_SetHTTPRequestGetOrPostParameter(request, "emailauth", "");
	Steam_SetHTTPRequestGetOrPostParameter(request, "emailsteamid", "");
	Steam_SetHTTPRequestGetOrPostParameter(request, "remember_login", "1");
	Steam_SendHTTPRequest(request, cbkLoginRequest);
}

public cbkLoginRequest(HTTPRequestHandle:response, bool:requestSuccessful, HTTPStatusCode:statusCode)
{
	if (response == INVALID_HTTP_HANDLE || !requestSuccessful || statusCode != HTTPStatusCode_OK)
	{
		PrintDebug(caller, "Login request failed (%i). Status Code: %i. ABORTED", requestSuccessful, statusCode);
		onRequestResult(caller, false, 0x05); // Failed htpps login request
		return;
	}
	decl String:responseBody[1024];
	Steam_GetHTTPResponseBodyData(response, responseBody, sizeof(responseBody));
	
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
		onRequestResult(caller, false, 0x06); // Incorrect login data, required captcha or e-mail confirmation (Steam Guard)
		return;
	}
	
	Steam_GetHTTPResponseHeaderValue(response, "Set-Cookie", sessionCookie, sizeof(sessionCookie));
	PrintDebug(caller, "Success, got response (%i): \n%s", strlen(responseBody), responseBody);
	PrintDebug(caller, "Stored Cookie (%i): \n%s", strlen(sessionCookie), sessionCookie);
	
	Steam_ReleaseHTTPRequest(request);
	request = INVALID_HTTP_HANDLE;
	
	PrintDebug(caller, "\n============================================================================\n");
	
	PrintDebug(caller, "Logging successful, obtaining session token...");
	
	request = Steam_CreateHTTPRequest(HTTPMethod_GET, "http://steamcommunity.com/profiles/RedirectToHome");
	Steam_SetHTTPRequestHeaderValue(request, "Cookie", sessionCookie);

	Steam_SendHTTPRequest(request, cbkTokenRequest);
}

public cbkTokenRequest(HTTPRequestHandle:response, bool:requestSuccessful, HTTPStatusCode:statusCode)
{
	if (response == INVALID_HTTP_HANDLE || !requestSuccessful || statusCode != HTTPStatusCode_OK)
	{
		PrintDebug(caller, "Session Token request failed (%i). Status Code: %i. ABORTED", requestSuccessful, statusCode);
		onRequestResult(caller, false, 0x07); // Failed http token request
		return;
	}
	
	decl String:responseBody[32768];
	Steam_GetHTTPResponseBodyData(response, responseBody, sizeof(responseBody));
	
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
		PrintDebug(caller, "Could not get session token. Got: %s.Incorrect Cookie?", steamId);
		onRequestResult(caller, false, 0x08); // Invalid session token. Incorrect cookie?
		return;
	}
	
	StrCat(sessionCookie, sizeof(sessionCookie), "; sessionid=");
	StrCat(sessionCookie, sizeof(sessionCookie), sessionToken);
	StrCat(sessionCookie, sizeof(sessionCookie), ";");
	
	PrintDebug(caller, "Session token successfully acquired (%i): %s", strlen(sessionToken), sessionToken);
	PrintDebug(caller, "Current session for Steam ID (%i): %s", strlen(steamId), steamId);
	PrintDebug(caller, "Appended session token to cookie, actual cookie (%i): \n%s", strlen(sessionCookie), sessionCookie);
	
	if (finalRequest != INVALID_HTTP_HANDLE)
	{
		PrintDebug(caller, "\n============================================================================\n");
		
		PrintDebug(caller, "Executing final request...");
		Steam_SendHTTPRequest(finalRequest, finalFunction);
		
		PrintDebug(caller, "Calling callback...");
	}
	else 
	{
		PrintDebug(caller, "There is no final request, logged in successfully.");
		onRequestResult(caller, true);
	}
	
	Steam_ReleaseHTTPRequest(request);
	request = INVALID_HTTP_HANDLE;
}

public cbkGroupAnnouncement(HTTPRequestHandle:response, bool:requestSuccessful, HTTPStatusCode:statusCode)
{
	if (response == INVALID_HTTP_HANDLE || !requestSuccessful || statusCode != HTTPStatusCode_OK)
	{
		PrintDebug(caller, "Group announcement request failed (%i). Status Code: %i", requestSuccessful, statusCode);
		onRequestResult(caller, false, 0x10); // Failed http group announcement request
		return;
	}
	
	decl String:cookie[1024];
	Steam_GetHTTPResponseHeaderValue(response, "Set-Cookie", cookie, sizeof(cookie));
	
	decl String:responseBody[65536];
	Steam_GetHTTPResponseBodyData(response, responseBody, sizeof(responseBody));
	
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
	
	Steam_ReleaseHTTPRequest(finalRequest);
	finalRequest = INVALID_HTTP_HANDLE;
	finalFunction = INVALID_FUNCTION;
}

onRequestResult(client, bool:success, errorCode=0, any:data=0)
{
	static bool:isRetry = false;
	isLogged = success;
	
	PrintDebug(caller, "\n============================================================================\n");
	
	PrintDebug(caller, "Final request result: %i - Error Code : %i", success, errorCode);
	
	isBusy = false;
	if (!success && !isRetry)
	{
		isRetry = true;
		PrintDebug(caller, "Request failed, retrying...");
		startRequest(caller, finalRequest, finalFunction, callbackPlugin, callbackFunction);
		return;
	}
	if (success)
	{
		timeSinceLastLogin = 0;
		KillTimer(hTimeIncreaser);
		hTimeIncreaser = CreateTimer(TIMER_UPDATE_TIME*60.0, timeIncreaser, INVALID_HANDLE, TIMER_REPEAT);
	}
	isRetry = false;
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
		new bool:removed = RemoveFromForward(callbackHandle, callbackPlugin, callbackFunction);
		new functionCount = GetForwardFunctionCount(callbackHandle);
		PrintDebug(caller, "Removing callback from forward - Result: %i, - Forward Function Count: %i", removed, functionCount);
		
		callbackFunction = INVALID_FUNCTION;
		callbackPlugin = INVALID_HANDLE;
	}
	caller = 0;
}

// ===================================================================================
// ===================================================================================

rsaEncrypt(const String:hexModulus[], const String:hexExponent[], const String:message[], String:ciphertext[], ctSize)
{
	decl modulus[1024];
	decl exponent[16];
	
	if (!hexString2BigInt(hexModulus, modulus, sizeof(modulus)))
	{
		PrintDebug(caller, "Error encrypting passphrase: Invalid modulus.");
		return;
	}
	
	if (!hexString2BigInt(hexExponent, exponent, sizeof(exponent)))
	{
		PrintDebug(caller, "Error encrypting passphrase: Invalid exponent.");
		return;
	}

	new k = strlen(hexModulus);
	new mSize = k + 1;
	if (ctSize < mSize) 
	{
		PrintDebug(caller, "Error encrypting passphrase: ciphertext size is can't be smaller than modulus size");
		
	}
	decl String:paddedMessage[mSize];
	pkcs1v15Pad(message, k, paddedMessage, mSize);
	PrintDebug(caller, "Padded message with PKCS#1 v1.5 standard (%i): \n%s", strlen(paddedMessage), paddedMessage);
	
	decl numericMessage[mSize];
	hexString2BigInt(paddedMessage, numericMessage, mSize);	
	
	decl encryptedMessage[mSize];
	modpowBigInt(numericMessage, exponent, modulus, 16, encryptedMessage, mSize);
	bigInt2HexString(encryptedMessage, ciphertext, ctSize);
}

pkcs1v15Pad(const String:data[], k, String:message[], maxSize) // Message must be even
{
	new dSize = strlen(data);
	new psSize = k - (dSize*2) - 6; // Padding string Size
	decl String:ps[psSize+1]; // Padding string / 1 more to add the string delimiter
	decl String:ds[(dSize*2)+1]; // Data string
	new i;
	for (i = 0; i < psSize; i++)
	{
		if ((i % 2) == 0) ps[i] = int2HexChar(GetRandomInt(1,15));
		else ps[i] = int2HexChar(GetRandomInt(0,15));
	}
	ps[i] = 0;
	for (i = 0; i < dSize; i++)
	{
		ds[i*2] =  int2HexChar(data[i] / 16); // High nibble 
		ds[i*2+1] = int2HexChar(data[i] % 16); // Low nibble
	}
	ds[i*2] = 0;
	
	Format(message, maxSize, "0002%s00%s", ps, ds);
}

encodeBase64(input[], paddingSize, String:output[], oSize)
{
	static const String:base64Table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
	
	new iSize = getBigIntSize(input);
	if (paddingSize < iSize) return 0;
	new zeros = paddingSize - iSize;
	for (new e = 0; e < zeros; e++) { input[iSize++] = 0; }
	new finalSize = (iSize / 6) * 4;
	if (oSize < finalSize) return 0;
	
	new bitString = 0, u = 0, i;
	for (i = iSize-1; i >= 0; i-=3)
	{
		if (i == 1)
		{
			if (((iSize/3)%2) == 1) bitString = (input[i--] << 8) + (input[i--]);
			else  bitString = (input[i--] << 8) + (input[i--] << 4);
		}
		else if (i == 0)
		{
			if (((iSize/3)%2) == 1) bitString = input[i--] << 8;
			else  bitString = input[i--] << 4;
		}
		else bitString = (input[i] << 8) + (input[i-1] << 4) + (input[i-2]);
		
		output[u++] = base64Table[(bitString & 0b111111_000000)>>6];
		output[u++] = base64Table[bitString & 0b000000_111111];
	}
	
	for (new a = 0; a < (u%4); a++)
	{
		output[u++] = '=';
	}
	output[u++] = 0;
	return u;
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









