#if defined _LogIn_included
	#endinput
#endif

#define _LogIn_included

#define LOGIN_TIMEOUT 10
#define LOGIN_FILE_NAME "steamcore_login"

#define RETRY_LOGIN_TIME 60.0

// General login vars
new String:login_username[32] = "";
new String:login_passphrase[32] = "";
new String:login_authcode[32] = "";
new String:login_emailsteamid[32] = "";
new String:login_sessionId[32] = "";
new String:login_sessionCookie[1024] = "";
new String:login_machineCookie[128] = "";
new String:login_chatToken[64] = "";
new Handle:login_request;
new bool:isLogged = false;
new bool:isLogging = false;
new String:loginFilePath[128];
new Handle:loginForward;
new login_lastError = 0x00;

// Auth Code config vars
new ReplySource:sendCodeReplySource;
new sendCodeReplyClient;
new bool:sendCodeFlag = false;
new ReplySource:enterCodeReplySource;
new enterCodeReplyClient;
new bool:enterCodeFlag = false;

Login_GetCookie(String:cookie[], maxlength) { strcopy(cookie, maxlength, login_sessionCookie); }
Login_GetSessionId(String:sessionId[], maxlength) { strcopy(sessionId, maxlength, login_sessionId); }
Login_GetChatToken(String:token[], maxlength) { strcopy(token, maxlength, login_chatToken); }

AskLoginPluginLoad2()
{
	CreateNative("IsSteamAccountLogged", nativeIsAccountLogged);
}

OnLoginPluginStart()
{
	loginForward = CreateGlobalForward("OnSteamAccountLoggedIn", ET_Ignore);
	
	RegAdminCmd("sm_steamcore_last_error", cmdLastError, ADMFLAG_ROOT, "Gets the last login error.");
	RegAdminCmd("sm_steamcore_send_code", cmdSendCode, ADMFLAG_ROOT, "Attempts to send the auth code to mail.");
	RegAdminCmd("sm_steamcore_input_code", cmdInputCode, ADMFLAG_ROOT, "Sets the code needed to login and then attempts to login.");
	
	BuildPath(Path_SM, loginFilePath, sizeof loginFilePath, "configs/%s.cfg", LOGIN_FILE_NAME);
	
	retrieveLoginInfo();
}

public nativeIsAccountLogged(Handle:plugin, numParams)
{
	return _:IsAccountLogged();
}

bool:Login_IsAccountLogged() 
{
	return isLogged;
}


public Action:cmdLastError(client, args)
{
	ReplyToCommand(client, "Last login ended with error code: 0x%02X (0x00 = success).", login_lastError);
	return Plugin_Handled;
}

public Action:cmdSendCode(client, args)
{
	retrieveLoginInfo();
	if (StrEqual(login_username, "") || StrEqual(login_passphrase, ""))
	{
		ReplyToCommand(client, "You must first configure username and password to send the code.");
		return Plugin_Handled;		
	}
	
	if (sendCodeFlag || enterCodeFlag)
	{
		ReplyToCommand(client, "There is another config request at this time, please retry in a few seconds.");
		return Plugin_Handled;		
	}
	ReplyToCommand(client, "Attempting to send an auth code to mail...");
	LogDebug("sm_steamcore_send_code: Attempting to send an auth code to mail...");
	sendCodeReplySource = GetCmdReplySource();
	sendCodeReplyClient = client;
	sendCodeFlag = true;
	
	strcopy(login_authcode, sizeof login_authcode, "");
	SteamLogIn();
	return Plugin_Handled;
}

public Action:cmdInputCode(client, args)
{
	retrieveLoginInfo();
	if (StrEqual(login_username, "") || StrEqual(login_passphrase, ""))
	{
		ReplyToCommand(client, "You must first configure username and password to send the code.");
		return Plugin_Handled;		
	}
	if (sendCodeFlag || enterCodeFlag)
	{
		ReplyToCommand(client, "There is another config request at this time, please retry in a few seconds.");
		return Plugin_Handled;		
	}
	if (GetCmdArgs() != 1)
	{
		ReplyToCommand(client, "Usage: sm_steamcore_input_code \"YOURCODE\"");
		return Plugin_Handled;
	}
	GetCmdArg(1, login_authcode, sizeof login_authcode);
	ReplyToCommand(client, "Attempting to login with code: %s", login_authcode);
	enterCodeReplySource = GetCmdReplySource();
	enterCodeReplyClient = client;
	enterCodeFlag = true;
	
	SteamLogIn();
	return Plugin_Handled;
}

