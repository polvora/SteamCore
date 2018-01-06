#if defined _Community_included
	#endinput
#endif

#define _Community_included

#define COMMUNITY_TIMEOUT 10

new Handle:announceForward;
new Handle:inviteForward;
new Handle:addFriendForward;
new Handle:removeFriendForward;

AskCommunityPluginLoad2() 
{
	CreateNative("SteamCommunityGroupAnnounce", nativeAnnounce);
	CreateNative("SteamCommunityGroupInvite", nativeInvite);
	CreateNative("SteamCommunityAddFriend", nativeAddFriend);
	CreateNative("SteamCommunityRemoveFriend", nativeRemoveFriend);
}

OnCommunityPluginStart()
{
	announceForward = CreateGlobalForward("OnCommunityGroupAnnounceResult", ET_Ignore, Param_String, Param_String, Param_String, Param_Cell, Param_Cell);
	inviteForward = CreateGlobalForward("OnCommunityGroupInviteResult", ET_Ignore, Param_String, Param_String, Param_Cell, Param_Cell);
	addFriendForward = CreateGlobalForward("OnCommunityAddFriendResult", ET_Ignore, Param_String, Param_Cell, Param_Cell);
	removeFriendForward = CreateGlobalForward("OnCommunityRemoveFriendResult", ET_Ignore, Param_String, Param_Cell, Param_Cell);
}

public nativeAnnounce(Handle:plugin, numParams)
{
	new String:title[256];
	new String:body[1024];
	new String:groupID[64];
	new any:data;
	GetNativeString(1, title, sizeof(title));
	GetNativeString(2, body, sizeof(body));
	GetNativeString(3, groupID, sizeof(groupID));
	data = GetNativeCell(4);
	
	decl String:URL[128];
	Format(URL, sizeof(URL), "http://steamcommunity.com/gid/%s/announcements", groupID);
	
	LogDebug("Preparing request to: \n%s...", URL);
	LogDebug("Title: \n%s", title);
	LogDebug("Body: \n%s", body);
	LogDebug("Verifying login...");
	
	if (!IsAccountLogged())
	{
		LogDebug("Account is not logged into Steam, task rejected.");
		SteamLogIn();
		return _:false;
	}
	else LogDebug("Logged in, executing task....");
	
	new String:sessionCookie[1024];
	new String:sessionId[32];
	GetCookie(sessionCookie, sizeof sessionCookie);
	GetSessionId(sessionId, sizeof sessionId);
	
	new Handle:request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, URL);
	SteamWorks_SetHTTPRequestHeaderValue(request, "Cookie", sessionCookie);
	
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "action", "post");
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "sessionID", sessionId);
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "headline", title);
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "body", body);
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "languages[0][headline]", title);
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "languages[0][body]", body);
	
	new Handle:container = CreateDataPack();
	WritePackString(container, title);
	WritePackString(container, body);
	WritePackString(container, groupID);
	
	SteamWorks_SetHTTPRequestContextValue(request, container, data);
	SteamWorks_SetHTTPCallbacks(request, cbkAnnounce);
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(request, COMMUNITY_TIMEOUT);
	SteamWorks_SendHTTPRequest(request);
	
	return _:true;
}

public cbkAnnounce(Handle:response, bool:failure, bool:requestSuccessful, EHTTPStatusCode:statusCode, any:container, any:data)
{
	if (response == INVALID_HANDLE || !requestSuccessful || statusCode != k_EHTTPStatusCode200OK)
	{
		if (statusCode == k_EHTTPStatusCodeInvalid)
		{
			if (SteamWorks_IsConnected())
			{
				LogDebug("Request timed out. (b%i)(b%i)(i%i)", failure, requestSuccessful, statusCode);
				onAnnounceResult(response, Handle:container, 0x02, data);
			}
			else
			{
				LogDebug("Steam servers down. (b%i)(b%i)(i%i)", failure, requestSuccessful, statusCode);
				onAnnounceResult(response, Handle:container, 0x03, data);
			}
		}
		else
		{
			LogDebug("Group announcement request failed (%i). Status Code: %i", requestSuccessful, statusCode);
			onAnnounceResult(response, Handle:container, 0x10, data); // Failed http group announcement request
		}
		return;
	}
	new cookieSize;
	SteamWorks_GetHTTPResponseHeaderSize(response, "Set-Cookie", cookieSize);
	new String:cookie[cookieSize];
	SteamWorks_GetHTTPResponseHeaderValue(response, "Set-Cookie", cookie, cookieSize);
	
	new bodySize;
	SteamWorks_GetHTTPResponseBodySize(response, bodySize);
	new String:responseBody[bodySize];
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
	
	if (StrEqual(steamLogin, "deleted"))
	{
		LogDebug("Invalid steam login token. Retrying login.");
		SteamLogIn();
		onAnnounceResult(response, Handle:container, 0x01, data); // Invalid steam login token
		return;
	}
	if (StrEqual(title, "Steam Community :: Error"))
	{
		LogDebug("Form error on request.");
		onAnnounceResult(response, Handle:container, 0x12, data); // Form error on request
		return;
	}
	
	onAnnounceResult(response, Handle:container, 0x00, data);
}

