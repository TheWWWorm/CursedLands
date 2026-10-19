# Discord activity setup

The Windows and Linux desktop game can publish its current mode, campaign
location, Trials round and phase, and elapsed play time to the locally running
Discord desktop client. No Discord login, bot, token, or password is required.
No player names, server addresses, save names, or invitation links are published.
Browser and mobile builds do not publish activity.

## Players

The application ID **1561645781533069393** is included in the game. Players do
not need a developer account, an environment variable, or any application setup.

1. Run the Discord desktop app with activity sharing enabled.
2. Leave **Discord activity** enabled in the game's network options (the default).
3. Play a campaign or Trials match. The mode and location update within about
   15 seconds. Turning the option off or exiting the game clears the activity.

### Для игроков

ID приложения **1561645781533069393** уже включён в игру. Учётная запись
разработчика, переменные окружения и создание приложения не нужны.

1. Запустите настольный Discord и разрешите в нём показ игровой активности.
2. Оставьте **Активность в Discord** включённой в сетевых настройках игры
   (это значение по умолчанию).
3. Начните кампанию или матч в испытаниях. Режим и локация обновляются примерно
   в течение 15 секунд. Выключение опции или выход из игры скрывает активность.

В Discord не передаются имена игроков, адреса серверов, названия сохранений
или ссылки-приглашения. Для игры не нужны токены, пароли или бот Discord.
Браузерная и мобильная версии не публикуют активность.

### Für Spieler

Die Anwendungs-ID **1561645781533069393** ist bereits im Spiel enthalten.
Ein Entwicklerkonto, Umgebungsvariablen oder eine eigene Anwendung sind nicht nötig.

1. Die Discord-Desktop-App starten und dort die Anzeige der Spielaktivität erlauben.
2. **Discord-Aktivität** in den Netzwerkeinstellungen des Spiels eingeschaltet
   lassen (Standardeinstellung).
3. Eine Kampagne oder Prüfungen-Partie spielen. Modus und Ort werden innerhalb
   von etwa 15 Sekunden aktualisiert. Ausschalten der Option oder Beenden des
   Spiels entfernt die Aktivität.

Spielernamen, Serveradressen, Spielstandnamen und Einladungslinks werden nicht
veröffentlicht. Das Spiel benötigt weder Discord-Token noch Passwort oder Bot.
Browser- und Mobilversionen veröffentlichen keine Aktivität.

## Maintaining the integration

The public application ID is stored under `[discord]` in `game/project.godot`
and is included when exporting the game. The application owner manages its
name and optional artwork in the [Discord Developer Portal](https://discord.com/developers/applications/1561645781533069393/information).
No bot, OAuth permissions, token, or client secret is needed by the game.

`EI_DISCORD_APP_ID` remains an optional developer override for testing another
application. It is not a player installation step. Publish new builds to deliver
changes; keep existing releases immutable.

The connection uses Discord's local IPC protocol, reconnects when Discord starts
later or restarts, and does not block the game when Discord is unavailable.
Linux Flatpak Discord's `app/com.discordapp.Discord` socket directory is also
searched. Sandboxed Discord must expose its IPC socket to the game.

Protocol references: [Discord RPC](https://docs.discord.com/developers/topics/rpc)
and [Discord's IPC framing documentation](https://github.com/discord/discord-rpc/blob/master/documentation/hard-mode.md).