public Action:retryLogin(Handle:timer)
{
	LogDebug("Retrying logging in to Steam community...");
	SteamLogIn();
}

Login_SteamLogIn()
{
	LogDebug("Logging in to Steam community...");
	if (isLogging) return;
	if (!SteamWorks_IsConnected()) return;
	retrieveLoginInfo();
	login_request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, "http://steamcommunity.com/login/getrsakey/");
	SteamWorks_SetHTTPRequestGetOrPostParameter(login_request, "username", login_username);
	SteamWorks_SetHTTPCallbacks(login_request, cbkRsaKeyRequest);
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(login_request, LOGIN_TIMEOUT);
	SteamWorks_SendHTTPRequest(login_request);
	LogDebug("Obtaining RSA Key from steamcommunity.com/login/getrsakey...");
	
	isLogged = false;
	isLogging = true;
}

loginCallback(bool:success, errorCode=0)
{
	CloseHandle(login_request);
	isLogging = false;
	LogDebug("Login request returned with error code: %i (0 = success)", errorCode);
	login_lastError = errorCode;
	
	if (sendCodeFlag) 
	{
		if (success)
		{
			SetCmdReplySource(sendCodeReplySource);
			ReplyToCommand(sendCodeReplyClient, "There was not need to send a code since the account logged in without problems.");
		}
		else if (errorCode == 0x0A)
		{
			if (sendCodeReplySource == SM_REPLY_TO_CONSOLE)
			{
				PrintToConsole(sendCodeReplyClient, "Login auth code sent, check the mail and then use sm_steamcore_input_code \"YOURCODE\".");
			}
			else
			{
				PrintToChat(sendCodeReplyClient, "Login auth code sent, check the mail and then use /steamcore_input_code \"YOURCODE\".");
			}
		}
		else // Other error
		{
			SetCmdReplySource(sendCodeReplySource);
			ReplyToCommand(sendCodeReplyClient, "There was an error 0x%02X trying to log in.", errorCode);
		}
		sendCodeFlag = false;
	}
	if (enterCodeFlag)
	{
		if (success)
		{
			SetCmdReplySource(enterCodeReplySource);
			ReplyToCommand(enterCodeReplyClient, "Successfully connected to Steam.");
		}
		else if (errorCode == 0x0A)
		{
			if (sendCodeReplySource == SM_REPLY_TO_CONSOLE)
			{
				PrintToConsole(sendCodeReplyClient, "The used code expired or was invalid, use sm_steamcore_send_code again to send another code.");
			}
			else
			{
				PrintToChat(sendCodeReplyClient, "The used code expired or was invalid, use /steamcore_send_code again to send another code.");
			}
		}
		else
		{
			SetCmdReplySource(enterCodeReplySource);
			ReplyToCommand(enterCodeReplyClient, "There was an error 0x%02X trying to log in.", errorCode);
		}
		enterCodeFlag = false;
	}
	if (success)
	{
		isLogged = true;
		Call_StartForward(loginForward);
		Call_Finish();
		OnSteamLogIn();
	}
	else if (errorCode == 0x02 || errorCode == 0x03) // Timeout
	{
		CreateTimer(RETRY_LOGIN_TIME, retryLogin);
	}
}

