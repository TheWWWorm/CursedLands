# Internet games

The Multiplayer screen's **Internet games** button opens a community game directory.
Enter its URL, refresh, select a game and choose **Use address**. The usual Join screen
handles the password, hero and connection. Desktop and Android can join ENet or
WebSocket games; browser players need a secure `wss://` address (or localhost for testing).

There is no built-in public directory. No directory is contacted until a player enters
its URL and refreshes, or opts into publishing a hosted game. This is a remake addition;
it does not connect to the original game's defunct Nival master server.

To publish, open **Internet games** from a host page and turn **List my hosted game
publicly** on. An empty public join address uses the IP seen by the directory and the
game's port. For a WebSocket reverse proxy, enter its `wss://` game address. Port
forwarding is still needed for a host behind a router. Turning listing off withdraws
the entry; a crashed or closed host expires within 65 seconds by default. Listing
reveals the host address, name, game type, base, quest, player count and whether a
password is required. The password and character data are never sent to the directory.

Settings stay in `user://internet_directory.cfg`. Public listing is off by default and
the directory URL starts empty.

For a direct connection, copy the address labelled **Internet** on the host page.
It appears first when the router supplies a public address, and uses the external
port the router assigned. **LAN / VPN** addresses work on the same local network or
VPN, including ZeroTier; a `192.168.x.x` address cannot connect friends on another
home network. Router forwarding can succeed while its external address is private
or unknown. The host page explains that case instead of labelling it Internet.
Forwarding acknowledgement and directory listing do not test a remote connection.

## Running a directory

The optional server needs Python 3.9 or newer and its standard library only:

```sh
python3 tools/server_directory.py --bind 127.0.0.1 --port 28004
```

For a public community service, place this behind an HTTPS reverse proxy. Forward
`/v1/games` and `/v1/games/<id>` to the service. If the proxy passes `X-Forwarded-For`,
also give the server `--trusted-proxy=127.0.0.1` (use the proxy's actual address).
Forwarded addresses from other clients are ignored. Browser builds require the
directory's HTTPS URL; the server supplies CORS headers for browser lookups.

The server keeps only live registrations in memory. It needs no original game files,
database or account service. Hosts renew a short lease every 20 seconds. Renewing and
removing an entry require its random token and the publishing address. Listings carry
the remake protocol number; incompatible games cannot be chosen. Listing a game does
not verify its reachability.
