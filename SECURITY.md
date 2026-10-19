# Security boundaries and known limitations

Only download media you own or are authorized to save. This repository provides no DRM, authentication, CAPTCHA or private-account bypass. An upstream service is not a substitute for authorization.

The client allows HTTPS on port 443, without URL credentials, and rejects local host suffixes. DNS preflight rejects private, loopback, link-local, reserved/multicast IPv4 and non-global IPv6 candidates. Every followed redirect repeats validation, at most five redirects. Backend bearer requests refuse redirects entirely; cookies and shared caches are disabled. There are no arbitrary backend endpoints embedded in the app.

**Known networking limitation:** Foundation background URLSession resolves DNS independently after preflight. These checks are not a proof against an attacker changing DNS answers between validation and connection, including later background reconnection. This has not been closed with a connection-level address policy. Do not claim complete SSRF resistance or deploy this as a high-assurance untrusted-link fetcher. Public distribution requires a separately reviewed solution or a narrowly administered source/CDN allowlist with stable trusted DNS. The included server cannot be a fetch proxy because it never makes media HTTP requests; catalog media URLs are separately validated by both parties.

File imports accept a fixed MIME set, enforce byte limits and inspect headers. ImageIO/AVFoundation inspect actual local content before completion. MIME/header inspection is not an antivirus or formal parser-safety guarantee. Keep iOS updated. Filenames are sanitized and managed files use internal UUID names. No remote manifest controls a local path. Original files are never silently recompressed.

Library snapshot and resume data use atomic protected writes; media are excluded from backup. Signed URLs with query tokens may remain in private on-device queue metadata because they are needed to resume downloads. They are not included in diagnostics. Backend bearer tokens use Keychain, not UserDefaults. Never commit real tokens, `.p12`, profiles, `.env` or signed content catalogs.

Share extension accepts URL/text only, writes a small protected App Group inbox and performs no resolver/network work. Provision App Group for both signed targets. No responder-chain launch hacks. Custom URL scheme is an input convenience, not a trust boundary; imported links always require inspection and explicit download.

Release fixture network code is removed with `#if DEBUG`; the CI UI fixture requires a launch argument and cannot intercept production media. Production progress comes from URLSession byte callbacks. Tests that mock DNS/network prove logic, not real-device platform behavior.

The optional backend requires a long bearer, constant-time comparison, body/type limits and global rate limiting. It uses exact operator-approved catalog entries only. Deploy behind TLS and bounded reverse-proxy connections, isolate the container and keep access logs free of secrets. It has no CORS surface for browsers and does not accept cookies, subprocess arguments or custom extractor commands.

Signing credentials are temporary CI files, never echoed. The release workflow checks both profile entitlements/certificate membership and removes known profiles plus the temporary Keychain on exit. No permission is granted to upload to App Store Connect automatically. An App Store export is not App Store approval.

If reporting a vulnerability, use GitHub private vulnerability reporting when enabled. Do not publish signed URLs, tokens, private media or signing material in issues. No private reporting endpoint is invented here.