public cbkRsaKeyRequest(Handle:response, bool:failure, bool:requestSuccessful, EHTTPStatusCode:statusCode)
{
	if (response == INVALID_HANDLE || !requestSuccessful || statusCode != k_EHTTPStatusCode200OK)
	{
		if (statusCode == k_EHTTPStatusCodeInvalid)
		{
			if (SteamWorks_IsConnected())
			{
				LogDebug("Request timed out. (b%i)(b%i)(i%i)", failure, requestSuccessful, statusCode);
				loginCallback(false, 0x02);
			}
			else
			{
				LogDebug("Steam servers down. (b%i)(b%i)(i%i)", failure, requestSuccessful, statusCode);
				loginCallback(false, 0x03);
			}
		}
		else
		{
			LogDebug("RSA Key request failed (%i). Status Code: %i. ABORTED", requestSuccessful, statusCode);
			loginCallback(false, 0x04); // Failed http RSA Key request
		}
		return;
	}
	new bodySize;
	SteamWorks_GetHTTPResponseBodySize(login_request, bodySize);
	new String:responseBody[bodySize];
	SteamWorks_GetHTTPResponseBodyData(login_request, responseBody, bodySize);
	LogDebug(responseBody);
	
	if (StrContains(responseBody, "\"success\":true", false) == -1)
	{
		LogDebug("Could not get RSA Key, aborting...");
		loginCallback(false, 0x05); // RSA Key response failed, unknown reason
		return;
	}
	new Handle:regex;
	regex = CompileRegex("\"publickey_mod\":\"(.*?)\"");
	MatchRegex(regex, responseBody);
	decl String:rsaPublicMod[1024];
	GetRegexSubString(regex, 1, rsaPublicMod, sizeof(rsaPublicMod));
	CloseHandle(regex);
	regex = INVALID_HANDLE;
	
	LogDebug("RSA KEY MODULUS (%i): \n%s", strlen(rsaPublicMod), rsaPublicMod);
	
	regex = CompileRegex("\"publickey_exp\":\"(.*?)\"");
	MatchRegex(regex, responseBody);
	decl String:rsaPublicExp[16];
	GetRegexSubString(regex, 1, rsaPublicExp, sizeof(rsaPublicExp));
	CloseHandle(regex);
	regex = INVALID_HANDLE;
	
	LogDebug("RSA KEY EXPONENT (%i): %s", strlen(rsaPublicExp), rsaPublicExp);
	
	regex = CompileRegex("\"timestamp\":\"(.*?)\"");
	MatchRegex(regex, responseBody);
	decl String:steamTimestamp[16];
	GetRegexSubString(regex, 1, steamTimestamp, sizeof(steamTimestamp));
	CloseHandle(regex);
	regex = INVALID_HANDLE;
	
	LogDebug("STEAM TIMESTAMP (%i): %s", strlen(steamTimestamp), steamTimestamp);
	
	LogDebug("Encrypting passphrase ******** with RSA public key...");
	decl String:encryptedPassword[1024];
	rsaEncrypt(rsaPublicMod, rsaPublicExp, login_passphrase, encryptedPassword, sizeof(encryptedPassword));
	LogDebug("Encrypted passphrase with RSA cryptosystem (%i): \n%s", strlen(encryptedPassword), encryptedPassword);
	
	decl numericPassword[1024];
	hexString2BigInt(encryptedPassword, numericPassword, sizeof(numericPassword));
	encodeBase64(numericPassword, strlen(rsaPublicMod),encryptedPassword, sizeof(encryptedPassword));
	LogDebug("Encoded encrypted passphrase with base64 algorithm (%i): \n%s", strlen(encryptedPassword), encryptedPassword);
	
	CloseHandle(login_request);
	login_request = INVALID_HANDLE;
	
	LogDebug("Logging in to steamcommunity.com/login/dologin/...");
	
	login_request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, "https://steamcommunity.com/login/dologin/");
	SteamWorks_SetHTTPRequestHeaderValue(login_request, "Cookie", login_machineCookie);
	SteamWorks_SetHTTPRequestGetOrPostParameter(login_request, "password", encryptedPassword);
	SteamWorks_SetHTTPRequestGetOrPostParameter(login_request, "username", login_username);
	SteamWorks_SetHTTPRequestGetOrPostParameter(login_request, "twofactorcode", "");
	SteamWorks_SetHTTPRequestGetOrPostParameter(login_request, "emailauth", login_authcode);
	SteamWorks_SetHTTPRequestGetOrPostParameter(login_request, "loginfriendlyname", "");
	SteamWorks_SetHTTPRequestGetOrPostParameter(login_request, "captchagid", "");
	SteamWorks_SetHTTPRequestGetOrPostParameter(login_request, "captcha_text", "");
	if (StrEqual(login_authcode, "")) strcopy(login_emailsteamid, sizeof login_emailsteamid, "");
	SteamWorks_SetHTTPRequestGetOrPostParameter(login_request, "emailsteamid", login_emailsteamid);
	SteamWorks_SetHTTPRequestGetOrPostParameter(login_request, "rsatimestamp", steamTimestamp);
	SteamWorks_SetHTTPRequestGetOrPostParameter(login_request, "remember_login", "true");
	SteamWorks_SetHTTPCallbacks(login_request, cbkLoginRequest);
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(login_request, LOGIN_TIMEOUT);
	SteamWorks_SendHTTPRequest(login_request);
}

