# Discord activity setup

The Windows and Linux desktop game can publish its current mode, campaign
location, Trials round and phase, and elapsed play time to the locally running
Discord desktop client. No Discord login, bot, token, or password is required.
No player names, server addresses, save names, or invitation links are published.
Browser and mobile builds do not publish activity.

An application has not yet been registered for this project. Until an application
ID is configured, the integration stays inactive, including when the option is on.

1. Open the [Discord Developer Portal](https://discord.com/developers/applications)
   and create an application named **Cursed Lands**. The application name is the
   game name Discord displays.
2. Copy its public **Application ID** from General Information. Do not copy a
   token or client secret. No OAuth scopes or bot permissions are needed.
3. Supply it to the game with the `EI_DISCORD_APP_ID` environment variable:

   Linux:
   ```sh
   EI_DISCORD_APP_ID=YOUR_APPLICATION_ID ./CursedLands.x86_64
   ```

   Windows PowerShell:
   ```powershell
   $env:EI_DISCORD_APP_ID = 'YOUR_APPLICATION_ID'
   & '.\CursedLands.exe'
   ```

   Distributors can instead add a `[discord]` section to `game/project.godot`
   with `application_id="YOUR_APPLICATION_ID"` before exporting. The environment
   variable overrides that public default. Never replace published artifacts.
4. Start Discord, enable Discord's activity-sharing preference, and enable
   **Discord activity** in the game's network options. Mode/location changes
   appear within about 15 seconds. No artwork upload is required.
5. Enter a campaign or Trials match and check your Discord profile from another
   account. Leaving the game or switching the option off clears its activity.

The connection uses Discord's local IPC protocol, reconnects when Discord starts
later or restarts, and does not block the game when Discord is unavailable.
Linux Flatpak Discord's `app/com.discordapp.Discord` socket directory is also
searched. Sandboxed Discord must expose its IPC socket to the game.

Protocol references: [Discord RPC](https://docs.discord.com/developers/topics/rpc)
and [Discord's IPC framing documentation](https://github.com/discord/discord-rpc/blob/master/documentation/hard-mode.md).
