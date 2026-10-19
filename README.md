# MONO · iOS 26

Нативное приложение на Swift 6 / SwiftUI для сохранения **собственных и разрешённых** медиа. MONO — рабочее название, проверка товарного знака не выполнена.

## Статус

Исходники, генератор проекта, два таргета, локализации и workflows находятся в этом репозитории. Смотрите [VERIFICATION.md](VERIFICATION.md) для **фактических**, а не предполагаемых результатов сборки. Написанный workflow сам по себе не является доказательством сборки. Последний статус CI виден во вкладке Actions.

## Что реализовано

- Прямой HTTPS-файл с корректным HEAD, MIME и публичным адресом: MP4/MOV, JPEG/PNG/GIF/WebP/HEIC/HEIF. HLS/DASH, страницы и ответы application/octet-stream не выдаются за поддерживаемое медиа.
- Реальные URLSessionDownloadTask, фоновая сессия, очередь 1–4, пауза с resume data, повтор, отмена, известные байты/скорость/ETA. Неизвестный размер не превращается в выдуманный процент. Настройки сети применяются к новым URLSession-задачам; существующие требуется отменить и создать заново.
- Атомарная запись метаданных, восстановление задач/промежуточных файлов, проверка сигнатуры, ImageIO/AVFoundation для реальных локальных параметров, SHA-256 и совместное хранение одинаковых файлов. По умолчанию байты сохраняются без перекодирования. Ограничение 2 ГБ на файл.
- Inspector с реальными вариантами, выбор отдельных элементов карусели, ограниченный предпросмотр фотографий (до 8 МБ), доступные параметры, имя и логическая коллекция. У direct resolver разрешение до загрузки обычно неизвестно; качество обозначается «Исходный файл».
- Локальная библиотека, сетка/список, поиск, фильтры типа/источника/коллекции, порядок по дате, избранное, переименование, подтверждение удаления, Quick Look, Share Sheet, системный экспорт в Files, add-only доступ к Photos. Имя и коллекция хранятся в метаданных; внутренние файлы имеют UUID для защиты путей.
- Пресеты: лучший доступный вариант / меньший / только фото, редактор, Wi-Fi и сохранение в Photos. Пресет не создаёт отсутствующее разрешение и не перекодирует файл.
- Obsidian, Porcelain, System; подлинный glassEffect для элементов управления, системные панели и непрозрачные поверхности контента. Lucide в нативном Path, 44 pt кнопки, Dynamic Type, VoiceOver labels, Reduce Motion/Transparency. Дизайн ещё должен пройти визуальную проверку на симуляторе и устройстве.
- Реальное Share Extension для URL/текста, App Group inbox с атомарной записью и дедупликацией. Расширение сообщает, что нужно открыть приложение. Системный URL scheme: `mono://import?url=<percent-encoded-https-url>`; универсальные ссылки не заявляются.
- Keychain для bearer-токена, отсутствие аналитики, контекстные разрешения и добровольные уведомления. Диагностика не содержит ссылок, имён файлов или токенов.

## Честно о TikTok и социальных сетях

MONO распознаёт TikTok, включая `vm.tiktok.com`/`vt.tiktok.com`, Instagram, YouTube, X, Reddit, Pinterest и Facebook. **Распознавание не означает поддержку скачивания платформы.** Без настроенного HTTPS endpoint и токена приложение объясняет ограничение.

В `Backend/` есть рабочий опциональный **authorized-catalog resolver**: оператор связывает точный социальный URL с манифестом собственных/лицензированных файлов. Он не скрейпит TikTok и не обходит редиректы коротких ссылок: короткий URL также должен присутствовать в разрешённом каталоге. Можно реализовать другой авторизованный адаптер того же контракта. Встроенного универсального TikTok extractor, yt-dlp, cookies, обхода DRM/CAPTCHA/закрытых аккаунтов и удаления watermark нет. TikTok Display API не объявляется download API.

## Структура

```text
Config/App.xcconfig            # имя, bundle IDs, App Group, команда
project.yml                   # XcodeGen 2.44.1, все таргеты и scheme
MONOApp/
  App/                        # lifecycle, очередь, восстановление
  DesignSystem/               # темы, native glass, Lucide wrapper
  Features/{Home,Inspector,Downloads,Library,Settings}/
  Domain/Media/               # manifest, variants, jobs, presets
  Data/{Resolvers,Downloads,Storage}/
  Services/Permissions/       # PhotoKit, Keychain
Shared/                       # URL policy, inbox, ru/en resources
MONOShareExtension/            # NSExtension, SwiftUI + UIKit host
MONOTests/                    # unit tests
MONOUITests/                  # controlled Debug fixture UI tests
Backend/                      # authenticated catalog resolver + tests
.github/workflows/            # unsigned CI + signed release
scripts/                      # generators, build, signing and checks
Vendor/Lucide/                # pinned official SVG and license
```

## Сборка через GitHub — Mac у владельца не требуется

