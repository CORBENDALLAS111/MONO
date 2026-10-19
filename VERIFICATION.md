# Verification record

Date: 2026-10-19. Authoring host: Windows, no Xcode/Apple SDK installed.

## Current verified source

Source: `2b4ebe553d6587996159697fa7c8b22bb91709d6`.
[Successful Actions run 39184865661](https://github.com/CORBENDALLAS111/MONO/actions/runs/39184865661), completed 2026-10-19.

- Xcode 26.6 (17F113), iOS SDK 26.5, macos-26 runner.
- Real device app + Share Extension build: **BUILD SUCCEEDED**. Unsigned archive: **ARCHIVE SUCCEEDED**.
- iPhone Air simulator, iOS 26.5: **23 unit tests + 3 deterministic UI tests passed**. Coverage includes real NSItemProvider text/URL conversion, native paste → inspector → download → log console → library, both Home themes and the unsupported social-service error.
- Separate opt-in live test: **1 UI test passed**, actual NASA Blue Marble HTTPS image resolution/download/local verification/library flow. No URLProtocol in this test; foreground-session limitation described below.
- Backend: **26 tests passed** in the same run.
- Actual artifacts: [MONO-UNSIGNED-device](https://github.com/CORBENDALLAS111/MONO/actions/runs/39184865661/artifacts/12157698360) (2,324,781 bytes) and [MONO-build-logs](https://github.com/CORBENDALLAS111/MONO/actions/runs/39184865661/artifacts/12157564082) (6,713,762 bytes). The private repository requires authorized GitHub access. Retention is 14 days.
- Downloaded and inspected the IPA: app binary 1,027,368 bytes, extension binary 135,768 bytes. Both have version 1.0.0/build 1 and minimum iOS 26.0. Expected bundle IDs are `com.example.mono` and `com.example.mono.share`; these still require replacement for signing.
- Unedited xcresult screenshots copied into `screenshots/`: Obsidian, Porcelain and the real session log console. `manifest.json` records test/device/timestamps. Visual inspection confirms removed Home eyebrow/slogan, no inner rectangular paste fill, readable light-mode paste control, and upward log blur/fade. These captures do not establish complete accessibility/device QA.
- Local repository integrity: 27 Swift syntax trees, 153 keys per language, 31 SVGs and configuration checks passed; `git diff --check` passed.

Later documentation/screenshot-only commits do not change the tested application source above.

## Earlier evidence and limits

- Backend: 26 unittest methods passed, including actual localhost HTTP requests, catalog/carousel, authentication and unsafe DNS cases.
- Swift sources also pass tree-sitter syntax inspection. This local check does **not** type-check Apple APIs or execute Swift tests.
- 153 Russian/English localization keys generated; 31 official Lucide assets pinned and native paths generated.
- Earlier successful Xcode run: [39182024858](https://github.com/CORBENDALLAS111/MONO/actions/runs/39182024858), source `309d56cdc0ffb7530f40f5cc24808eaa9de24887`. Xcode 26.6 (17F113), iOS SDK 26.5, iPhone Air simulator on iOS 26.5. Device app and extension build/archive succeeded; 19 unit tests and 3 UI tests passed. This predates the latest Home/log-console changes.
- That run uploaded actual unsigned archive/IPA and xcresult/screenshots. No signed build, certificate, provisioning profile or physical-device installation has been produced.

Production downloads use a background URLSession. The separate opt-in real HTTPS smoke test uses an ephemeral foreground session because the unsigned hosted simulator rejected nsurlsessiond XPC. A successful foreground smoke test cannot establish physical-device background recovery.

Unsigned artifacts require signing before installation. Optional `MONO-SIGNED-<method>` remains unproduced because Apple signing credentials have not been supplied. Physical-device Share Extension, background execution, Photos denial and VoiceOver remain unverified; see CHECKLIST.md and README.md.