public cbkLoginRequest(Handle:response, bool:failure, bool:requestSuccessful, EHTTPStatusCode:statusCode)
{
	if (response == INVALID_HANDLE || !requestSuccessful || statusCode != k_EHTTPStatusCode200OK)
	{
		if (statusCode == k_EHTTPStatusCodeInvalid)
		{
			if (SteamWorks_IsConnected())
			{
				LogDebug("Request timed out. (b%i)(b%i)(i%i)", failure, requestSuccessful, statusCode);
				loginCallback(false, 0x02);
			}
			else
			{
				LogDebug("Steam servers down. (b%i)(b%i)(i%i)", failure, requestSuccessful, statusCode);
				loginCallback(false, 0x03);
			}
		}
		else 
		{
			LogDebug("Login request failed (%i). Status Code: %i. ABORTED", requestSuccessful, statusCode);
			loginCallback(false, 0x06); // Failed htpps login request
		}
		return;
	}
	new bodySize;
	SteamWorks_GetHTTPResponseBodySize(login_request, bodySize);
	new String:responseBody[bodySize];
	SteamWorks_GetHTTPResponseBodyData(login_request, responseBody, bodySize);
	
	new Handle:regex;
	regex = CompileRegex("\"emailauth_needed\":(.*?),");
	MatchRegex(regex, responseBody);
	new String:needsEmailAuth[20];
	GetRegexSubString(regex, 1, needsEmailAuth, sizeof(needsEmailAuth));
	CloseHandle(regex);
	regex = INVALID_HANDLE;
	
	if (StrEqual(needsEmailAuth, "true"))
	{
		regex = CompileRegex("\"emailsteamid\":\"(.*?)\"");
		MatchRegex(regex, responseBody);
		GetRegexSubString(regex, 1, login_emailsteamid, sizeof login_emailsteamid); // Stored to be used on the next login call
		CloseHandle(regex);
		regex = INVALID_HANDLE;
		
		LogDebug("Aborted logging, needs emailauth (%i): \n%s", bodySize, responseBody);
		loginCallback(false, 0x0A); // Requires e-mail confirmation.
		return;
	}
	
	regex = CompileRegex("\"success\":(.*?),");
	MatchRegex(regex, responseBody);
	new String:successString[20];
	GetRegexSubString(regex, 1, successString, sizeof successString);
	CloseHandle(regex);
	regex = INVALID_HANDLE;
	
	if (!StrEqual(successString, "true"))
	{
		if (StrContains(responseBody, "\"message\":\"The account name or password that you have entered is incorrect.\"") != -1)
		{
			LogDebug("Aborted logging, incorrect login, data body (%i): \n%s", strlen(responseBody), responseBody);
			loginCallback(false, 0x07); // Incorrect login data
			return;
		}
		else
		{
			LogDebug("Aborted logging, requires captcha, data body (%i): \n%s", strlen(responseBody), responseBody);
			loginCallback(false, 0x0C); // Requires captcha
			return;
		}
	}
	
	SteamWorks_GetHTTPResponseHeaderValue(login_request, "Set-Cookie", login_sessionCookie, sizeof login_sessionCookie);
	
	if (StrContains(login_sessionCookie, "steamRememberLogin", false) == -1)
	{
		LogDebug("Session token doesn't contain remember login cookie, only steam guard enabled accounts allowed.");
		loginCallback(false, 0x0B);
		return;
	}
	
	LogDebug("Success, got response (%i): \n%s", strlen(responseBody), responseBody);
	LogDebug("Stored dirty cookie (%i): \n%s", strlen(login_sessionCookie), login_sessionCookie);
	
	CloseHandle(login_request);
	login_request = INVALID_HANDLE;
	
	// Cleaning cookie
	ReplaceString(login_sessionCookie, sizeof login_sessionCookie, "path=/,", "", false);
	ReplaceString(login_sessionCookie, sizeof login_sessionCookie, "path=/; httponly,", "", false);
	ReplaceString(login_sessionCookie, sizeof login_sessionCookie, "path=/; secure; httponly", "", false);
	
	LogDebug("Logging successful, obtaining session token from steamcommunity.com/chat...");
	
	login_request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, "https://steamcommunity.com/chat");
	SteamWorks_SetHTTPRequestHeaderValue(login_request, "Cookie", login_sessionCookie);
	SteamWorks_SetHTTPCallbacks(login_request, cbkTokenRequest);
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(login_request, LOGIN_TIMEOUT);
	SteamWorks_SendHTTPRequest(login_request);
}