1. Push этого отдельного репозитория в GitHub. В Actions включить workflows.
2. Открыть **iOS CI → Run workflow** либо отправить коммит. Runner `macos-26`: скрипт обнаруживает установленные stable Xcode 26.x, выбирает 26.6, если он есть, и сохраняет реальную версию. Никакого Xcode для Windows не предполагается.
3. XcodeGen 2.44.1 собирается из фиксированного git tag. Assets/иконки/локализации уже включены, генерация не требует сетевых пакетов.
4. CI собирает app + extension для устройства, делает unsigned archive, запускает unit/UI tests на доступном iPhone с iOS 26. При отсутствии runtime выполняет build-for-testing и явно сообщает **SKIPPED**, а не PASS.
5. В завершённом run → Artifacts: `MONO-UNSIGNED-device` (реальный `.xcarchive.tar.gz` и `MONO-UNSIGNED-REQUIRES-SIGNING.ipa`), `MONO-build-logs` (логи и `.xcresult`). Наличие и корректность результатов подтверждаются только успешным run.

Unsigned IPA **не устанавливается на iPhone напрямую**. Он требует корректной переподписи и совместимых entitlements. Сам факт успешной компиляции не даёт право или техническую возможность установки.

На Mac: Xcode 26.x, XcodeGen 2.44.1; `xcodegen generate`, открыть `MONO.xcodeproj`, выбрать scheme MONO. Конфигурация iPhone-only, iOS 26+, Swift 6 strict concurrency. Необходимые Info.plist/entitlements генерируются из закоммиченного `project.yml`.

## Подписанный IPA и установка

В Apple Developer зарегистрировать **два отдельных explicit App ID** и общий App Group. Выдать обоим компонентам одинаковый group entitlement. Изменить `Config/App.xcconfig` и repository variables `APP_BUNDLE_ID`, `EXTENSION_BUNDLE_ID`, `APP_GROUP` согласованно. По умолчанию `com.example.mono`, `com.example.mono.share`, `group.com.example.mono` — плейсхолдеры, не готовая подпись.

GitHub Secrets:

| Secret | Значение |
|---|---|
| `APPLE_P12_BASE64` | base64 .p12 с private key |
| `APPLE_P12_PASSWORD` | пароль .p12 |
| `APPLE_TEAM_ID` | Apple Team ID |
| `APP_PROFILE_BASE64` | профиль приложения |
| `EXTENSION_PROFILE_BASE64` | отдельный профиль расширения |

**Signed iOS release → Run workflow**: `ad-hoc`, `development` либо `app-store-connect`. Метод должен совпадать с обоими профилями и сертификатом. Workflow проверяет срок, Team ID, exact bundle IDs, App Group, тип профиля и членство сертификата в обоих профилях; импортирует private key во временный Keychain; архивирует; выполняет настоящий `xcodebuild -exportArchive`; проверяет codesign и очищает ключи/профили в always-step.

Артефакт после успешного экспорта: `MONO-SIGNED-<method>`. Development/ad-hoc устанавливаются только на устройства с UDID в обоих профилях, например через Apple Configurator/Xcode Devices на Mac или совместимый инструмент установки подписанных IPA. App Store export предназначен для дальнейшей загрузки в App Store Connect/TestFlight, а не прямой установки. App Store approval не гарантируется. При sideloading без App Group Share Extension не сможет передавать ссылки; приложение покажет ошибку.

Ошибки provisioning обычно означают несовпадение bundle ID/Team/App Group, отсутствие private key, истёкший профиль или незарегистрированный UDID. Исправьте оба профиля и повторите run; не удаляйте entitlements, чтобы скрыть ошибку.

## Backend

См. [Backend/README.md](Backend/README.md): отдельный постоянный HTTPS-хостинг, никогда GitHub Actions как сервер. Backend необязателен для прямых файлов. Конфигурация в приложении: Настройки → Дополнительно → HTTPS endpoint и bearer token.

## Что ещё не завершено / не заявляется

- Универсальное скачивание TikTok и других социальных платформ; автоматическое раскрытие коротких социальных ссылок вне авторизованного адаптера.
- Аудиоэкстракция, MP3, remux/transcode, HLS/DASH, DRM; вымышленных вариантов 4K нет.
- Universal Links/Associated Domains, App Intents/Shortcuts, импорт локальных медиа в расширение.
- Массовые операции библиотеки, шаблоны имён, настраиваемые retry/backoff/timeout, per-source permissions, granular reset, полный редактор внешних путей хранения, контроль интенсивности эффектов/плотности/аспекта.
- Интерактивный видеопредпросмотр до загрузки и предзагрузка удалённой AV-метадаты. Реальные локальные видео доступны через Quick Look/AVFoundation после загрузки.
- Защита от DNS rebinding между предварительной проверкой и внутренним DNS URLSession не доказана: см. [SECURITY.md](SECURITY.md). Это ограничение до публичного распространения требует отдельной сетевой проверки/решения.
- Реальные device-проверки Share Sheet, background recovery, Photos permission denial, VoiceOver и визуальная доводка. Наличие labels и тестов не считается пройденным ручным аудитом.

Полный исходный запрос шире реализованного набора. Список выше намеренно фиксирует оставшуюся работу вместо утверждения, что все acceptance criteria уже выполнены.

## Проверки локально

`python -m unittest discover -s Backend/tests -v` — без внешней сети, включая настоящий локальный HTTP test server.

`python scripts/validate_repository.py` — целостность конфигурации, локализаций, иконок, plist и Swift syntax (tree-sitter, **не** компилятор Swift). Для этого: `pip install -r scripts/requirements-dev.txt`.

Иконки воспроизводимы: `python scripts/generate_icons.py`. Источник закреплён commit SHA в скрипте; точная замена отсутствующих имён описана в [DESIGN.md](DESIGN.md). `python scripts/generate_assets.py` создаёт оригинальный app icon; это графический ассет, не скриншот симулятора.
