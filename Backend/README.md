# Optional authorized resolver

This service provides a real MONO v1 endpoint for an **operator-curated catalog of owned/licensed media**. It does not extract arbitrary TikTok posts. There is no scraper, proxy, subprocess, cookie import or automatic fallback. Unknown sources return 422, never fabricated media.

## Contract

All endpoints require `Authorization: Bearer <your secret>` (at least 32 characters). Place behind HTTPS. Requests with credentials are never redirected by the client.

`GET /v1/health` → `{"version":"1.0","adapter":"authorized-catalog","contract":1}`.

`POST /v1/resolve`, `Content-Type: application/json`, body `{"url":"https://vm.tiktok.com/your-authorized-link/"}`. Only this field is accepted. Exact normalized URL is the authorization/catalog key, including short URLs. Resolving a short link does not imply automated scraping or original-quality TikTok access.

200 response (Swift Codable keys are exact, optional fields may be omitted):

```json
{
  "id": "your-owned-post-id",
  "sourceURL": "https://vm.tiktok.com/your-authorized-link/",
  "title": "Your media",
  "creator": "Your account",
  "resolver": "authorized-catalog/1.0",
  "assets": [{
    "id": "asset-1",
    "kind": "video",
    "duration": 12.5,
    "variants": [{
      "id": "original",
      "url": "https://your-public-cdn.example/owned-file.mp4",
      "mimeType": "video/mp4",
      "width": 1920,
      "height": 1080,
      "fps": 30,
      "codec": "h264",
      "hasAudio": true,
      "bytes": 2300000
    }]
  }]
}
```

The domains and values above document the schema, **not** a functioning download. Supply your own actually accessible files. Never label a variant with dimensions/codecs you have not verified. Carousel: one asset per image, each with its real variants; mixed image/video assets are supported by the contract.

Errors: 400 invalid/unsafe request or manifest; 401 bad/missing bearer; 404 unknown route; 413 body too large; 415 non-JSON/unsupported transfer encoding; 422 unavailable/not authorized; 429 global rate limit; 504 network/DNS timeout. The app maps non-2xx to a source error with exact HTTP status, without leaking signed URL/query/token details.

Limits: 8 KiB request, 512 KiB manifest, 50 assets, 20 variants per asset, 2 GiB file, 30 authenticated requests/minute globally. Socket timeout 15 seconds; client request timeout 30 seconds, resource timeout 45 seconds. The service validates URL scheme, credentials, ports, host and all DNS answers. It never fetches a supplied target, so there is no general fetch proxy or redirect chain. DNS results do not pin the separate iOS download connection: see ../SECURITY.md.

## Catalog

`catalog.json` is a dictionary keyed by SHA-256 of the normalized exact `sourceURL`. Put the above manifest under its matching key. Generate the key using the same normalizer:

```python
from server import normalize
import hashlib
print(hashlib.sha256(normalize("https://vm.tiktok.com/your-authorized-link/").encode()).hexdigest())
```

Start with `catalog.example.json` (empty, no invented successful content). Short URLs must be explicitly cataloged with matching `sourceURL`. Content expiry and platform authorization remain the operator's responsibility. Restart after replacing the catalog. A future authorized API adapter can replace `Resolver.resolve` while preserving validation and auth; it must not bypass source restrictions.

## Deploy

Use a persistent server you control. GitHub Actions builds/tests and then terminates; it is not server hosting.

1. Copy `.env.example` to a private `.env`, generate `MONO_TOKEN` using `secrets.token_urlsafe(48)`, create your private `catalog.json`. Do not commit either.
2. `docker build -t mono-resolver Backend` from repository root.
3. `docker run --read-only --cap-drop ALL --security-opt no-new-privileges --memory 128m --pids-limit 64 --env-file .env -p 127.0.0.1:8080:8080 -v /absolute/private/catalog.json:/data/catalog.json:ro mono-resolver`
4. Reverse proxy your own HTTPS domain to `127.0.0.1:8080`. Enforce 8 KiB body limit, connection/time limits and a bounded upstream worker pool. Do not forward an unbounded public HTTP listener. Do not log Authorization, request bodies or query strings. Keep TLS certificate validation enabled.
5. Set the HTTPS **base URL** (without `/v1/resolve`) and token in MONO Settings → Advanced. Direct-file transfers do not need this server.

Local development without Docker: set `MONO_TOKEN` and `MONO_CATALOG`, run `python Backend/server.py`. Default bind is loopback HTTP; the production iOS app intentionally requires HTTPS and rejects private targets. Do not disable ATS to connect it. Unit tests run their own loopback HTTP fixtures without modifying production policies.

26 backend tests were run on the authoring Windows host. Container build, public TLS deployment and real authorized platform integration require independent verification.
