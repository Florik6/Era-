# ANDROID BUILD REPORT — ERA: Восхождение 0.14.0

Разработка ведётся только для Android: iOS и IPA в этой версии не собирались и не менялись.

## Файлы

| Файл | Размер | SHA-256 |
|---|---|---|
| `builds/android/ERA_Ascension_Android.apk` — основная сборка (рендер Mobile/Vulkan, авто-откат на OpenGL ES 3) | 63 222 634 байт | `f307a7f43be4d457e7e0e764dc3ab33aca7728bf81db61659ec08e3989e3972e` |
| `builds/android/ERA_Ascension_Android_GL.apk` — совместимая сборка (рендер GL Compatibility, OpenGL ES 3) | 63 222 634 байт | `bdbf2bacd54ef535c4b9370fe1edb27b878f16bc2fa90639584c2d7d54cbc834` |

Те же файлы лежат в `dist/ERA_Ascension.apk` и `dist/ERA_Ascension_GL.apk` (байт в байт); там же `dist/ERA_Ascension_Source.zip` — исходники без ключей подписи.

Прямые ссылки работают только **после того, как эти файлы будут закоммичены и отправлены в ветку** `claude/era-ascension-android-rpg-kf1ila` (см. раздел «Состояние репозитория»). До этого по ссылкам лежит прежняя версия 0.12.0:
- https://github.com/Florik6/Era-/raw/claude/era-ascension-android-rpg-kf1ila/builds/android/ERA_Ascension_Android.apk
- https://github.com/Florik6/Era-/raw/claude/era-ascension-android-rpg-kf1ila/builds/android/ERA_Ascension_Android_GL.apk

## Как собрано
- Godot 4.7.1 stable, официальные шаблоны экспорта 4.7.1 (template-based export, без Gradle).
- Команда: `tools/build_apk.sh release` — собирает оба пресета, «Android» и «Android GL».
- Подпись: apksigner (build-tools 34.0.0), схемы v2/v3, тот же ключ релиза, что у прошлых версий. Поэтому 0.14.0 ставится поверх как обновление, сохранения остаются.
- Ключ и пароль хранятся только локально: `android/release.keystore` и `android/release_pass.txt` в `.gitignore`, в архив исходников не попадают (проверено).

## Проверка (выполнена)
| Проверка | Результат |
|---|---|
| `apksigner verify -v` | Verifies, v2 и v3 (оба файла) |
| Сертификат подписи | SHA-256 `c782a0b8…a0d4` у обоих, совпадает с прошлыми версиями |
| Манифест (`aapt dump badging`) | `com.eraascension.game`, `versionCode 17`, `versionName 0.14.0`, `minSdk 24` (Android 7.0+), `targetSdk 36` |
| Нативные библиотеки | `lib/arm64-v8a/libgodot_android.so`, `lib/armeabi-v7a/libgodot_android.so` |
| Аргументы GL-сборки | `assets/_cl_` содержит `--rendering-method gl_compatibility --rendering-driver opengl3` |
| Данные игры | 549 файлов в `assets/`, включая новые скрипты (`time_fx`, `boss_shield`, `db_creatures`, `db_beasts`, `beast_dungeon`, `beast_world`) и 10 новых звуков |
| Запуск упакованных данных | `assets/` из APK запущены настольным Godot 4.7.1 со встроенным `--smoke-test`: меню → загрузка мира (1,6 с) → бой → сохранение → `ok=true`, версия 0.14.0. **Это не запуск на Android**, а проверка, что в пакете ничего не потеряно |
| Все скрипты компилируются | `tools/check.sh`: 153 файла, 0 ошибок |

## Чего НЕ было
- **Установки и запуска на реальном Android-устройстве или эмуляторе**: в среде нет ни того, ни другого. FPS, нагрев, память на телефоне и сенсорное управление на экране телефона не измерены. Цель «30 FPS на среднем устройстве» **не подтверждена**.
- Публикации в Google Play (не требовалась).

## Что нового в 0.14.0
- **Исправление времени и щитов.** Замедление больше не зависает (`TimeFX`). Щит босса-мага работает по конечному автомату с окнами уязвимости.
- **«Звери Эпох».** 100 существ, 40 боссов, 25 подземелий, экология, логова, мировые боссы, охота, бестиарий, демо «Пробуждение Чёрного Камня».
- **«Восхождение силы»** (0.13.0, впервые в сборке). 200 способностей.

Подробно — `PROGRESS.md`, `reports/COMBAT_FIX_TIME_SHIELD_REPORT.md`, `reports/BEASTS_OF_THE_AGES_REPORT.md`, `reports/ASCENSION_OF_POWER_REPORT.md`.
