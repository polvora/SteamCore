# SteamCore

Sourcemod natives that extends the functionality of Pawn to interact with common Steam functions.

This is not an actual plugin, it's a library for other plugins to work and it doesn't interact directly with players in servers.

## For Server Owners
SteamCore makes use of an account to send requests to Steam server as a normal user would do.Create a new Steam account, login in Steam client and deactivate Steam Guard. 

**You should not use your personal account for this, since it could be banned for "botting".** Well, an account never has been banned for this before, but eventually Steam could do it to stop all these scam bots.

### Cvars
#### Mandatory
* `sc_username` Steam account user.  
* `sc_password` Steam account password.

#### Alternative
* `sc_debug` Toggles debug mode.

### Install
#### Requirements
* [A working version of Sourcemod](http://www.sourcemod.net/downloads.php).
* [SteamTools extension](https://forums.alliedmods.net/showthread.php?t=170630).

Just copy `steamtools.smx` to the `plugins` folder in your Sourcemod directory.

### Download
Compiled version: [steamcore.smx][1]. Also available in downloads section.

[1]: https://bitbucket.org/Polvora/steamcore/downloads/steamcore.smx

If you want to compile the code yourself, you must use the offline compiler, and copy `steamcore.sp` and `steamcore/bigint.sp` to the scripting folder in your Sourcemod directory, also you need to copy the include file from SteamTools to scripting/include.

## For Scripts Writers
You must add `steamcore.inc` inside your `include` folder in order to use SteamCore natives.

### Natives
Also available on `steamcore.inc`.

	/**
	 * Callback function called at the end of a request
	 * 
	 * @param client 	Calling client.
	 * @param success	Result of the request.
	 * @param errorCode	Result error code if error, otherwise 0.
	 * @param data		Extra data if any, otherwise 0
	 * 
	 * @noreturn
	 */
	functag SteamCoreCallback public(client, bool:success, errorCode, any:data);

	/**
	 * Creates an announce on a desired Steam group. 
	 *
	 * @param client 	Debug purposes, calling client, use 0 if no client.
	 * @param title		Title of the announce.
	 * @param body		Body of the announce.
	 * @param groupId	Group link id, not complete URL.
	 * @param func		Callback function to be called at the end of the request.
	 * 
	 * @noreturn
	 */
	native steamGroupAnnounce(client, const String:title[], const String:body[],  const String:groupId[], SteamCoreCallback:func);

### Error Codes
Also available on `steamcore.inc`.

	0x00: No error, request successful.
	0x01: Plugin is busy with another task at this time.
	0x02: Login Error: Invalid login information, it means there are errors in the Cvar Strings.
	0x03: Login Error: Failed http RSA Key request.
	0x04: Login Error: RSA Key response failed, unknown reason, probably server side.
	0x05: Login Error: Failed htpps login request.
	0x06: Login Error: Incorrect login data, required captcha or e-mail confirmation (Steam Guard).
	0x07: Login Error: Failed http token request.
	0x08: Login Error: Invalid session token. Incorrect cookie?.
	0x10: Announcement Error: Failed http group announcement request.
	0x11: Announcement Error: Invalid steam login token.
	0x12: Announcement Error: Form error on request.

### Internal Processing of a Request
Natives names and parameters are self-explanatory, but you must first understand the internal processing of a request:

1. When a request is made, SteamCore will first check if another request is being executed, if true, the callback function will be _almost automatically_ (0.1 seconds delay) called with `errorCode = 1`. If there is no another request being executed it will continue to the next step.

2. Checking the Steam login status, if it's disconnected it means a previous attempt to login has failed or 50 minutes have passed since the last login. 

    2.1 If server is connected, SteamCore will automatically execute your request.

    2.2 If server is disconnected, SteamCore first will attempt to login and then execute the request.

3.1 If the request is successful an `errorCode = 0` will be returned on the callback call.

3.2 If the request fails it will be retried one more time, this means SteamCore tries to execute the request 2 times before calling the callback with an error.

**IMPORTANT NOTES:**

* SteamCore automatically tries to login on map changes.
    * This only happens 10 minutes after the last login has elapsed, this is to prevent Steam login spam on consecutive map changes.

*  **LOGGING IN CAN FREEZE THE SERVER FOR A FRACTION OF A SECOND** (usually < 0.5 seconds) since a long algorithm is executed ([RSA](http://en.wikipedia.org/wiki/RSA_(cryptosystem))) in order to encrypt the login information.

* When retrying a request for a second time, a login attempt will  **always** be executed before the request.

* It's possible that SteamCore _"wastes"_ a request retry when believing that it's logged on Steam and in reality it is not, this usually happens when an user logs out the Steam account from a web browser, therefore ending any active session on that account.

### Demo Code
A very basic working code:

    new String:groupID = "7376325";
    
    public OnPluginStart()
    {
        RegAdminCmd("sm_announce", cmdAnnounce, ADMFLAG_CONFIG, "");
    }

    public Action:cmdAnnounce(client, args)
    {
        decl String:announcement[256];
        GetCmdArgString(announcement, sizeof(announcement));
        steamGroupAnnounce(client, announcement, "\n", groupID, myCallback);
    }
    public myCallback(client, bool:success, errorCode, any:data)
    {
        if (success) PrintToChat(client, "Success!!!");
        else PrintToChat(client, "Failure :(");
    }