#if defined _Chat_included
	#endinput
#endif

#define _Chat_included

#define RETRY_CONNECTION_TIME 30.0

new Handle:connectedForward;
new Handle:disconnectedForward;
new Handle:messageSentForward;
new Handle:messageReceivedForward;
new Handle:stateChangeForward;
new Handle:relationshipChangeForward;

new SteamChatMode:chatMode;
new String:chatToken[64];
new String:umqid[32];
new messagelast;

new bool:isConnected = false;
new bool:keepConnected = false;
new bool:isConnecting = false;

AskChatPluginLoad2() 
{
	CreateNative("SteamChatConnect", nativeChatConnect);
	CreateNative("SteamChatDisconnect", nativeChatDisconnect);
	CreateNative("SteamChatIsConnected", nativeIsConnected);
	CreateNative("SteamChatSendMessage", nativeChatSendMessage);
}

OnChatPluginStart() 
{
	connectedForward = CreateGlobalForward("OnChatConnected", ET_Ignore, Param_Cell);
	disconnectedForward = CreateGlobalForward("OnChatDisconnected", ET_Ignore, Param_Cell);
	messageSentForward = CreateGlobalForward("OnChatMessageSent", ET_Ignore, Param_String, Param_String, Param_Cell, Param_Cell);
	messageReceivedForward = CreateGlobalForward("OnChatMessageReceived", ET_Ignore, Param_String, Param_String);
	stateChangeForward = CreateGlobalForward("OnChatFriendStateChange", ET_Ignore, Param_String, Param_String, Param_Cell);
	relationshipChangeForward = CreateGlobalForward("OnChatRelationshipChange", ET_Ignore, Param_String, Param_Cell);
}

Chat_OnSteamLogIn()
{
	if (keepConnected)
	{
		LogDebug("Steam account logged in, retrying connection to chat.");
		chatConnect();
	}
}

public nativeIsConnected(Handle:plugin, numParams)
{
	return _:isConnected;
}

public nativeChatConnect(Handle:plugin, numParams)
{
	chatMode = GetNativeCell(1);
	return _:chatConnect();
}

delayChatConnection()
{
	CreateTimer(RETRY_CONNECTION_TIME, chatConnectTimer);
}

public Action:chatConnectTimer(Handle:timer)
{
	chatConnect();
}

bool:chatConnect()
{
	if (isConnecting) return true;
	keepConnected = true;
	if (isConnected) return true;
	
	if (!IsAccountLogged())
	{
		LogDebug("Account is not logged into Steam, task rejected.");
		SteamLogIn();
		return false;
	}
	
	new String:URL[] = "https://api.steampowered.com/ISteamWebUserPresenceOAuth/Logon/v0001/";
	GetChatToken(chatToken, sizeof chatToken);
	
	LogDebug("Connecting to Steam chat...");
	
	new Handle:request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, URL);
	
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "jsonp", "steamcore"); // Random identifier to be returned in the response
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "access_token", chatToken);
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "ui_mode", chatMode ? "mobile" : "web");
	
	SteamWorks_SetHTTPCallbacks(request, cbkConnect);
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(request, 20);
	SteamWorks_SendHTTPRequest(request);
	
	return true;
}

