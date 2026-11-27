# IOS BUILD REPORT — ERA: Восхождение 0.12.0

## Итог (честно)

| Что | Статус |
|---|---|
| Официальный пресет экспорта Godot iOS | ✅ готов (`export_presets.cfg`, пресет «iOS»), версия 0.12.0, сборка 15 |
| Xcode-проект | ✅ экспортирован официальным экспортёром Godot 4.7.1 (Linux): локально и в GitHub Actions |
| macOS-сборка в GitHub Actions | ✅ **впервые выполнилась**: запуски №4 (run 45950622038) и №5 (run 45954909139) получили macOS-раннер (`macos-latest`, Xcode 26.6). В запусках №1–3 macOS-раннер не выдавался |
| `builds/ios/ERA_Ascension_iOS_unsigned.ipa` | ✅ **создан** (запуск №5): 31 899 721 байт, SHA-256 `040762c58f029d9fe90ae6495ad46da7a0ae0ad0200eb08dc8a49dc7422493c2`. Структура проверена `tools/verify_ipa.sh`: исполняемый файл arm64 (59 МБ), данные игры `.pck` (9,9 МБ), иконки, экран запуска, Bundle ID `com.eraascension.game`, версия 0.12.0 (15), iOS 15.0+, альбомная ориентация, iPhone и iPad |
| Подпись | ❌ **IPA не подписан.** Установить его на произвольный iPhone **нельзя**. Можно только переподписать своим Apple ID (AltStore, Sideloadly, Xcode) или подписать в CI через секреты (раздел 4). Данных Apple Developer в репозитории и в чате нет и не будет |
| iOS Simulator | 🟡 **игра запускается и работает, полный смоук-тест не завершился.** iPhone 17 Pro / iOS 26.5: установка, запуск, OpenGL ES 3.0, главное меню (0,4 с), загрузка мира, бой — подтверждено журналом игры (`reports/ios_ci/boot.log`) и снимком экрана (`reports/ios_ci/sim_screenshot.png`: мир средневековья, HUD, заклинание огня). Симулятор очень медленный (≈1 кадр/с: сборка x86_64 под Rosetta и программный OpenGL), поэтому за отведённые 6 минут тест дошёл до этапа «бой» и не успел выдать итог. Окно ожидания увеличено до 25 минут для следующих запусков |
| Установка на физический iPhone | ❌ не выполнялась: нет устройства и нет подписи. Проверка в симуляторе — **не** подтверждение установки на iPhone |

APK не превращался в IPA ни переименованием, ни упаковкой: IPA собран из официального Xcode-проекта Godot компилятором Xcode.

### Что показали первые настоящие запуски на macOS
- **Запуск №4.** Архив для устройства собрался (`** ARCHIVE SUCCEEDED **`), IPA прошёл проверку структуры. Сборка для симулятора **упала при компоновке**: библиотека симулятора из шаблона Godot 4.7.1 собрана не под arm64, а workflow принудительно задавал `ARCHS=arm64`. Ошибку скрыл конвейер `xcodebuild … | tail` без `pipefail`, поэтому шаг выглядел успешным, а в симулятор попало приложение без исполняемого файла («missing its bundle executable»). Возврат результатов в ветку не сработал («unstaged changes»).
- **Исправлено в workflow:** архитектура симулятора берётся из самой библиотеки (`lipo -archs`, здесь x86_64), включён `set -o pipefail`, шаг сборки проверяет наличие исполняемого файла, неудача сборки симулятора не скрывает IPA, в отчёте смоук-теста честно пишется, если он не выполнялся, для возврата в ветку используется `--autostash`.
- **Запуск №5.** Архив, проверка IPA и сборка под симулятор — успешно. Игра установилась и запустилась в симуляторе (см. таблицу). IPA и отчёты автоматически закоммичены в ветку (`builds/ios/`, `reports/ios_ci/`).

## Что сделано

