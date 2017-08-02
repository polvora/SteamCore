#if defined _steamcore_included
  #endinput
#endif
#define _steamcore_included

/*
	Error Codes:
	0x00: No error, request successful.
	0x01: Plugin is busy with another task at this time. (legacy, new versions return inmediatly when busy)
	0x02: Connection timed out.
	
	0x03: Login Error: Invalid login information, it means there are errors in the Cvar Strings.
	0x04: Login Error: Failed http RSA Key request.
	0x05: Login Error: RSA Key response failed, unknown reason, probably server side.
	0x06: Login Error: Failed htpps login request.
	0x07: Login Error: Incorrect login data, required captcha or e-mail confirmation (Steam Guard).
	0x08: Login Error: Failed http token request.
	0x09: Login Error: Invalid session token. Incorrect cookie?.
	
	0x10: Announcement Error: Failed http group announcement request.
	0x11: Announcement Error: Invalid steam login token.
	0x12: Announcement Error: Form error on request.
	
	// Invitee: Who receives the invite.
	0x20: Invite Error: Failed http group invite request.
	0x21: Invite Error: Incorrect invitee or another error.
	0x22: Invite Error: Incorrect Group ID or missing data.
	0x23: Invite Error: Logged out. Retry to login.
	0x24: Invite Error: Inviter account is not a member of the group or does not have permissions to invite.
	0x25: Invite Error: Limited account. Only full Steam accounts can send Steam group invites
	0x26: Invite Error: Unknown error.
	0x27: Invite Error: Invitee has already received an invite or is already on the group.
*/

/**
 * Callback function called at the end of a request
 * 
 * @param client 	Reference client.
 * @param success	Result of the request.
 * @param errorCode Result error code if error, otherwise 0.
 * @param data		Extra data if any, otherwise 0
 * 
 * @noreturn
 */
functag SteamCoreCallback public(client, bool:success, errorCode, any:data);

/**
 * Returns wheter the plugin is currently busy with a request.
 *
 * @return			True is plugin is busy, false otherwise.
*/
native bool:IsSteamCoreBusy();

/**
 * Posts an announcement on a desired Steam group. 
 *
 * @param client 	Reference client, will be returned in callback.
 * @param title		Title of the announce.
 * @param body		Body of the announce.
 * @param group		SteamID64 of the group.
 * @param func		Callback function to be called at the end of the request.
 * 
 * @return			True if it was was executed, false if plugin was busy.
 */
native bool:SteamGroupAnnouncement(client, const String:title[], const String:body[],  const String:group[], SteamCoreCallback:func);

/**
 * Sends a Steam group invitation to an account.
 *
 * @param client 	Reference client, will be returned in callback.
 * @param invitee	SteamID64 of the account to invite.
 * @param group		GroupID.
 * @param func		Callback function to be called at the end of the request.
 *
 * @return			True if it was was executed, false if plugin was busy.
 */
native bool:SteamGroupInvite(client, const String:invitee[], const String:group[], SteamCoreCallback:func);

public SharedPlugin:__pl_steamcore = 
{
	name = "steamcore",
	file = "steamcore.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};