onAnnounceResult(Handle:response, Handle:container, errorCode, any:data)
{
	CloseHandle(response);
	
	new String:title[256]; new String:body[1024]; new String:groupID[64];
	ResetPack(container);
	ReadPackString(container, title, sizeof title);
	ReadPackString(container, body, sizeof body);
	ReadPackString(container, groupID, sizeof groupID);
	CloseHandle(container);
	
	Call_StartForward(announceForward);
	Call_PushString(title);
	Call_PushString(body);
	Call_PushString(groupID);
	Call_PushCell(errorCode);
	Call_PushCell(data);
	Call_Finish();
}

public nativeInvite(Handle:plugin, numParams)
{
	new String:invitee[64];
	new String:groupID[64];
	new data;
	GetNativeString(1, invitee, sizeof invitee);
	GetNativeString(2, groupID, sizeof groupID);
	data = GetNativeCell(3);
	
	decl String:URL[] = "http://steamcommunity.com/actions/GroupInvite";
	
	LogDebug("Preparing request to: \n%s...", URL);
	LogDebug("Invitee community ID: \n%s", invitee);
	LogDebug("Group community ID: \n%s", groupID);
	LogDebug("Verifying login...");
	
	if (!IsAccountLogged())
	{
		LogDebug("Account is not logged into Steam, task rejected.");
		SteamLogIn();
		return _:false;
	}
	else LogDebug("Logged in, executing task....");
	
	new String:sessionCookie[1024];
	new String:sessionId[32];
	GetCookie(sessionCookie, sizeof sessionCookie);
	GetSessionId(sessionId, sizeof sessionId);
	
	new Handle:request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, URL);
	
	SteamWorks_SetHTTPRequestHeaderValue(request, "Accept", "*/*");
	SteamWorks_SetHTTPRequestHeaderValue(request, "Accept-Encoding", "gzip, deflate");
	SteamWorks_SetHTTPRequestHeaderValue(request, "User-Agent", "Mozilla/5.0 (Windows NT 6.3; WOW64)");
	SteamWorks_SetHTTPRequestHeaderValue(request, "Cookie", sessionCookie);
	
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "json", "1");
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "type", "groupInvite");
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "sessionID", sessionId);
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "group", groupID);
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "invitee", invitee);
	
	new Handle:container = CreateDataPack();
	WritePackString(container, invitee);
	WritePackString(container, groupID);
	
	SteamWorks_SetHTTPRequestContextValue(request, container, data);
	SteamWorks_SetHTTPCallbacks(request, cbkInvite);
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(request, COMMUNITY_TIMEOUT);
	SteamWorks_SendHTTPRequest(request);
	
	return _:true;
}