public cbkConnect(Handle:response, bool:failure, bool:requestSuccessful, EHTTPStatusCode:statusCode)
{
	if (response == INVALID_HANDLE || !requestSuccessful || statusCode != k_EHTTPStatusCode200OK)
	{
		if (statusCode == k_EHTTPStatusCode401Unauthorized)
		{
			if (StrEqual(chatToken, ""))
			{
				LogDebug("Limited account. Only full Steam accounts are allowed to chat.");
				onConnectResult(response, 0x42);
			}
			else
			{
				LogDebug("Unauthorized. Retrying login and reconnecting.");
				SteamLogIn();
				onConnectResult(response, 0x01);
			}
		}
		else if (statusCode == k_EHTTPStatusCodeInvalid)
		{
			if (SteamWorks_IsConnected())
			{
				LogDebug("Request timed out. Retrying. (b%i)(b%i)(i%i)", failure, requestSuccessful, statusCode);
				onConnectResult(response, 0x02);
				if (keepConnected) delayChatConnection();
			}
			else
			{
				LogDebug("Steam servers down. Retrying. (b%i)(b%i)(i%i)", failure, requestSuccessful, statusCode);
				onConnectResult(response, 0x03);
				if (keepConnected) delayChatConnection();
			}
		} 
		else
		{
			LogDebug("Chat message poll request failed (%i)(%i). Status Code: %i", failure, requestSuccessful, statusCode);
			onConnectResult(response, 0x40); // Failed http chat connect request
		}
		return;
	}
	new bodySize;
	SteamWorks_GetHTTPResponseBodySize(response, bodySize);
	new String:responseBody[bodySize];
	SteamWorks_GetHTTPResponseBodyData(response, responseBody, bodySize);
	
	LogDebug("Got response (%i):\n%s", bodySize, responseBody);
	
	if (StrContains(responseBody, "\"error\": \"OK\"") == -1)
	{
		LogDebug("Unexpected request error.")
		onConnectResult(response, 0x41); // Incorrect chat connect response
		return;
	}
	new start = FindCharInString(responseBody, '{');
	new end = FindCharInString(responseBody[start], '}', true) + 2;
	strcopy(responseBody, end, responseBody[start]);
	
	new Handle:json = json_load(responseBody);
	json_object_get_string(json, "umqid", umqid, sizeof umqid);
	messagelast = json_object_get_int(json, "message");
	CloseHandle(json);
	
	LogDebug("Found umqid: %s", umqid);
	LogDebug("Successfuly connected to Steam chat.");
	onConnectResult(response, 0x00);
}

onConnectResult(Handle:response, errorCode)
{
	CloseHandle(response);
	isConnecting = false;
	if (keepConnected)
	{
		Call_StartForward(connectedForward);
		Call_PushCell(errorCode);
		Call_Finish();
		
		if (errorCode == 0x00) 
		{
			isConnected = true;
			pollMessage();
		}
	}
}

public nativeChatDisconnect(Handle:plugin, numParams) 
{
	// new String:URL[] = "https://api.steampowered.com/ISteamWebUserPresenceOAuth/Logoff/v0001/"; // TO-DO
	if (isConnected)
	{
		keepConnected = false;
		return _:true;
	}
	return _:false;
}

onDisconnectResult(errorCode)
{
	isConnected = false;
	Call_StartForward(disconnectedForward);
	Call_PushCell(errorCode);
	Call_Finish();
}

pollMessage()
{
	if (!keepConnected)
	{
		if (isConnected) onDisconnectResult(0x00);
		return;
	}
	
	LogDebug("Requesting message %i from message poll...", messagelast);
	
	new String:URL[] = "https://api.steampowered.com/ISteamWebUserPresenceOAuth/Poll/v0001/";
	new Handle:request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, URL);
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "jsonp", "steamcore"); // Random identifier to be returned in the response
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "access_token", chatToken);
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "umqid", umqid);
	new String:ml[16]; IntToString(messagelast, ml, sizeof ml);
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "message", ml);
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "sectimeout", "30"); // This holds the request for 30 seconds if no new messages
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "useaccounids", "1");
	//SteamWorks_SetHTTPRequestGetOrPostParameter(request, "sectimeout", "10"); // Counter to set away state
	SteamWorks_SetHTTPCallbacks(request, cbkPollMessage);
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(request, 60);
	SteamWorks_SendHTTPRequest(request);
}

