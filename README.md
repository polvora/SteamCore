# SteamCore

_If you see a bug, want to add a new feature or have a question, you should create an issue [here](https://github.com/polvora/SteamCore/issues/new)._

Sourcemod natives that extends the functionality of Pawn to interact with common Steam functions.

This is not an actual plugin, it's a library for other plugins to work and it doesn't interact directly with players in servers.

#### Table of Contents 
* [Server Owners](#server-owners)
	* [Prerequisites](#prerequisites)
	* [Install](#install)
		* [Requirements](#requirements)
		* [Setting Account](#setting-account)
	* [Cvars](#cvars)
	* [Download](#download)
* [Scripts Writers](#scripts-writers)
	* [Error Codes Table](#error-codes-table)
* [Changelog](#changelog)

## Server Owners
### Prerequisites
SteamCore makes use of an account to send requests to Steam server as a normal user would do. To get more of this plugin, it is better to use a full steam account, read [this](https://support.steampowered.com/kb_article.php?ref=3330-IAGK-7663) to check the limitations of a limited account.

The Steam account must have Steam Guard configured to send e-mail codes, so if you don't have it enabled, enable it by choosing _"Get Steam Guard codes by email"_ in [this page](https://store.steampowered.com/twofactor/manage).

**I recommend you not using your personal account for this**

### Install
#### Requirements
* [A working version of Sourcemod](http://www.sourcemod.net/downloads.php).
* [SteamWorks extension](http://users.alliedmods.net/~kyles/builds/SteamWorks/).
* [SMJansson extension](https://github.com/thraaawn/SMJansson/tree/master/bin) (.dll for Windows and .so for Linux)

To install SteamCore unpack the [latest release](https://github.com/polvora/SteamCore/releases/latest) in the Sourcemod directory.

To add the plugins and extensions restart the server.

#### Setting Account
After you have installed SteamCore you need to configure the Steam account's credentials, to do so open `sourcemod/configs/steamcore_login.cfg` and input the accounts credentials in the file, an example would be this:

	"steamcore_login"
	{
		"username"	"testaccountname789"
		"password"	"arandompassword123"
	}
**_Use alphanumeric user/pass, max length: 32 characters_**

Now to login to Steam servers you need join the server as a player and from console or chat (i recommend console) input the next command:

`sm_steamcore_send_code` or from chat `/steamcore_send_code`

This will send a Steam Guard code to the configured e-mail of the account. Copy the code and input the next command with the code:

`sm_steamcore_input_code YOURCODE`

If everything went right, you should have now completed the setup process.

### Cvars
* `sc_debug` Toggles debug mode _(Default = 0)_.

Turning debug mode on will write a lot of data in `/sourcemod/logs/steamcore_debug_DATE.cfg` only enable it if you are having problems othewise it will only put **extra load, huge files and console spam** on your server. If you need to enable it check the errors and then disable it. Never let it on all the time.

### Download
Compiled versions: [steamcore.zip](https://github.com/polvora/SteamCore/releases/latest).

## Scripts Writers
Read the [include file](https://github.com/polvora/SteamCore/blob/master/scripting/include/steamcore.inc).
You only need the SteamCore include file to compile your plugin.

### Error Codes Table
	0x00(00): General: No error, request successful.
	0x01(01): General: Logged out, plugin will attempt to login.
	0x02(02): General: Connection timed out.
	0x03(03): General: Steam servers down.
	
	0x04(04): Login Error: Failed http RSA Key request.
	0x05(05): Login Error: RSA Key response failed, unknown reason, probably server side.
	0x06(06): Login Error: Failed htpps login request.
	0x07(07): Login Error: Incorrect login information.
	0x08(08): Login Error: Failed http token request.
	0x09(09): Login Error: Invalid session token. Incorrect cookie?.
	0x0A(10): Login Error: Requires e-mail confirmation.
	0x0B(11): Login Error: Steam Guard disabled, only accounts with mail confirmation allowed.
	0x0C(12): Login Error: Requires captcha, wait a few minutes then try again.
	
	0x10(16): Announcement Error: Failed http group announcement request.
	0x11(17): Announcement Error: (LEGACY, no longer used)
	0x12(18): Announcement Error: Form error on request or too many consecutive requests.
	
	// Invitee: Who receives the invite.
	0x20(32): Invite Error: Failed http group invite request.
	0x21(33): Invite Error: Incorrect invitee or another error.
	0x22(34): Invite Error: Incorrect Group ID or missing data.
	0x23(35): Invite Error: (LEGACY, no longer used)
	0x24(36): Invite Error: SteamCore account is not a member of the group or does not have permissions to invite.
	0x25(37): Invite Error: Limited account. Only full Steam accounts can send Steam group invites
	0x26(38): Invite Error: Unkown error. Check https://github.com/polvora/SteamCore/issues/6
	0x27(39): Invite Error: Invitee has already received an invite or is already on the group.
	0x28(40): Invite Error: Invitee must be friends with the SteamCore account to receive an invite.
	
	0x30(48): Friend Add Error: Failed http friend request.
	0x31(49): Friend Add Error: Invited account ignored the friend request.
	0x32(50): Friend Add Error: Invited account has blocked the SteamCore account.
	0x32(51): Friend Add Error: SteamCore account is limited. Only full Steam accounts can send friend requests.
	0x34(52): Friend Remove Error: Failed http request.
	
	0x40(64): Chat Connect Error: Failed http chat connect request.
	0x41(65): Chat Connect Error: Incorrect chat connect response.
	0x42(66): Chat Connect Error: Chat not allowed for limited accounts. Only full Steam accounts can use chat.
	0x43(67): Chat Disconnect Error: Failed http poll request.
	0x44(68): Chat Disconnect Error: Message poller timed out, plugin will automatically reconnect.
	0x45(69): Chat Send Message Error: Failed http send message request.
	0x46(70): Chat Send Message Error: Diconnected from chat, plugin will automatically reconnect.

> ### Changelog
> [04/02/2015] v1.0 

> * Initial Release.

> [29/03/2015] v1.1

> * _Announcement Module:_ Fixed critical bug that made announcements stopped working after a few calls.
> * Added a timeout error code.
> * Added the native isSteamCoreBusy to check if there is a request being executed.
> * Eliminated the retry function in all requests.
> * _Announcement Module:_ Changed steamGroupAnnoucement function name to SteamGroupAnnouncement for convention purposes.

> [13/04/2015] v1.2

> * Added the native SteamGroupInvite, sending group invites is only available to non-limited accounts (accounts that have purshased something on the Steam store).

> [03/05/2015] v1.3

> * Added compatibility with most source games, instead of only TF2.
> * **SteamTools extension is no longer needed. Instead, SteamWorks is now required.**

> [08/05/2015] v1.4

> * _Invite Module:_ Permissions errors and Limited account error are now differentiated.
> * _Invite Module:_ Fixed the unknown errors being called as success and added an errorCode for them (0x26).

> [18/05/2015] v1.5

> * **Fixed critical bug that prevented logging in on Steam.**

> [12/06/2015] v1.5.1

> * Increased timeout time for requests to 10 seconds (previously 5 seconds).

> [17/08/2015] v1.6

> * **Fixed critical bug that prevented logging in on Steam.** 

> [02/02/2017] v1.7

> * _Announcement Module:_ **Fixed critical bug caused by outdated method to post announcements.**
> * **Fixed critical bug that crashed the plugin when making a request while plugin is busy.**

> [15/03/2017] v1.7.1

> * Added minor debug text.

> [03/08/2017] v1.8

> * Changed the way developers have to handle busy requests.
> * Solved a bug when a request was made while logging on map change.

> [03/08/2017] v1.9

> * Adds natives to Add/Remove friends.

> [21/08/2017] v2.0

> * Complete restructuring of the code.
> * Debug now logs to file.
> * Now plugin can handle multiple requests at the same time. No more busy requests.
> * Steam account credentials storage is now safer.
> * Steam Guard login is possible and mandatory.
> * Now plugin only needs to login when server restarts. No more random logouts.
> * Added a Steam chat module with 4 new natives to connect/disconnect from chat and send/receive messages.