public cbkInvite(Handle:response, bool:failure, bool:requestSuccessful, EHTTPStatusCode:statusCode, any:container, any:data)
{
	if (response == INVALID_HANDLE || !requestSuccessful || (statusCode != k_EHTTPStatusCode200OK && statusCode != k_EHTTPStatusCode400BadRequest))
	{
		if (statusCode == k_EHTTPStatusCode401Unauthorized)
		{
			LogDebug("Unauthorized. Retrying login.");
			SteamLogIn();
			onInviteResult(response, Handle:container, 0x01, data); // Logged out
		}
		else if (statusCode == k_EHTTPStatusCodeInvalid)
		{
			if (SteamWorks_IsConnected())
			{
				LogDebug("Request timed out. (b%i)(b%i)(i%i)", failure, requestSuccessful, statusCode);
				onInviteResult(response, Handle:container, 0x02, data);
			}
			else
			{
				LogDebug("Steam servers down. (b%i)(b%i)(i%i)", failure, requestSuccessful, statusCode);
				onInviteResult(response, Handle:container, 0x03, data);
			}
		}
		else
		{
			LogDebug("Group invite request failed (%i). Status Code: %i", requestSuccessful, statusCode);
			onInviteResult(response, Handle:container, 0x20, data); // Failed http
		}
		return;
	}
	new bodySize;
	SteamWorks_GetHTTPResponseBodySize(response, bodySize);
	new String:responseBody[bodySize];
	SteamWorks_GetHTTPResponseBodyData(response, responseBody, bodySize);
	
	new Handle:regex;
	regex = CompileRegex("\"results\": ?\"(.*?)\"", PCRE_DOTALL);
	MatchRegex(regex, responseBody);
	new String:result[48];
	GetRegexSubString(regex, 1, result, sizeof(result));
	CloseHandle(regex);
	regex = INVALID_HANDLE;
	
	if (!StrEqual(result, "OK"))
	{
		regex = CompileRegex("\"strError\": ?\"(.*?)\"", PCRE_DOTALL);
		MatchRegex(regex, responseBody);
		new String:error[2048];
		GetRegexSubString(regex, 1, error, sizeof(error));
		CloseHandle(regex);
		regex = INVALID_HANDLE;
		
		if (StrEqual(error, "The invitation to that player failed. Please try again.\n\nError code: 19"))
		{
			LogDebug("Invite failed. Incorrect invitee id on request or another error.");
			onInviteResult(response, Handle:container, 0x21, data); // Incorrect invitee or another error
		}
		else if (StrEqual(result, "Missing Data"))
		{
			LogDebug("Invite failed. Incorrect group id or missing data on request.");
			onInviteResult(response, Handle:container, 0x22, data); // Incorrect Group ID or missing data.
		}
		else if (StrEqual(result, "Missing or invalid form session key"))
		{
			LogDebug("Invite failed. Plugin is not logged in. Retrying login.");
			SteamLogIn();
			onInviteResult(response, Handle:container, 0x01, data); // Logged out
		}
		else if (StrEqual(error, "You do not have permission to invite to the group specified."))
		{
			LogDebug("Invite failed. Inviter account is not a member of the group or does not have permissions to invite.");
			onInviteResult(response, Handle:container, 0x24, data); // Account does not have permissions to invite.
		}
		else if (StrContains(error, "Your account does not meet the requirements to use this feature.") != -1)
		{
			LogDebug("Invite failed. Account is limited, only full Steam accounts can send group invites.");
			onInviteResult(response, Handle:container, 0x25, data); // Limited account. Only full Steam accounts can send Steam group invites
		}
		else if (StrEqual(error, "This user has already been invited or is currently a member."))
		{
			LogDebug("Invite failed. Invitee has already received an invite or is already on the group.");
			onInviteResult(response, Handle:container, 0x27, data); // Invitee has already received an invite or is already on the group.
		}
		else if (StrEqual(error, "You must be friends with a user before you can invite that user to a group."))
		{
			LogDebug("Invite failed. Invitee is not friends with inviter account.");
			onInviteResult(response, Handle:container, 0x28, data); // Invitee is not a friend.
		}
		else
		{
			LogDebug("Invite failed. Unknown error response received when sending the group invite.");
			SteamWorks_WriteHTTPResponseBodyToFile(response, "unknownsteamcoreinviteresponse.json");
			onInviteResult(response, Handle:container, 0x26, data); // Unknown error
		}
	}
	else
	{
		LogDebug("Group invite sent.");
		onInviteResult(response, Handle:container, 0x00, data); // Success
	}
	LogDebug("Response body (%i):\n %s", strlen(responseBody), responseBody);
}

onInviteResult(Handle:response, Handle:container, errorCode, any:data)
{
	CloseHandle(response);
	
	new String:invitee[64]; new String:groupID[64];
	ResetPack(container);
	ReadPackString(container, invitee, sizeof invitee);
	ReadPackString(container, groupID, sizeof groupID);
	CloseHandle(container);
	
	Call_StartForward(inviteForward);
	Call_PushString(invitee);
	Call_PushString(groupID);
	Call_PushCell(errorCode);
	Call_PushCell(data);
	Call_Finish();
}