public cbkPollMessage(Handle:response, bool:failure, bool:requestSuccessful, EHTTPStatusCode:statusCode)
{
	if (response == INVALID_HANDLE || !requestSuccessful || statusCode != k_EHTTPStatusCode200OK)
	{
		CloseHandle(response);
		if (statusCode == k_EHTTPStatusCode401Unauthorized)
		{
			if (isConnected)
			{
				LogDebug("Unauthorized. Retrying login and reconnecting.");
				SteamLogIn();
				onDisconnectResult(0x01);
			}
		}
		else if (statusCode == k_EHTTPStatusCodeInvalid)
		{
			if (SteamWorks_IsConnected())
			{
				LogDebug("Request timed out. Retrying. (b%i)(b%i)(i%i)", failure, requestSuccessful, statusCode);
				if (isConnected) onDisconnectResult(0x02);
				if (keepConnected) delayChatConnection();
			}
			else
			{
				LogDebug("Steam servers down. Retrying. (b%i)(b%i)(i%i)", failure, requestSuccessful, statusCode);
				if (isConnected) onDisconnectResult(0x03);
				if (keepConnected) delayChatConnection();
			}
		}
		else
		{
			LogDebug("Chat message poll request failed (%i)(%i). Status Code: %i", failure, requestSuccessful, statusCode);
			if (isConnected) onDisconnectResult(0x43); // Disconnected due failed http poll request
		}
		return;
	}
	new bodySize;
	SteamWorks_GetHTTPResponseBodySize(response, bodySize);
	new String:responseBody[bodySize];
	SteamWorks_GetHTTPResponseBodyData(response, responseBody, bodySize);
	
	LogDebug("Got response (%i):\n%s", bodySize, responseBody);
	
	if (StrContains(responseBody, "\"error\": \"Timeout\"") != -1)
	{
		LogDebug("No new messages aquired. Requesting new messages...");
		pollMessage();
	}
	else if (StrContains(responseBody, "\"error\": \"OK\"") != -1)
	{
		LogDebug("Found new messages.");
		
		new start = FindCharInString(responseBody, '{');
		new end = FindCharInString(responseBody[start], '}', true) + 2;
		strcopy(responseBody, end, responseBody[start]);
		
		new Handle:json = json_load(responseBody);
		messagelast = json_object_get_int(json, "messagelast");
		
		new Handle:messages = json_object_get(json, "messages");
		new size = json_array_size(messages);
		new Handle:message;
		new String:type[32];
		new String:text[256];
		new String:persona[64];
		new String:name[64];
		for (new i = 0; i < size; i++)
		{
			message = json_array_get(messages, i);
			json_object_get_string(message, "type", type, sizeof type);
			LogDebug("Found message of type: %s", type);
			if (StrEqual(type, "saytext"))
			{
				json_object_get_string(message, "text", text, sizeof text);
				json_object_get_string(message, "steamid_from", persona, sizeof persona);
				LogDebug("Message from %s (%i): %s", persona, strlen(text), text);
				onMessageReceived(persona, text);
			}
			else if (StrEqual(type, "personastate"))
			{
				json_object_get_string(message, "steamid_from", persona, sizeof persona);
				json_object_get_string(message, "persona_name", name, sizeof name);
				new Handle:hState = json_object_get(message, "persona_state");
				if (hState != INVALID_HANDLE)
				{
					new SteamChatState:state = SteamChatState:json_integer_value(hState);
					CloseHandle(hState);
					LogDebug("State change from %s: state=%i ; name=\"%s\"", persona, state, name);
					onStateChange(persona, name, state);
				}
				
			}
			else if (StrEqual(type, "leftconversation"))
			{
				// TO-DO
			}
			else if (StrEqual(type, "typing"))
			{
				// TO-DO
			}
			else if (StrEqual(type, "personarelationship"))
			{
				json_object_get_string(message, "steamid_from", persona, sizeof persona);
				new Handle:hRelationship = json_object_get(message, "persona_state");
				if (hRelationship != INVALID_HANDLE)
				{
					new SteamChatRelationship:relationship = SteamChatRelationship:json_integer_value(hRelationship);
					CloseHandle(hRelationship);
					LogDebug("Relationship change from %s: relationship=%i", persona, relationship);
					onRelationshipChange(persona, relationship);
				}
			}
			CloseHandle(message);
		}
		
		CloseHandle(messages);
		CloseHandle(json);
		pollMessage();
	}
	else if (StrContains(responseBody, "\"error\": \"Not Logged On\"") != -1)
	{
		LogDebug("Chat disconnected. Retrying connection...");
		if (isConnected) onDisconnectResult(0x44);
		if (keepConnected) delayChatConnection();
	}
	else
	{
		LogDebug("Unknown error. Retrying connection...");
		if (isConnected) onDisconnectResult(0x44); // Just in case some weird error happens
		if (keepConnected) delayChatConnection();
	}
	
	CloseHandle(response);
}

onMessageReceived(const String:friend[], const String:message[])
{
	Call_StartForward(messageReceivedForward);
	Call_PushString(friend);
	Call_PushString(message);
	Call_Finish();
}

onStateChange(const String:friend[], const String:name[], SteamChatState:state)
{
	Call_StartForward(stateChangeForward);
	Call_PushString(friend);
	Call_PushString(name);
	Call_PushCell(state);
	Call_Finish();
}

onRelationshipChange(const String:account[], SteamChatRelationship:relationship)
{
	Call_StartForward(relationshipChangeForward);
	Call_PushString(account);
	Call_PushCell(relationship);
	Call_Finish();
}

