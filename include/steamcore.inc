#if defined _steamcore_included
  #endinput
#endif
#define _steamcore_included

/**
 * Callback function called at the end of a request
 * 
 * @param client 	Calling client.
 * @param success	Result of the request.
 * @param errorCode Result error code if error, otherwise 0.
 * @param data		Extra data if any, otherwise 0
 * 
 * @noreturn
 */
functag SteamCoreCallback public(client, bool:success, errorCode, any:data);

/**
 * Creates an announce on a desired steam group. 
 *
 * @param client 	Debug purposes, calling client, use 0 if no client.
 * @param title		Title of the announce.
 * @param body		Body of the announce.
 * @param groupId		Group link id, not complete url.
 * @param func		Callback function to be called at the end of the request.
 * 
 * @noreturn
 */
native steamGroupAnnounce(client, const String:title[], const String:body[],  const String:groupId[], SteamCoreCallback:func);

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