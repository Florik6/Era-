# ANDROID BUILD REPORT — ERA: Восхождение 0.12.0

## Файлы

| Файл | Размер | SHA-256 |
|---|---|---|
| `builds/android/ERA_Ascension_Android.apk` — основная сборка (рендер Mobile/Vulkan, авто-откат на OpenGL ES 3) | 62 726 018 байт | `7b3a7f6e3baf61bb4fbf5cd1410f0e6e8b08bda5b9ed77967261b5122db717e0` |
| `builds/android/ERA_Ascension_Android_GL.apk` — совместимая сборка (рендер GL Compatibility, OpenGL ES 3) | 62 726 018 байт | `1141ac1b2cad3beff45f7216839ce76e005422a74d9d0aee7286db00aa70e1f3` |

Те же файлы лежат в `dist/ERA_Ascension.apk` и `dist/ERA_Ascension_GL.apk` (байт в байт), чтобы старые ссылки продолжали работать.

Прямые ссылки (публичный репозиторий, без входа в GitHub):
- https://github.com/Florik6/Era-/raw/claude/era-ascension-android-rpg-kf1ila/builds/android/ERA_Ascension_Android.apk
- https://github.com/Florik6/Era-/raw/claude/era-ascension-android-rpg-kf1ila/builds/android/ERA_Ascension_Android_GL.apk

## Как собрано
- Godot 4.7.1 stable, официальные шаблоны экспорта 4.7.1 (template-based export, без Gradle).
- Команда: `tools/build_apk.sh release` — собирает оба пресета («Android» и «Android GL»).
- Подпись: apksigner (build-tools 34.0.0), схемы v2/v3, ключ релиза тот же, что у 0.9.2–0.10.2.
  Сертификат SHA-256 `c782a0b85ba035e1c7923187d6284cf3668b12f97886ad335822d7c13c22a0d4`, поэтому 0.12.0 ставится поверх прежней версии как обновление, сохранения не теряются.
  Ключ и пароль хранятся только локально (`android/release.keystore`, `android/release_pass.txt` — в `.gitignore`).

## Проверка (выполнена)
| Проверка | Результат |
|---|---|
| `apksigner verify -v` | Verifies (оба файла) |
| Сертификат подписи | `c782a0b8…a0d4` у обоих, совпадает с прошлыми версиями |
| Манифест (разбор бинарного `AndroidManifest.xml`) | `package com.eraascension.game`, `versionCode 15`, `versionName 0.12.0`, `minSdkVersion 24` (Android 7.0+), `targetSdkVersion 36` (оба файла) |
| Нативные библиотеки | `lib/arm64-v8a/libgodot_android.so` (71,1 МБ), `lib/armeabi-v7a/libgodot_android.so` (74,9 МБ) |
| Аргументы GL-сборки | `assets/_cl_` содержит `--rendering-method gl_compatibility --rendering-driver opengl3` |
| Данные игры | 493 файла в `assets/` (скрипты, сцены, звуки, шрифты) |
| Все скрипты компилируются | `tools/check.sh`: 135 файлов, 0 ошибок |

## Чего НЕ было
- **Установки и запуска на реальном Android-устройстве или эмуляторе**: в среде нет ни того, ни другого. Скорость, нагрев и FPS на телефоне не измерены, цель «30 FPS на среднем устройстве» не подтверждена.
- Публикации в Google Play (не требовалась).

## Что нового в 0.12.0 для Android
Мирные живые города (распорядок дня, стража, редкие налёты, восстановление), 160 событий, 150 новых предметов с 10 легендарными и 5 мифическими способностями, визуальная экипировка с 3D-примеркой, ремесло, Hardcore Mode с X-ray-меню анатомии, собственные дома с сундуком и мебелью, мирные легенды горожан. Подробно — `PROGRESS.md`, проверки — `reports/EXPANSION_TEST_REPORT.md`.