public nativeChatSendMessage(Handle:plugin, numParams) 
{
	new String:friend[64];
	new String:message[1024];
	new any:data;
	GetNativeString(1, friend, sizeof(friend));
	GetNativeString(2, message, sizeof(message));
	data = GetNativeCell(3);
	
	if (!isConnected) 
	{
		if (keepConnected) delayChatConnection();
		return false;
	}
	if (!IsAccountLogged())
	{
		LogDebug("Account is not logged into Steam, task rejected.");
		SteamLogIn();
		return false;
	}
	new String:URL[] = "https://api.steampowered.com/ISteamWebUserPresenceOAuth/Message/v0001/";
	
	LogDebug("Sending message (%i) \"%s\" to friend \"%s\"...", strlen(message), message, friend);
	
	new Handle:request = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, URL);
	
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "jsonp", "steamcore"); // Random identifier to be returned in the response
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "access_token", chatToken);
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "umqid", umqid);
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "type", "saytext");
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "steamid_dst", friend);
	SteamWorks_SetHTTPRequestGetOrPostParameter(request, "text", message);
	
	new Handle:container = CreateDataPack();
	WritePackString(container, friend);
	WritePackString(container, message);
	
	SteamWorks_SetHTTPRequestContextValue(request, container, data);
	SteamWorks_SetHTTPCallbacks(request, cbkSendMessage);
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(request, 20);
	SteamWorks_SendHTTPRequest(request);
	return true;
}

public cbkSendMessage(Handle:response, bool:failure, bool:requestSuccessful, EHTTPStatusCode:statusCode, any:container, any:data)
{
	if (response == INVALID_HANDLE || !requestSuccessful || statusCode != k_EHTTPStatusCode200OK)
	{
		if (statusCode == k_EHTTPStatusCode401Unauthorized)
		{
			if (isConnected) 
			{
				LogDebug("Unauthorized. Retrying login and reconnecting.");
				SteamLogIn();
			}
			onSendMessageResult(response, Handle:container, 0x01, data);
		}
		else if (statusCode == k_EHTTPStatusCodeInvalid)
		{
			if (SteamWorks_IsConnected())
			{
				LogDebug("Request timed out. Retrying. (b%i)(b%i)(i%i)", failure, requestSuccessful, statusCode);
				onSendMessageResult(response, Handle:container, 0x02, data);
				if (keepConnected) delayChatConnection();
			}
			else
			{
				LogDebug("Steam servers down. Retrying. (b%i)(b%i)(i%i)", failure, requestSuccessful, statusCode);
				onSendMessageResult(response, Handle:container, 0x03, data);
				if (keepConnected) delayChatConnection();
			}
		}
		else
		{
			LogDebug("Chat message poll request failed (%i)(%i). Status Code: %i", failure, requestSuccessful, statusCode);
			onSendMessageResult(response, Handle:container, 0x45, data); // Failed http chat connect request
		}
		return;
	}
	new bodySize;
	SteamWorks_GetHTTPResponseBodySize(response, bodySize);
	new String:responseBody[bodySize];
	SteamWorks_GetHTTPResponseBodyData(response, responseBody, bodySize);
	
	LogDebug("Got response (%i):\n%s", bodySize, responseBody);
	
	if (StrContains(responseBody, "\"error\": \"OK\"") != -1)
	{
		LogDebug("Message succesfuly sent.")
		onSendMessageResult(response, Handle:container, 0x00, data);
		return;
	}
	if (StrContains(responseBody, "\"error\": \"Not Logged On\"") != -1)
	{
		LogDebug("Disconnected from chat, attempting reconnect...")
		onSendMessageResult(response, Handle:container, 0x46, data);
		if (keepConnected) delayChatConnection();
		return;
	}
	LogDebug("Unknown error while sending message...");
}

onSendMessageResult(Handle:response, Handle:container, errorCode, any:data)
{
	CloseHandle(response);
	ResetPack(container);
	new String:friend[64]; new String:message[1024];
	ReadPackString(container, friend, sizeof friend);
	ReadPackString(container, message, sizeof message);
	CloseHandle(container);
	
	Call_StartForward(messageSentForward);
	Call_PushString(friend);
	Call_PushString(message);
	Call_PushCell(errorCode);
	Call_PushCell(data);
	Call_Finish();
}