public cbkTokenRequest(Handle:response, bool:failure, bool:requestSuccessful, EHTTPStatusCode:statusCode)
{
	if (response == INVALID_HANDLE || !requestSuccessful || statusCode != k_EHTTPStatusCode200OK)
	{
		if (statusCode == k_EHTTPStatusCodeInvalid)
		{
			if (SteamWorks_IsConnected())
			{
				LogDebug("Request timed out. (b%i)(b%i)(i%i)", failure, requestSuccessful, statusCode);
				loginCallback(false, 0x02);
			}
			else
			{
				LogDebug("Steam servers down. (b%i)(b%i)(i%i)", failure, requestSuccessful, statusCode);
				loginCallback(false, 0x03);
			}
		}
		else
		{
			LogDebug("Session Token request failed (%i). Status Code: %i. ABORTED", requestSuccessful, statusCode);
			loginCallback(false, 0x08); // Failed http token request
		}
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
	GetRegexSubString(regex, 1, login_sessionId, sizeof(login_sessionId));
	CloseHandle(regex);
	regex = INVALID_HANDLE;
	
	regex = CompileRegex("'https://api.steampowered.com/', \"(.*?)\"");
	MatchRegex(regex, responseBody);
	GetRegexSubString(regex, 1, login_chatToken, sizeof login_chatToken);
	CloseHandle(regex);
	regex = INVALID_HANDLE;
	
	regex = CompileRegex("steamMachineAuth(.*?);");
	MatchRegex(regex, login_sessionCookie);
	GetRegexSubString(regex, 0, login_machineCookie, sizeof(login_machineCookie));
	CloseHandle(regex);
	regex = INVALID_HANDLE;
	
	storeMachineCookie();
	
	if (strcmp(steamId, "false") == 0) // steamId == false
	{
		LogDebug("Could not get session token. Got: \"%s\". Incorrect Cookie?", steamId);
		loginCallback(false, 0x09); // Invalid session token. Incorrect cookie?
		return;
	}
	
	Format(login_sessionCookie, sizeof login_sessionCookie, "Steam_Language=english; sessionid=%s; %s", login_sessionId, login_sessionCookie);
	
	LogDebug("Session token successfully acquired (%i): %s", strlen(login_sessionId), login_sessionId);
	LogDebug("Chat token successfully acquired (%i): %s", strlen(login_chatToken), login_chatToken);
	LogDebug("Machine cookie successfully acquired (%i): %s", strlen(login_machineCookie), login_machineCookie);
	LogDebug("Current session for Steam ID (%i): %s", strlen(steamId), steamId);
	LogDebug("Appended session token to clean cookie, actual cookie (%i): \n%s", strlen(login_sessionCookie), login_sessionCookie);
	
	loginCallback(true);
}

storeMachineCookie()
{
	LogDebug("Storing machine auth in %s...", loginFilePath);
	new Handle:config = CreateKeyValues(LOGIN_FILE_NAME);
	if (!FileToKeyValues(config, loginFilePath)) 
	{
		LogDebug("ERROR: Login file not present.");
		return;
	}
	KvSetString(config, "machinecookie", login_machineCookie);
	if (!KeyValuesToFile(config, loginFilePath)) 
	{
		LogDebug("ERROR: Could not create login file.");
		return;
	}
	LogDebug("Success.");
	CloseHandle(config);
}

retrieveLoginInfo()
{
	LogDebug("Retrieving login info from %s...", loginFilePath);
	new Handle:config = CreateKeyValues(LOGIN_FILE_NAME);
	if (!FileToKeyValues(config, loginFilePath)) 
	{
		LogDebug("ERROR: Login file not present.");
		return;
	}
	KvGetString(config, "username", login_username, sizeof login_username, "");
	KvGetString(config, "password", login_passphrase, sizeof login_passphrase, "");
	KvGetString(config, "machinecookie", login_machineCookie, sizeof login_machineCookie, "");
	
	LogDebug("Found username: \"%s\" and password: \"%s\"", login_username, login_passphrase);
	LogDebug("Found machine cookie: \"%s\"", login_machineCookie);
	CloseHandle(config);
}