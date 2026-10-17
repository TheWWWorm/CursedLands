# Online autochess

Online autochess adds human opponents to the existing nine-seat tournament.
Each player has a separate shop, gold, army and health. Computers fill the
remaining seats and use the same purchasing rules as in solo autochess.

## Host and join

Open **Trials of the Allods → Autochess → Play online**. The connection window
uses the same host/join pages, frames, editable rows, checkmark and back controls
as campaign co-op. It also supports keyboard, controller targets and touch
text entry.

1. Choose **Host autochess**, enter your name and an optional password, then
   select **Start hosting**. The default port is **27016**.
2. Copy an address from the lower panel and give it to the other players.
3. They choose **Join autochess**, paste the address, enter the password if
   needed, and select **Join**. Recently used autochess addresses are retained
   separately from campaign addresses.
4. Joining players select **Ready**. The host selects **Start the game** once
   everyone is ready. Empty seats are labeled **Computer**. Starting alone
   creates a tournament with eight computers.

All participants need this online-autochess build and compatible original game
data. The separate autochess protocol is version **1**; campaign co-op retains
its own protocol. No account or external lobby service is required.

Desktop and Android peers use ENet over UDP by default. The existing automatic
router setup can open the selected UDP port. LAN/VPN addresses work on the same
network; internet hosting needs a reachable address and port. The window reports
router status and provides public, LAN/VPN or IPv6 addresses when available.

WebSocket hosting uses TCP. Desktop and Android clients can join a
`ws://address:27016` host. Browser clients need a reachable secure `wss://` endpoint,
usually an HTTPS reverse proxy in front of the WebSocket port. Browser clients
can join but cannot host. WebSocket hosting uses manual TCP forwarding instead
of automatic UDP router setup. IPv6 literals use `[address]:port`.

## Playing

Preparation lasts **60 seconds**, matching solo autochess. Surviving human
players can start early by selecting **Ready**. Changing the army cancels that
player's ready state. The host handles the shared countdown, bot purchases,
combat and results. Menus, guides and scouting keep the online clock running.
There are no per-player pause or speed controls.

Recruitment, training, reserves, evolution, alliances, creeps, pairings, damage
and income follow the existing tournament rules. Combat shopping is available;
deployed fighters remain locked until the next round. Interest uses each
player's savings at battle start. Shops stay private while armies and standings
can be scouted. All nine boards can be watched in the overview.

An eliminated player can keep watching. A departing guest is replaced by a
computer using the same company. If the host leaves, the game closes for everyone.
This first version has no late joining, reconnection, host migration or online
save/resume. Solo autochess and expedition saves remain separate.

## Implementation and checks

`ArenaOnlineSession` owns an ENet or WebSocket peer independently of campaign
multiplayer. Clients send bounded, sequenced intents. The host associates each
intent with the sender's seat and validates phase, round, arguments, prices,
formation and the selected shop offer. It applies rate limits to actions and
scouting changes. Packets use value serialization without object decoding or RPC.

`ArenaOnlineGame` runs the native boards on a fixed combat tick. Each participant,
including the host, presents an `ArenaOnlineView` and received board snapshots.
Replica worlds do not run authoritative damage or movement. Reliable actor
records and effect events accompany motion snapshots; exact body-part health
keeps the creature inspector consistent with the host.

Relevant fixtures in `tools/tests/`:

- `arena_online.gd`: authority, independent shops, stale/replayed/malformed
  actions, bots, combat shopping, native results, exact health, elimination and
  bot takeover for both transports.
- `arena_online_lobby.gd`: password rejection, all nine seats, full and started
  rooms, readiness, freed seats, disconnects and localized network errors.
- `arena_online_ui.gd`: rendered host/join forms, clipboard controls, readiness,
  game view, scouting, overview, guide and menu in EN/RU/DE.
- `run_arena_online_peers.py`: two independent game processes complete six rounds,
  including PvP rounds four and six, over ENet and WebSocket; final health and
  standings must agree.

Run the independent-process check with an imported source project:

```sh
python3 tools/tests/run_arena_online_peers.py \
  --godot /path/to/godot \
  --data /path/to/owned/Evil-Islands \
  --output /path/to/new-test-output
```

The source game can open the connection window directly with
`--autochess-online` after Godot's `--` separator.
