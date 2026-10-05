#!/usr/bin/env python3
"""Optional game directory. Run behind HTTPS; no original game data needed."""
import argparse
import ipaddress
import json
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


class Directory:
    def __init__(self, ttl=65, clock=time.monotonic):
        self.ttl, self.clock = ttl, clock
        self.records = {}
        self.lock = threading.Lock()

    def prune(self):
        now = self.clock()
        self.records = {k: v for k, v in self.records.items() if v['expires'] > now}

    def list(self):
        with self.lock:
            self.prune()
            return {'version': 1, 'games': [v['game'] for v in self.records.values()]}

    def publish(self, data, ip):
        if not isinstance(data, dict):
            raise ValueError('expected an object')
        game = {}
        for key, limit in [('name', 24), ('base', 16), ('quest', 32)]:
            value = data.get(key, '')
            if not isinstance(value, str) or any(ord(c) < 32 for c in value):
                raise ValueError('invalid ' + key)
            game[key] = value[:limit]
        for key, lo, hi in [('port', 1, 65535), ('players', 1, 6), ('max', 1, 6), ('protocol', 1, 65535)]:
            value = data.get(key)
            if type(value) is not int or not lo <= value <= hi:
                raise ValueError('invalid ' + key)
            game[key] = value
        if game['players'] > game['max'] or data.get('mode') not in ['coop', 'lmp']:
            raise ValueError('invalid game')
        game.update(mode=data['mode'], pw=bool(data.get('pw')), in_game=bool(data.get('in_game')))
        address = data.get('address', '')
        if not isinstance(address, str) or len(address) > 256 or any(ord(c) <= 32 for c in address):
            raise ValueError('invalid address')
        if address:
            if '://' in address and not address.startswith(('ws://', 'wss://')):
                raise ValueError('invalid address transport')
            parsed = urlsplit(address if '://' in address else 'enet://' + address)
            if parsed.scheme not in ['enet', 'ws', 'wss'] or not parsed.hostname or parsed.username is not None \
                    or parsed.password is not None or parsed.fragment or parsed.query or (parsed.scheme == 'enet' and parsed.path):
                raise ValueError('invalid address')
            if bool(data.get('ws')) != (parsed.scheme in ['ws', 'wss']):
                raise ValueError('address transport differs from the game')
            if parsed.port is not None and not 1 <= parsed.port <= 65535:
                raise ValueError('invalid address port')
        else:
            host = '[' + ip + ']' if ':' in ip else ip
            address = ('ws://' if data.get('ws') else '') + f'{host}:{game["port"]}'
        game['address'] = address
        with self.lock:
            self.prune()
            ident = data.get('id', '')
            if not isinstance(ident, str) or (ident and len(ident) != 32):
                raise ValueError('invalid lease id')
            if ident:
                old = self.records.get(ident)
                if not old or old['ip'] != ip or not secrets.compare_digest(str(data.get('token', '')), old['token']):
                    raise PermissionError('invalid lease')
                token = old['token']
            else:
                if len(self.records) >= 512 or sum(v['ip'] == ip for v in self.records.values()) >= 8:
                    raise OverflowError('directory is full')
                ident, token = secrets.token_hex(16), secrets.token_hex(32)
            self.records[ident] = {'ip': ip, 'token': token, 'game': game, 'expires': self.clock() + self.ttl}
            return {'version': 1, 'id': ident, 'token': token, 'ttl': self.ttl}

    def remove(self, ident, token, ip):
        with self.lock:
            old = self.records.get(ident)
            if old and (old['ip'] != ip or not secrets.compare_digest(token, old['token'])):
                raise PermissionError('invalid lease')
            self.records.pop(ident, None)


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def setup(self):
        super().setup()
        self.connection.settimeout(10)

    def reply(self, code, data):
        body = json.dumps(data, ensure_ascii=True, separators=(',', ':')).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET,POST,DELETE,OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type,Authorization')
        self.end_headers()
        self.wfile.write(body)

    def remote_ip(self):
        ip = self.client_address[0]
        if ip in self.server.trusted_proxies:
            ip = str(ipaddress.ip_address(self.headers.get('X-Forwarded-For', ip).split(',')[0].strip()))
        return ip

    def do_OPTIONS(self):
        self.reply(200, {})

    def do_GET(self):
        if self.path == '/v1/games':
            self.reply(200, self.server.directory.list())
        else:
            self.reply(404, {'error': 'not found'})

    def do_POST(self):
        if self.path != '/v1/games':
            self.reply(404, {'error': 'not found'})
            return
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= 4096:
                self.close_connection = True
                self.reply(413, {'error': 'invalid body size'})
                return
            data = json.loads(self.rfile.read(length))
            self.reply(200, self.server.directory.publish(data, self.remote_ip()))
        except PermissionError:
            self.reply(403, {'error': 'invalid lease'})
        except OverflowError:
            self.reply(503, {'error': 'directory is full'})
        except (ValueError, TypeError):
            self.reply(400, {'error': 'invalid record'})

    def do_DELETE(self):
        ident = self.path.removeprefix('/v1/games/')
        if not self.path.startswith('/v1/games/') or len(ident) != 32:
            self.reply(404, {'error': 'not found'})
            return
        try:
            token = self.headers.get('Authorization', '').removeprefix('Bearer ')
            self.server.directory.remove(ident, token, self.remote_ip())
            self.reply(200, {'removed': True})
        except (PermissionError, ValueError):
            self.reply(403, {'error': 'invalid lease'})


def make_server(host, port, ttl=65, trusted_proxies=()):
    server = ThreadingHTTPServer((host, port), Handler)
    server.daemon_threads = True
    server.directory = Directory(ttl)
    server.trusted_proxies = set(trusted_proxies)
    return server


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bind', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=28004)
    parser.add_argument('--ttl', type=int, default=65)
    parser.add_argument('--trusted-proxy', action='append', default=[])
    args = parser.parse_args()
    if not 5 <= args.ttl <= 300:
        parser.error('--ttl must be between 5 and 300 seconds')
    server = make_server(args.bind, args.port, args.ttl, args.trusted_proxy)
    print(f'Game directory on {args.bind}:{server.server_port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