### 1. Пресет экспорта iOS (`export_presets.cfg`, `[preset.2]`)
- Bundle ID `com.eraascension.game` (можно заменить секретом `IOS_BUNDLE_ID`, если в вашем аккаунте Apple зарегистрирован другой).
- Имя «ERA: Восхождение», версия 0.12.0 (сборка 15), минимальная iOS 15.0.
- Архитектура только **arm64**; iPhone + iPad (`TARGETED_DEVICE_FAMILY = 1,2`).
- Ориентация: только альбомная (LandscapeLeft/Right) из настроек проекта.
- Иконка App Store 1024×1024 **без альфа-канала** (`assets/icon/icon_ios_1024.png`); Godot генерирует все размеры.
- Экран запуска (storyboard) с цветом фона игры.
- `export_project_only = true`: Godot создаёт Xcode-проект, а архив и IPA собирает `xcodebuild`.
- Godot сам добавляет требование `iphone-ipad-minimum-performance-a12`: Mobile-рендереру (Metal/Vulkan) нужен A12 или новее, то есть iPhone XS / XR и новее.

### 2. Xcode-проект (`exports/ios_xcode/`)
- Создаётся командой `tools/export_ios.sh release` (официальный экспортёр Godot, шаблон `ios.zip` 4.7.1).
- В git хранятся проект (`ERA_Ascension.xcodeproj`, `ERA_Ascension/` с Info.plist, иконками, storyboard, entitlements) и данные игры `ERA_Ascension.pck` (9,6 МБ).
- Библиотеки движка (`*.xcframework`, ~370 МБ) берутся из официального шаблона без изменений и заново создаются скриптом; в git их нет (лимит GitHub — 100 МБ на файл).
- `DEVELOPMENT_TEAM = UNSIGNED00` — заглушка. Настоящий Team ID подставляется только в CI из секрета `IOS_TEAM_ID`; скрипт меняет временную копию пресета и всегда восстанавливает оригинал.
- Проверено в Info.plist и `project.pbxproj`: `PRODUCT_BUNDLE_IDENTIFIER = com.eraascension.game`, `ARCHS = arm64`, `IPHONEOS_DEPLOYMENT_TARGET = 15.0`, `MARKETING_VERSION = 0.12.0`, `CURRENT_PROJECT_VERSION = 15`, ориентации — только альбомные, `UIRequiresFullScreen`, `UIStatusBarHidden`.

### 3. Облачная сборка: `.github/workflows/ios.yml`
Две задачи:
1. **`xcode-project`** (ubuntu-24.04): ставит Godot 4.7.1 и официальный iOS-шаблон, запускает `tools/export_ios.sh`, выкладывает Xcode-проект артефактом.
   **Результат: ✅ выполнено** — запуск №2 (run 45856768056), экспорт за 22 с, артефакт `ios_xcode_project` (110 МБ, хранится до 10.12.2026).
2. **`ios`** (macOS): `xcodebuild archive` → IPA; проверка IPA (`tools/verify_ipa.sh`); сборка под симулятор и смоук-тест `--smoke-test` (меню → мир → заклинания → сохранение → загрузка, скриншот); загрузка в TestFlight (по желанию); коммит IPA и отчётов обратно в ветку.
   **Результат:** запуски №1–3 (26.11) не получили macOS-машину (`runner_id: 0`, отмена через 15 минут). Запуски №4 и №5 (27.11) выполнились на `macos-latest` (Xcode 26.6): архив и IPA — успешно, симулятор — см. «Итог».

**Если macOS-раннер снова не выдаётся (так было в запусках №1–3):**
- проверить в настройках GitHub (Settings → Billing and plans / Actions), разрешены ли macOS-раннеры, и перезапустить workflow (Actions → iOS build → Run workflow);
- или подключить свой Mac как self-hosted runner и задать переменную репозитория `IOS_RUNNER` (например, `self-hosted`); метка раннера в workflow настраивается;
- или собрать IPA на любом Mac с Xcode 16 из артефакта `ios_xcode_project` (команды — в разделе 5).

