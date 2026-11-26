# BUILD REPORT — ERA: Восхождение 0.10.0

## 0.10.0 — две сборки и новый загрузчик

| Файл | Рендер | Размер | Подпись |
|---|---|---|---|
| `dist/ERA_Ascension.apk` | Mobile (Vulkan), откат на OpenGL, если Vulkan не инициализируется | 62 140 306 байт | v2 + v3, тот же ключ, что у 0.9.2 (SHA-256 сертификата `c782a0b8…a0d4`) |
| `dist/ERA_Ascension_GL.apk` | Compatibility (OpenGL ES 3): в `assets/_cl_` записаны аргументы `--rendering-method gl_compatibility --rendering-driver opengl3` | 62 140 306 байт | тот же ключ |

- Пресет экспорта «Android GL» отличается только `command_line/extra_args`. Пакет и ключ общие, поэтому сборки ставятся
  друг поверх друга с сохранением прогресса, и обе ставятся поверх 0.9.2.
- Загрузчик: заставка `boot_splash` (картинка `assets/icon/splash.png`) появляется до запуска скриптов. Затем
  `scenes/boot.gd` показывает полосу загрузки и фоново грузит меню (`ResourceLoader.load_threaded_request`).
  При ошибке показывает кнопки «Повторить» и «Безопасный режим». Если прошлый запуск не дошёл до меню,
  включает безопасную графику. Ведёт журнал `user://boot.log`.
- Проверено: `apksigner verify` — v2 и v3 true; оба APK содержат arm64-v8a и armeabi-v7a; аргументы GL-сборки на месте.
  Запуск на устройстве **не проверялся** (нет эмулятора и устройств в среде).
- Прямые ссылки (репозиторий публичный):
  - https://github.com/Florik6/Era-/raw/claude/era-ascension-android-rpg-kf1ila/dist/ERA_Ascension.apk
  - https://github.com/Florik6/Era-/raw/claude/era-ascension-android-rpg-kf1ila/dist/ERA_Ascension_GL.apk

## Инструменты

| Компонент | Версия / источник |
|---|---|
| Godot | 4.7.1.stable.official (a13da4feb), Linux x86_64, github.com/godotengine/godot releases |
| Шаблоны экспорта | 4.7.1.stable (`android_debug.apk`, `android_release.apk`) |
| Способ экспорта | официальный шаблонный экспорт Godot без Gradle (`gradle_build/use_gradle_build=false`) |
| apksigner / adb | Ubuntu 24.04: `apksigner` 31.0.2, `adb` 34.0.4. Положены в `/opt/android-sdk/build-tools/34.0.0` и `platform-tools`, потому что официальный Android SDK (dl.google.com) недоступен из среды |
| JDK | OpenJDK 21 (keytool для ключей) |

Сценарий сборки: `tools/build_apk.sh [debug|release|both]`. Он создаёт ключи (если их нет), настраивает пути SDK, JDK и
debug-ключа в editor settings, импортирует ресурсы и экспортирует оба APK. Время полной сборки около 36 с.

## Пресет экспорта (`export_presets.cfg`)

- Платформа Android, архитектуры **arm64-v8a + armeabi-v7a** в одном APK: все ARM-телефоны, 64 и 32 бит. x86 и x86_64 нужны только эмуляторам на ПК, они выключены ради размера.
- `package/unique_name = com.eraascension.game`, имя «ERA: Восхождение», версия 0.10.0 (code 12).
- Иконки: 192 px и адаптивная 432 px (foreground и background).
- Immersive mode. Разрешение — только VIBRATE, интернет не требуется.
- Ориентация горизонтальная (sensor landscape в project.godot).
- Рендерер Mobile (Vulkan) с `fallback_to_opengl3=true`; Vulkan объявлен как необязательная функция.
- Сжатие текстур ETC2/ASTC.
- Из пакета исключены `tests/`, `tools/`, `docs/`, `builds/`, `dist/`, `android/`.

## Результаты

| Файл | Размер | SHA-256 |
|---|---|---|
| `ERA_Ascension.apk` (единый release, arm64-v8a + armeabi-v7a) | 60 395 588 байт | `48093b29fc09e06e7a3b534b5e59eedcd442bc4752b04013bc90bcba2a64bf57` |

Debug-сборка по-прежнему собирается командой `tools/build_apk.sh debug`, но в `dist/` её больше нет: для установки нужен один файл.

## Проверка APK

- **Формат и подпись:** `file` определяет оба файла как Android package (APK). `apksigner verify` проходит для обоих.
  Подпись debug — `CN=Android Debug, O=Android, C=US`, release — `CN=ERA Ascension, O=ERA, C=RU`.
- **Подпись:** схемы APK Signature v2 и v3 (`apksigner verify -v`). Схема v1 для minSdk 24 не требуется.
- **Манифест (`aapt dump badging`):** `package: name='com.eraascension.game' versionCode='11' versionName='0.9.2'`,
  `sdkVersion:'24'`, `targetSdkVersion:'36'`, метка `ERA: Восхождение`.
  - `android.hardware.vulkan.level` и `.version` объявлены с `required="false"`, так что устройства без Vulkan не отсекаются.
  - `glEsVersion 0x30000` (OpenGL ES 3 для отката).
  - Старый `aapt` v1 выводит «failed to read attribute 'android:required'». Godot записывает этот атрибут для Vulkan строкой
    `"false"`. Android разбирает его через `TypedArray.getBoolean` → `convertValueToBoolean`, так что для установки это безопасно.
    Так выглядит стандартный манифест любого Godot 4 экспорта с Vulkan.
- **Содержимое:**
  - `lib/arm64-v8a/libgodot_android.so` и `libc++_shared.so` — нативный движок, без WebView и браузера;
  - `classes.dex`;
  - игровые ресурсы: 356 файлов, 7.6 МБ — скомпилированные скрипты `.gdc`, импортированные звуки и музыка, шрифты, сцены.
- **Сцена запуска:** `res://scenes/boot.tscn` → главное меню. Пакет ресурсов из Android-экспорта (`--export-pack`) загружен
  на ПК: выход в меню и 900 кадров без ошибок скриптов.
- **Запуск на устройстве или в эмуляторе не проводился:** нет KVM и образов системы.

## Подпись release-сборки

В репозитории нет секретов: ключи в `android/` исключены из git.
- `ERA_Ascension.apk` подписан **локально созданным** 4096-битным RSA-ключом. Он подходит для установки и тестирования.
- Чтобы публиковать в Google Play и выпускать обновления, нужен постоянный ключ разработчика (Android требует один ключ для всех обновлений).
  Создайте свой ключ и соберите так:
  ```bash
  keytool -genkeypair -keystore my-release.keystore -alias era -keyalg RSA -keysize 4096 -validity 10000
  ERA_RELEASE_KEYSTORE=$PWD/my-release.keystore ERA_RELEASE_ALIAS=era ERA_RELEASE_PASSWORD='***' tools/build_apk.sh release
  ```
- Для Google Play нужен формат AAB через Gradle-сборку Godot. Это требует полного Android SDK (см. NEXT_STEPS.md).

## Повтор сборки на чистой машине

1. Установите Godot 4.7.1 и шаблоны экспорта 4.7.1 (Editor → Manage Export Templates либо распаковка `.tpz` в
   `~/.local/share/godot/export_templates/4.7.1.stable/`).
2. Установите JDK 17+ и Android SDK (platform-tools и build-tools 34+). Задайте `ANDROID_SDK_ROOT` и `JAVA_HOME`.
3. Выполните `tools/build_apk.sh both`.
