"""MONO v1: authenticated, curated authorized-manifest resolver. No scraping or proxying.

Operators populate a catalog only with media they own or are licensed to distribute.
This is a working optional social adapter, not a claim of general TikTok extraction.
TLS terminates at your reverse proxy; never expose this HTTP listener to the Internet.
"""
import hashlib
import hmac
import ipaddress
import json
import os
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, urlunsplit

MAX_BODY = 8192
MAX_MANIFEST = 512 * 1024
MIMES = {'video/mp4', 'video/quicktime', 'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/heic', 'image/heif'}
SOCIAL = ('tiktok.com', 'instagram.com', 'youtube.com', 'youtu.be', 'twitter.com', 'x.com', 'reddit.com', 'redd.it', 'pinterest.com', 'pin.it', 'facebook.com', 'fb.watch')

def normalize(raw):
    if not isinstance(raw, str) or len(raw) > MAX_BODY or any(ord(c) < 32 for c in raw):
        raise ValueError('invalid_url')
    p = urlsplit(raw)
    if p.scheme != 'https' or not p.hostname or p.username or p.password or p.port not in (None, 443):
        raise ValueError('https_required')
    host = p.hostname.lower()
    if '.' not in host or host.endswith(('.', '.local', '.internal', '.home', '.test', '.invalid')) or '%' in host:
        raise ValueError('unsafe_host')
    return urlunsplit(('https', host + (':443' if p.port else ''), p.path, p.query, ''))

def validate_public(raw, lookup=socket.getaddrinfo):
    url = normalize(raw)
    answers = lookup(urlsplit(url).hostname, 443, type=socket.SOCK_STREAM)
    if not answers:
        raise ValueError('dns_failed')
    for answer in answers:
        address = ipaddress.ip_address(answer[4][0])
        if not address.is_global or address.is_multicast or address.is_reserved or address.is_unspecified or address.is_loopback or address.is_link_local:
            raise ValueError('unsafe_address')
        if getattr(address, 'ipv4_mapped', None):
            raise ValueError('mapped_address')
    return url

def validate_manifest(manifest, source, validate=validate_public):
    if not isinstance(manifest, dict) or manifest.get('sourceURL') != source:
        raise ValueError('source_mismatch')
    if not isinstance(manifest.get('id'), str) or not 1 <= len(manifest['id']) <= 256:
        raise ValueError('invalid_id')
    if not isinstance(manifest.get('title'), str) or len(manifest['title']) > 500 or not isinstance(manifest.get('resolver'), str):
        raise ValueError('invalid_metadata')
    assets = manifest.get('assets', [])
    if not isinstance(assets, list) or not 1 <= len(assets) <= 50:
        raise ValueError('invalid_assets')
    seen = set()
    for asset in assets:
        if not isinstance(asset.get('id'), str) or asset['id'] in seen or asset.get('kind') not in ('image', 'video'):
            raise ValueError('invalid_asset')
        seen.add(asset['id'])
        variants = asset.get('variants', [])
        if not isinstance(variants, list) or not 1 <= len(variants) <= 20:
            raise ValueError('invalid_variants')
        ids = set()
        for variant in variants:
            if not isinstance(variant.get('id'), str) or variant['id'] in ids:
                raise ValueError('invalid_variant_id')
            ids.add(variant['id'])
            mime = variant.get('mimeType')
            if mime not in MIMES or not mime.startswith(asset['kind'] + '/'):
                raise ValueError('invalid_type')
            for field, maximum in [('bytes', 2*1024**3), ('width',16384), ('height',16384)]:
                value = variant.get(field)
                if value is not None and (not isinstance(value, int) or isinstance(value, bool) or not 0 <= value <= maximum):
                    raise ValueError('invalid_' + field)
            validate(variant.get('url'))
    if len(json.dumps(manifest).encode()) > MAX_MANIFEST:
        raise ValueError('manifest_too_large')
    return manifest

class Resolver:
    def __init__(self, catalog, validate=validate_public):
        self.catalog = catalog
        self.validate = validate

    def resolve(self, raw):
        source = self.validate(raw)
        host = urlsplit(source).hostname
        if not any(host == domain or host.endswith('.' + domain) for domain in SOCIAL):
            raise ValueError('unsupported_source')
        # Exact URLs, including short links, must be explicitly authorized in the catalog.
        # No redirect scraping, subprocess extractor, user cookies, DRM or paywall access.
        key = hashlib.sha256(source.encode()).hexdigest()
        manifest = self.catalog.get(key)
        if manifest is None:
            raise LookupError('source_unavailable')
        return validate_manifest(manifest, source, self.validate)

class RateLimit:
    def __init__(self):
        self.lock = threading.Lock()
        self.events = []
    def allow(self):
        # Global limiter cannot be bypassed with a forged X-Forwarded-For header.
        with self.lock:
            now = time.monotonic()
            self.events = [t for t in self.events if t > now - 60]
            if len(self.events) >= 30: return False
            self.events.append(now)
            return True

class Handler(BaseHTTPRequestHandler):
    server_version = 'MONOResolver/1.0'
    def log_message(self, *_): pass  # No URLs or credentials in access logs.
    def setup(self):
        super().setup()
        self.connection.settimeout(15)
    def reply(self, status, body):
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(data)
    def authorized(self):
        expected = 'Bearer ' + self.server.token
        if not hmac.compare_digest(self.headers.get('Authorization', '').encode(), expected.encode()):
            self.reply(401, {'error':'unauthorized'})
            return False
        if not self.server.limiter.allow():
            self.reply(429, {'error':'rate_limited'})
            return False
        return True
    def do_GET(self):
        if not self.authorized(): return
        if self.path == '/v1/health': self.reply(200, {'version':'1.0', 'adapter':'authorized-catalog', 'contract':1})
        else: self.reply(404, {'error':'not_found'})
    def do_POST(self):
        if not self.authorized(): return
        if self.path != '/v1/resolve': return self.reply(404, {'error':'not_found'})
        if self.headers.get('Transfer-Encoding') or self.headers.get_content_type() != 'application/json':
            return self.reply(415, {'error':'json_required'})
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= MAX_BODY: return self.reply(413, {'error':'request_too_large'})
            payload = json.loads(self.rfile.read(length))
            if not isinstance(payload, dict) or set(payload) != {'url'}: raise ValueError('invalid_request')
            result = self.server.resolver.resolve(payload['url'])
            self.reply(200, result)
        except LookupError:
            self.reply(422, {'error':'source_unavailable'})
        except (ValueError, TypeError, AttributeError, KeyError, socket.gaierror):
            self.reply(400, {'error':'invalid_or_unsafe_request'})
        except (TimeoutError, OSError):
            self.reply(504, {'error':'resolution_timeout'})

def make_server(address, token, catalog, validate=validate_public):
    if len(token) < 32: raise ValueError('MONO_TOKEN must contain at least 32 characters')
    server = ThreadingHTTPServer(address, Handler)
    server.daemon_threads = True
    server.token, server.resolver, server.limiter = token, Resolver(catalog, validate), RateLimit()
    return server

if __name__ == '__main__':
    with open(os.environ.get('MONO_CATALOG', 'catalog.json'), encoding='utf-8') as file:
        catalog = json.load(file)
    server = make_server((os.environ.get('MONO_BIND', '127.0.0.1'), int(os.environ.get('PORT', '8080'))), os.environ.get('MONO_TOKEN',''), catalog)
    server.serve_forever()
