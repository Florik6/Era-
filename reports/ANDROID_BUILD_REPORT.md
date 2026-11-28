# ANDROID BUILD REPORT — ERA: Восхождение 0.15.0

Разработка ведётся только для Android: iOS и IPA в этой версии не собирались и не менялись.

## Файлы

| Файл | Размер | SHA-256 |
|---|---|---|
| `builds/android/ERA_Ascension_Android.apk` — основная сборка (рендер Mobile/Vulkan, авто-откат на OpenGL ES 3) | 63 309 632 байт | `7c7e8c373beccb8194dd80a1e16252c7d8a355f7bd6ebee4f8ff9451a57ab637` |
| `builds/android/ERA_Ascension_Android_GL.apk` — совместимая сборка (рендер GL Compatibility, OpenGL ES 3) | 63 309 632 байт | `d1fe3af2ee263f0c96ad865f26e96a6e5e3c390822bf99e4fb4e57f6be33b396` |

Те же файлы лежат в `dist/ERA_Ascension.apk` и `dist/ERA_Ascension_GL.apk` (байт в байт); там же `dist/ERA_Ascension_Source.zip` — исходники без ключей подписи.

Прямые ссылки (работают после отправки коммита в ветку `claude/era-ascension-android-rpg-kf1ila`):
- https://github.com/Florik6/Era-/raw/claude/era-ascension-android-rpg-kf1ila/builds/android/ERA_Ascension_Android.apk
- https://github.com/Florik6/Era-/raw/claude/era-ascension-android-rpg-kf1ila/builds/android/ERA_Ascension_Android_GL.apk

## Как собрано
- Godot 4.7.1 stable, официальные шаблоны экспорта 4.7.1 (template-based export, без Gradle).
- Команда: `tools/build_apk.sh release` — собирает оба пресета, «Android» и «Android GL».
- Подпись: apksigner (build-tools 34.0.0), схемы v2/v3, тот же ключ релиза, что у прошлых версий. Поэтому 0.15.0 ставится поверх как обновление, сохранения остаются (старые сохранения один раз получают боеприпасы и знания уже пройденных эпох).
- Ключ и пароль хранятся только локально: `android/release.keystore` и `android/release_pass.txt` в `.gitignore`, в репозиторий и архив исходников не попадают.

## Проверка (выполнена)
| Проверка | Результат |
|---|---|
| `apksigner verify` | Verifies, v2 и v3 (оба файла) |
| Сертификат подписи | SHA-256 `c782a0b8…a0d4` у обоих, совпадает с прошлыми версиями |
| Манифест | `com.eraascension.game`, `versionCode 18`, `versionName 0.15.0` |
| Аргументы GL-сборки | `assets/_cl_` содержит `--rendering-method gl_compatibility --rendering-driver …` |
| Данные игры | в `assets/` есть новые скрипты: `ammo`, `mana`, `tech_know`, экраны `inspect`, `tech`, `inspect_view` |
| Запуск упакованных данных | `assets/` из APK запущены настольным Godot 4.7.1 со встроенным `--smoke-test`: меню → мир (2,0 с) → бой → сохранение → `ok=true`, версия 0.15.0. **Это не запуск на Android**, а проверка, что в пакете ничего не потеряно |
| Все скрипты компилируются | `tools/check.sh`: 159 файлов, 0 ошибок |

## Чего НЕ было
- **Установки и запуска на реальном Android-устройстве или эмуляторе**: в среде нет ни того, ни другого. FPS, нагрев, память на телефоне и сенсорное управление на экране телефона не измерены.
- Публикации в Google Play (не требовалась).

## Что нового в 0.15.0
- **Ammo & Mana Overhaul** — `reports/AMMO_MANA_REPORT.md`: исправлены бесконечные заряды импульсной винтовки и почти мгновенная мана; полноценные боеприпасы, перезарядка, зелья маны.
- **Technological Knowledge System** — `reports/TECH_KNOWLEDGE_REPORT.md`: знания технологий эпох, 5 стадий освоения, интерактивное изучение предметов, обучение у NPC, перенос знаний, память эпох.

## Что нового в 0.14.0
- **Исправление времени и щитов.** Замедление больше не зависает (`TimeFX`). Щит босса-мага работает по конечному автомату с окнами уязвимости.
- **«Звери Эпох».** 100 существ, 40 боссов, 25 подземелий, экология, логова, мировые боссы, охота, бестиарий, демо «Пробуждение Чёрного Камня».
- **«Восхождение силы»** (0.13.0, впервые в сборке). 200 способностей.

Подробно — `PROGRESS.md`, `reports/COMBAT_FIX_TIME_SHIELD_REPORT.md`, `reports/BEASTS_OF_THE_AGES_REPORT.md`, `reports/ASCENSION_OF_POWER_REPORT.md`.