public nativeAddFriend(Handle:plugin, numParams)
{
	decl String:friend[64];
	new data
	GetNativeString(1, friend, sizeof friend);
	data = GetNativeCell(2);
	
	decl String:URL[] = "http://steamcommunity.com/actions/AddFriendAjax";
	
	LogDebug("Preparing request to: \n%s...", URL);
	LogDebug("Friend community ID: \n%s", friend);
	LogDebug("Verifying login...");
	
	if (!IsAccountLogged())
	{
		LogDebug("Account is not logged into Steam, task rejected.");
		SteamLogIn();
		return _:false;
	}
	else LogDebug("Logged in, executing task....");
	
	new String:sessionCookie[1024];
	new String:sessionId[32];
	GetCookie(sessionCookie, sizeof sessionCookie);
	GetSessionId(sessionId, sizeof sessionId);
	
	new Handle:request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, URL);
	SteamWorks_SetHTTPRequestHeaderValue(request, "Accept", "*/*");
	SteamWorks_SetHTTPRequestHeaderValue(request, "Accept-Encoding", "gzip, deflate");
	SteamWorks_SetHTTPRequestHeaderValue(request, "User-Agent", "Mozilla/5.0 (Windows NT 6.3; WOW64)");
	SteamWorks_SetHTTPRequestHeaderValue(request, "Cookie", sessionCookie);
	
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "sessionID", sessionId);
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "steamid", friend);
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "accept_invite", "0");
	
	new Handle:container = CreateDataPack();
	WritePackString(container, friend);
	
	SteamWorks_SetHTTPRequestContextValue(request, container, data);
	SteamWorks_SetHTTPCallbacks(request, cbkAddFriend);
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(request, COMMUNITY_TIMEOUT);
	SteamWorks_SendHTTPRequest(request);
	
	return _:true;
}

public cbkAddFriend(Handle:response, bool:failure, bool:requestSuccessful, EHTTPStatusCode:statusCode, any:container, any:data)
{
	if (response == INVALID_HANDLE || !requestSuccessful || (statusCode != k_EHTTPStatusCode200OK && statusCode != k_EHTTPStatusCode400BadRequest))
	{
		if (statusCode == k_EHTTPStatusCodeInvalid)
		{
			if (SteamWorks_IsConnected())
			{
				LogDebug("Request timed out. (b%i)(b%i)(i%i)", failure, requestSuccessful, statusCode);
				onAddFriendResult(response, Handle:container, 0x02, data);
			}
			else
			{
				LogDebug("Steam servers down. (b%i)(b%i)(i%i)", failure, requestSuccessful, statusCode);
				onAddFriendResult(response, Handle:container, 0x03, data);
			}
		}
		else
		{
			LogDebug("Friend add request failed (%i). Status Code: %i", requestSuccessful, statusCode);
			onAddFriendResult(response, Handle:container, 0x30, data); // Failed http group invite request
		}
		return;
	}
	
	new bodySize;
	SteamWorks_GetHTTPResponseBodySize(response, bodySize);
	new String:responseBody[bodySize];
	SteamWorks_GetHTTPResponseBodyData(response, responseBody, bodySize);
	
	LogDebug("Got response (%i): %s", strlen(responseBody), responseBody);
	
	
	new Handle:regex = CompileRegex("\"failed_invites_result\":\\[(.*?)\\]", PCRE_DOTALL);
	MatchRegex(regex, responseBody);
	new String:error[8];
	GetRegexSubString(regex, 1, error, sizeof(error));
	CloseHandle(regex);
	regex = INVALID_HANDLE;
	
	if (StrEqual(error, "41"))
	{
		LogDebug("Added account ignored the friend request.");
		onAddFriendResult(response, Handle:container, 0x31, data); 
		return;
	}
	else if (StrEqual(error, "40"))
	{
		LogDebug("Added account has blocked inviter.");
		onAddFriendResult(response, Handle:container, 0x32, data);
		return;
	}
	else if (StrEqual(error, "24"))
	{
		LogDebug("Steam account is limited. Only full Steam accounts can send friend requests.");
		onAddFriendResult(response, Handle:container, 0x33, data);
		return;
	}
	else if (StrEqual(error, "84"))
	{
		LogDebug("You've been sending too many invitations lately. Please try again in a day or two.");
		onAddFriendResult(response, Handle:container, 0x35, data);
		return;
	}
	else if (StrEqual(error, "25"))
	{
		LogDebug("Your account friends list is full.");
		onAddFriendResult(response, Handle:container, 0x36, data);
		return;
	}
	else if (StrEqual(error, "15"))
	{
		LogDebug("Invited account friends list is full.");
		onAddFriendResult(response, Handle:container, 0x37, data);
		return;
	}
	else if (StrEqual(error, "11"))
	{
		LogDebug("You blocked the account you are trying to invite.");
		onAddFriendResult(response, Handle:container, 0x38, data);
		return;
	}
	else if (StrEqual(responseBody, "false"))
	{
		LogDebug("Add request failed. Plugin is not logged in. Retrying loggin.");
		SteamLogIn();
		onAddFriendResult(response, Handle:container, 0x01, data); // Logged out.
	}
	else
	{
		LogDebug("Friend request sent.");
		onAddFriendResult(response, Handle:container, 0x00, data); // Success
		return;
	}
}

