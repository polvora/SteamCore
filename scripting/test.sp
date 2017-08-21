#pragma semicolon 1

#include <sourcemod>
#include <steamcore>

#define PLUGIN_NAME "Tester"
#define PLUGIN_AUTHOR "Statik"
#define PLUGIN_DESCRIPTION "TESTS"
#define PLUGIN_VERSION "0.0"
#define PLUGIN_URL "http://example.org"

public Plugin:myinfo = 
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
}

public OnPluginStart()
{
	
	RegConsoleCmd("sm_islogged", cmdIsLogged, "");
	RegConsoleCmd("sm_announce", cmdAnnounce, "");
	RegConsoleCmd("sm_invite", cmdInvite, "");
	RegConsoleCmd("sm_addfriend", cmdAddFriend, "");
	RegConsoleCmd("sm_removefriend", cmdRemoveFriend, "");
	RegConsoleCmd("sm_chatconnect", cmdChatConnect, "");
	RegConsoleCmd("sm_chatdisconnect", cmdChatDisconnect, "");
	RegConsoleCmd("sm_ischatconnected", cmdIsChatConnected, "");
	RegConsoleCmd("sm_sendmessage", cmdSendMessage, "");
}

public Action:cmdIsLogged(client, args)
{
	PrintToServer("IsLogged() RESULT: %i", IsSteamAccountLogged());
}

public Action:cmdAnnounce(client, args)
{
	PrintToServer("SteamCommunityGroupAnnounce() RESULT: %i", SteamCommunityGroupAnnounce("TEST", "CUERPO", "103582791436897733", 123));
}

public Action:cmdInvite(client, args)
{
	PrintToServer("SteamCommunityGroupInvite() RESULT: %i", SteamCommunityGroupInvite("76561198059743463", "103582791436897733", 321));
}

public Action:cmdAddFriend(client, args)
{
	PrintToServer("SteamCommunityAddFriend() RESULT: %i", SteamCommunityAddFriend("76561198059743463", 456));
}

public Action:cmdRemoveFriend(client, args)
{
	PrintToServer("SteamCommunityRemoveFriend() RESULT: %i", SteamCommunityRemoveFriend("76561198059743463", 654));
}

public Action:cmdChatConnect(client, args)
{
	PrintToServer("SteamChatConnect() RESULT: %i", SteamChatConnect());
}

public Action:cmdChatDisconnect(client, args)
{
	PrintToServer("SteamChatDisconnect() RESULT: %i", SteamChatDisconnect());
}

public Action:cmdIsChatConnected(client, args)
{
	PrintToServer("SteamChatIsConnected() RESULT: %i", IsSteamAccountLogged());
}

public Action:cmdSendMessage(client, args)
{
	PrintToServer("SteamChatSendMessage() RESULT: %i", SteamChatSendMessage("76561198059743463", "HELLO4"));
}

public OnCommunityGroupAnnounceResult(const String:title[], const String:body[], const String:group[], errorCode, any:data)
{
	PrintToServer("OnCommunityGroupAnnounceResult() FIRED. RESULT: title=%s ; body=%s ; group=%s ; errorCode=%i ; data=%i", title, body, group, errorCode, data);
}

public OnCommunityGroupInviteResult(const String:invitee[], const String:group[], errorCode, any:data)
{
	PrintToServer("OnCommunityGroupInviteResult() FIRED. RESULT: invitee=%s ; group=%s ; errorCode=%i ; data=%i", invitee, group, errorCode, data);
}

public OnCommunityAddFriendResult(const String:friend[], errorCode, any:data)
{
	PrintToServer("OnCommunityAddFriendResult() FIRED. RESULT: friend=%s ; errorCode=%i ; data=%i", friend, errorCode, data);
}

public OnCommunityRemoveFriendResult(const String:friend[], errorCode, any:data)
{
	PrintToServer("OnCommunityRemoveFriendResult() FIRED. RESULT: friend=%s ; errorCode=%i ; data=%i", friend, errorCode, data);
}

public OnChatConnected(errorCode)
{
	PrintToServer("OnChatConnected() FIRED. RESULT: errorCode=%i", errorCode);
}

public OnChatDisconnected(errorCode)
{
	PrintToServer("OnChatDisconnected() FIRED. RESULT: errorCode=%i", errorCode);
}

public OnSteamAccountLoggedIn()
{
	PrintToServer("OnSteamAccountLoggedIn() FIRED");
}

public OnChatMessageReceived(const String:friend[], const String:message[])
{
	PrintToServer("OnChatMessageReceived() FIRED. RESULT: friend=\"%s\" ; message=\"%s\"", friend, message);
}

public OnChatFriendStateChange(const String:friend[], const String:name[], SteamChatState:state)
{
	PrintToServer("OnChatFriendStateChange() FIRED. RESULT: friend=\"%s\" ; name=\"%s\" ; state=%i", friend, name, state);
}

public OnChatMessageSent(const String:friend[], const String:message[], errorCode)
{
	PrintToServer("OnChatMessageSent() FIRED. RESULT: friend=\"%s\" ; message=\"%s\" ; errorCode=%i", friend, message, errorCode);
}