### 4. Подпись (только через секреты CI)
Пароли, ключи и сертификаты **не** передаются в чат. Их добавляют в GitHub → Settings → Secrets and variables → Actions:

| Секрет | Что это |
|---|---|
| `IOS_TEAM_ID` | Team ID из Apple Developer (10 символов) |
| `IOS_CERT_P12_BASE64` | сертификат подписи с ключом (.p12), закодированный в base64 |
| `IOS_CERT_PASSWORD` | пароль от этого .p12 |
| `IOS_PROFILE_BASE64` | профиль .mobileprovision для Bundle ID, в base64 |
| `IOS_BUNDLE_ID` | (необязательно) Bundle ID из вашего аккаунта |
| `APPSTORE_KEY_ID`, `APPSTORE_ISSUER_ID`, `APPSTORE_KEY_P8_BASE64` | (необязательно) ключ App Store Connect API для TestFlight |

Workflow сам определяет тип профиля (Development / Ad Hoc / App Store / Enterprise), создаёт временную связку ключей, подписывает вручную и в конце удаляет связку. Без секретов собирается **неподписанный** `ERA_Ascension_iOS_unsigned.ipa`. Такой файл **нельзя** установить на произвольный iPhone: его можно только переподписать своим Apple ID (AltStore, Sideloadly) или использовать для проверки структуры.

### 5. Сборка на своём Mac (без CI)
```
tools/export_ios.sh release            # или распаковать артефакт ios_xcode_project в exports/
cd exports/ios_xcode
xcodebuild -project ERA_Ascension.xcodeproj -scheme ERA_Ascension -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -archivePath build/ERA_Ascension.xcarchive archive
xcodebuild -exportArchive -archivePath build/ERA_Ascension.xcarchive \
  -exportOptionsPlist ERA_Ascension/export_options.plist -exportPath build/ipa
bash ../../tools/verify_ipa.sh build/ipa/*.ipa com.eraascension.game
```
Для запуска на своём iPhone откройте проект в Xcode, выберите свою команду в Signing & Capabilities и нажмите Run.

### 6. Проверка IPA (`tools/verify_ipa.sh`, запускалась на реальном IPA в запусках №4 и №5 — `reports/ios_ci/IPA_VERIFICATION.md`)
Payload/*.app, Bundle ID, имя, версия и номер сборки, минимальная iOS, ориентации, семейство устройств, архитектура исполняемого файла (`lipo`, нужна arm64), наличие `.pck` и `Assets.car`, экран запуска, подпись (`codesign --verify --deep --strict`), команда, entitlements, встроенный профиль (тип, срок, совпадение с Bundle ID).

## Совместимость кода с iOS (проверено в коде, не на устройстве)
- **Безопасные зоны, вырез, Dynamic Island:** HUD, сенсорное управление и меню берут отступы из `DisplayServer.get_display_safe_area()` (`hud.gd`, `touch_controls.gd`, `ui_theme.gd`) на всех мобильных ОС (`OS.has_feature("mobile")` верно и для iOS). Игра только в альбомной ориентации; отступы считаются для левого и правого краёв.
- **Сохранения:** только `user://` (на iOS это контейнер приложения), атомарная запись через временный файл.
- **Шейдеры:** все шейдеры проекта компилируются в Mobile- и GL Compatibility-рендерерах (проверено на Linux; на iOS Godot использует Metal). Глобальные параметры шейдеров объявлены в `project.godot`.
- **Управление:** то же сенсорное управление, что на Android; клавиатура и мышь не нужны.
- **Самопроверка:** `--smoke-test` на Linux (GL): меню за 2,1 с, мир за 1,9 с, бой, сохранение и загрузка — `ok: true`.

## Чего нет
- Подписанного IPA (нужны данные Apple Developer владельца, только через секреты GitHub).
- Установки на физический iPhone.
- Завершённого полного смоук-теста в симуляторе (игра запустилась и дошла до боя, итог не успел записаться за 6 минут; окно увеличено).