onAddFriendResult(Handle:response, Handle:container, errorCode, any:data)
{
	CloseHandle(response);
	
	new String:friend[64];
	ResetPack(container);
	ReadPackString(container, friend, sizeof friend);
	CloseHandle(container);
	
	Call_StartForward(addFriendForward);
	Call_PushString(friend);
	Call_PushCell(errorCode);
	Call_PushCell(data);
	Call_Finish();
}

public nativeRemoveFriend(Handle:plugin, numParams)
{
	decl String:friend[64];
	new data;
	GetNativeString(1, friend, sizeof friend);
	data = GetNativeCell(2);
	
	decl String:URL[] = "http://steamcommunity.com/actions/RemoveFriendAjax";
	
	LogDebug("Preparing request to: \n%s...", URL);
	LogDebug("Ex-Friend community ID: \n%s", friend);
	LogDebug("Verifying login...");
	
	if (!IsAccountLogged())
	{
		LogDebug("Account is not logged into Steam, task rejected.");
		SteamLogIn();
		return _:false;
	}
	else LogDebug("Logged in, executing task....");
	
	new String:sessionCookie[1024];
	new String:sessionId[32];
	GetCookie(sessionCookie, sizeof sessionCookie);
	GetSessionId(sessionId, sizeof sessionId);
	
	new Handle:request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, URL);
	SteamWorks_SetHTTPRequestHeaderValue(request, "Accept", "*/*");
	SteamWorks_SetHTTPRequestHeaderValue(request, "Accept-Encoding", "gzip, deflate");
	SteamWorks_SetHTTPRequestHeaderValue(request, "User-Agent", "Mozilla/5.0 (Windows NT 6.3; WOW64)");
	SteamWorks_SetHTTPRequestHeaderValue(request, "Cookie", sessionCookie);
	
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "sessionID", sessionId);
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "steamid", friend);
	
	new Handle:container = CreateDataPack();
	WritePackString(container, friend);
	
	SteamWorks_SetHTTPRequestContextValue(request, container, data);
	SteamWorks_SetHTTPCallbacks(request, cbkRemoveFriend);
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(request, COMMUNITY_TIMEOUT);
	SteamWorks_SendHTTPRequest(request);
	
	return _:true;
}

public cbkRemoveFriend(Handle:response, bool:failure, bool:requestSuccessful, EHTTPStatusCode:statusCode, any:container, any:data)
{
	if (response == INVALID_HANDLE || !requestSuccessful || (statusCode != k_EHTTPStatusCode200OK && statusCode != k_EHTTPStatusCode400BadRequest))
	{
		if (statusCode == k_EHTTPStatusCodeInvalid)
		{
			if (SteamWorks_IsConnected())
			{
				LogDebug("Request timed out. (b%i)(b%i)(i%i)", failure, requestSuccessful, statusCode);
				onRemoveFriendResult(response, Handle:container, 0x02, data);
			}
			else
			{
				LogDebug("Steam servers down. (b%i)(b%i)(i%i)", failure, requestSuccessful, statusCode);
				onRemoveFriendResult(response, Handle:container, 0x03, data);
			}
		}
		else
		{
			LogDebug("Friend remove request failed (%i). Status Code: %i", requestSuccessful, statusCode);
			onRemoveFriendResult(response, Handle:container, 0x34, data); // Failed http 
		}
		return;
	}
	
	new bodySize;
	SteamWorks_GetHTTPResponseBodySize(response, bodySize);
	new String:responseBody[bodySize]; // I use new instead of decl because for some reason the null terminator is not being added.
	SteamWorks_GetHTTPResponseBodyData(response, responseBody, bodySize);
	
	LogDebug("Got response (%i): %s", bodySize, responseBody);
	
	if (StrEqual(responseBody, "false"))
	{
		LogDebug("Friend remove request failed. Not logged in. Retrying login.");
		SteamLogIn();
		onRemoveFriendResult(response, Handle:container, 0x01, data); // Logged out http 400
	}
	else
	{
		LogDebug("Friend removed.");
		onRemoveFriendResult(response, Handle:container, 0x00, data); // Success
	}
}

onRemoveFriendResult(Handle:response, Handle:container, errorCode, any:data)
{
	CloseHandle(response);
	
	new String:friend[64];
	ResetPack(container);
	ReadPackString(container, friend, sizeof friend);
	CloseHandle(container);
	
	Call_StartForward(removeFriendForward);
	Call_PushString(friend);
	Call_PushCell(errorCode);
	Call_PushCell(data);
	Call_Finish();
}