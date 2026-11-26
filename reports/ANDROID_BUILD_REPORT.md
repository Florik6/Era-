# ANDROID BUILD REPORT — ERA: Восхождение 0.11.0

## Файлы

| Файл | Размер | SHA-256 |
|---|---|---|
| `builds/android/ERA_Ascension_Android.apk` — основная сборка (рендер Mobile/Vulkan, авто-откат на OpenGL ES 3) | 62 444 144 байт | `dc85fc1cf33db9edc164ab0bddeeb9fb68dbc18ac00812ace6b339559ea46e03` |
| `builds/android/ERA_Ascension_Android_GL.apk` — совместимая сборка (рендер GL Compatibility, OpenGL ES 3) | 62 444 144 байт | `d883d4a2111c656c59fef6c7c3db07c27b174bbbea7ea7622d057e58a1e10cac` |

Те же файлы лежат в `dist/ERA_Ascension.apk` и `dist/ERA_Ascension_GL.apk` (байт в байт), чтобы старые ссылки продолжали работать.

Прямые ссылки (публичный репозиторий, без входа в GitHub):
- https://github.com/Florik6/Era-/raw/claude/era-ascension-android-rpg-kf1ila/builds/android/ERA_Ascension_Android.apk
- https://github.com/Florik6/Era-/raw/claude/era-ascension-android-rpg-kf1ila/builds/android/ERA_Ascension_Android_GL.apk

## Как собрано
- Godot 4.7.1 stable, официальные шаблоны экспорта 4.7.1 (template-based export, без Gradle).
- Команда: `tools/build_apk.sh release` — собирает оба пресета («Android» и «Android GL»).
- Подпись: apksigner (build-tools 34.0.0), схемы v2/v3, ключ релиза тот же, что у 0.9.2–0.10.2.
  Сертификат SHA-256 `c782a0b85ba035e1c7923187d6284cf3668b12f97886ad335822d7c13c22a0d4`, поэтому 0.11.0 ставится поверх прежней версии как обновление, сохранения не теряются.
  Ключ и пароль хранятся только локально (`android/release.keystore`, `android/release_pass.txt` — в `.gitignore`).

## Проверка (выполнена)
| Проверка | Результат |
|---|---|
| `apksigner verify -v` | Verifies (оба файла) |
| Сертификат подписи | `c782a0b8…a0d4` у обоих, совпадает с прошлыми версиями |
| `aapt dump badging` | `package: name='com.eraascension.game' versionCode='14' versionName='0.11.0'`, `sdkVersion:'24'` (Android 7.0+), `targetSdkVersion:'36'`, label «ERA: Восхождение» |
| Нативные библиотеки | `lib/arm64-v8a/libgodot_android.so` (71,1 МБ), `lib/armeabi-v7a/libgodot_android.so` (74,9 МБ) |
| Аргументы GL-сборки | `assets/_cl_` содержит `--rendering-method gl_compatibility --rendering-driver opengl3` |
| Данные игры | 453 файла в `assets/` (скрипты, сцены, звуки, шрифты) |
| Все скрипты компилируются | `tools/check.sh`: 115 файлов, 0 ошибок |

## Чего НЕ было
- **Установки и запуска на реальном Android-устройстве или эмуляторе**: в среде нет ни того, ни другого. Скорость, нагрев и FPS на телефоне не измерены, цель «30 FPS на среднем устройстве» не подтверждена.
- Публикации в Google Play (не требовалась).

## Что нового в 0.11.0 для Android
Магический резонанс и катастрофы, «Буря над Чёрным городом», Combat Clash, пул динамического света, мокрые дороги, лужи и снег, грейдинг эпох, исторические эхо, живой вид особого оружия, инерция плаща и волос, режимы камеры, профиль «Максимум» и отдельные настройки графики (хранятся на устройстве). Подробно — в `PROGRESS.md`, результаты проверок — в `reports/CROSS_PLATFORM_TEST_REPORT.md`.
