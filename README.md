#SteamCore

Sourcemod natives that extends the functionality of Pawn to interact with common Steam functions.

This is not an actual plugin, it's a library for other plugins to work and it doesn't interact directly with players in servers.

####Table of Contents 
* [Server Owners](#markdown-header-for-server-owners)
	* [Cvars](#markdown-header-cvars)
		* [Mandatory](#markdown-header-mandatory)
		* [Alternative](#markdown-header-alternative)
	* [Install](#markdown-header-install)
		* [Requirements](#markdown-header-requirements)
	* [Download](#markdown-header-download)
* [Script Writers](#markdown-header-for-scripts-writers)
	* [Natives](#markdown-header-natives)
	* [Error Codes](#markdown-header-error-codes)
	* [Internal Processing of a Request](#markdown-header-internal-processing-of-a-request)
	* [Demo Code](#markdown-header-demo-code)
* [Changelog](#markdown-header-changelog)

##For Server Owners
SteamCore makes use of an account to send requests to Steam server as a normal user would do. Create a new Steam account, **login on a Steam client and deactivate Steam Guard**. 

**You should not use your personal account for this, it could be flagged as a spam bot.**

###Cvars
####Mandatory
* `sc_username` Steam account user.  
* `sc_password` Steam account password.

####Alternative
* `sc_debug` Toggles debug mode _(Default = 0)_.

###Install
####Requirements
* [A working version of Sourcemod](http://www.sourcemod.net/downloads.php).
* [SteamWorks extension](https://forums.alliedmods.net/showthread.php?t=229556).

To install just copy `steamcore.smx` to the `plugins` folder in your Sourcemod directory.

###Download
Compiled version: [steamcore.smx][1]. Available in downloads section.

[1]: https://bitbucket.org/Polvora/steamcore/downloads/steamcore.smx

If you want to compile the code yourself, you must use the offline compiler, and copy `steamcore.sp`, `steamcore/bigint.sp` and `steamcore/rsa.sp` to the scripting folder in your Sourcemod directory, also you need to copy the include file from SteamWorks to scripting/include.

##For Scripts Writers
You must add `steamcore.inc` inside your `include` folder in order to use SteamCore natives.

###Natives
Also available on `steamcore.inc`.
	
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
	 * Returns wheter the plugin is currently busy with a request.
	 *
	 * @return			True is plugin is busy, false otherwise.
	*/
	native bool:IsSteamCoreBusy();
	
	/**
	 * Posts an announcement on a desired Steam group. 
	 *
	 * @param client 	Debug purposes, calling client, use 0 if no client.
	 * @param title		Title of the announce.
	 * @param body		Body of the announce.
	 * @param group		GroupID.
	 * @param func		Callback function to be called at the end of the request.
	 * 
	 * @noreturn
	 */
	native SteamGroupAnnouncement(client, const String:title[], const String:body[],  const String:group[], SteamCoreCallback:func);
	
	/**
	 * Sends a Steam group invitation to an account.
	 *
	 * @param client 	Debug purposes, calling client, use 0 if no client.
	 * @param invitee	SteamID64 of the account to invite.
	 * @param group		GroupID.
	 * @param func		Callback function to be called at the end of the request.
	 *
	 * @noreturn
	 */
	native SteamGroupInvite(client, const String:invitee[], const String:group[], SteamCoreCallback:func);

###Error Codes
Also available on `steamcore.inc`.

	0x00: No error, request successful.
	0x01: Plugin is busy with another task at this time.
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

###Internal Processing of a Request
Natives names and parameters are self-explanatory, but you can first understand the internal processing of a request:

- When a request is made, SteamCore will first check if another request is being executed, if true, the callback function will be _almost automatically_ called (0.1 seconds delay) with `errorCode = 1`. If there is no another request being executed it will continue to the next step.

- Checking the Steam login status, if it's logged out it means a previous attempt to login has failed, a previous request returned a auth error, or 50 minutes have passed since the last login. 

    - If the server is logged in, SteamCore will automatically execute your request.

    - If the server is logged out, SteamCore will first attempt to login and then execute the request.

- Request is executed and callback is called.

    - If the request is successful an `errorCode = 0` will be returned.

    - if the request fails it can be for any reason that will be reflected in the `errorCode`. If the reason is an auth failure, next time a request is made the plugin will try to login before executing the request.

**IMPORTANT NOTES:**

* SteamCore automatically tries to login on map changes.
    * This only happens 10 minutes after the last login has elapsed, this is to prevent Steam login spam on consecutive map changes.

*  **LOGGING IN CAN FREEZE THE SERVER FOR A FRACTION OF A SECOND** (usually < 0.5 seconds) since a long algorithm is executed ([RSA](http://en.wikipedia.org/wiki/RSA_(cryptosystem))) in order to encrypt the login information.

* When retrying a request for a second time, a login attempt will  **always** be executed before the request.

* It's possible that SteamCore fails a request when believing that it's logged in and it is not, this usually happens when an user logs out the Steam account from a web browser, therefore ending any active session on that account.

###Demo Code
A very basic working code:

	#include <steamcore>
	
    new String:groupID = "7376325";
    
    public OnPluginStart()
    {
        RegAdminCmd("sm_announce", cmdAnnounce, ADMFLAG_CONFIG, "");
    }

    public Action:cmdAnnounce(client, args)
    {
        decl String:announcement[256];
        GetCmdArgString(announcement, sizeof(announcement));
        SteamGroupAnnouncement(client, announcement, "\n", groupID, myCallback);
    }
    public myCallback(client, bool:success, errorCode, any:data)
    {
        if (success) PrintToChat(client, "Success!!!");
        else PrintToChat(client, "Failure :(");
    }
	
###Changelog
> [04/02/2015] v1.0 

> * Initial Release.

> [29/03/2015] v1.1

> * Fixed critical bug that made announcements stopped working after a few calls.
> * Added a timeout error code.
> * Added the native isSteamCoreBusy to check if there is a request being executed.
> * Eliminated the retry function in all requests.
> * Changed steamGroupAnnoucement function name to SteamGroupAnnouncement for convention purposes.

> [13/04/2015] v1.2

> * Added the native SteamGroupInvite, sending group invites is only available to non-limited accounts (accounts that have purshased something on the Steam store).

> [03/05/2015] v1.3

> * Added compatibility with most source games, instead of only TF2.
> * SteamTools extension is no longer needed. Instead, SteamWorks is now required.