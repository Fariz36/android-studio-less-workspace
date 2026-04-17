# Android CLI FAFO Setup

This folder is a lightweight replacement for the parts of Android Studio you
actually need day-to-day when you prefer:

- editing in a normal editor
- using a physical device instead of an emulator
- running build/install/logcat from the terminal

It does not create an Android project for you. It wraps the common CLI flow for
an existing Gradle-based Android app.

## What is here

- `android`: main command wrapper
- `lib/android_common.sh`: shared detection logic
- `.android-env.example`: per-project configuration template

## Expected baseline

- Java installed
- Android SDK platform-tools available somewhere in WSL or Windows
- an Android Gradle project with `gradlew`
- USB debugging enabled on your device

## Quick start

1. Copy `.android-env.example` to `.android-env`
2. Set `PROJECT_DIR` to your Android app root
3. Optionally set `ADB_BIN`, `ADB_SERIAL`, `APP_ID`, and `LAUNCH_ACTIVITY`
4. Run:

```bash
cd /home/fariz/TUGAS_ITB/mobdev/fafo_setup
chmod +x android
./android doctor
./android devices
./android build
./android install
./android launch
./android logs
```

You can also skip `.android-env` and pass values inline:

```bash
./android --project ~/code/MyApp --serial 2a8df356 build
./android --project ~/code/MyApp --serial 2a8df356 install
./android --project ~/code/MyApp --app-id com.example.myapp launch
./android --adb-bin /path/to/adb devices
```

## Commands

### `doctor`

Prints detected Java, SDK, adb, Gradle, device list, and project config.

### `devices`

Equivalent to `adb devices`.

### `tasks`

Runs `./gradlew tasks --all`.

### `build`

Runs:

```bash
./gradlew :app:assembleDebug
```

The module and variant are configurable.

### `install`

First tries:

```bash
./gradlew :app:installDebug
```

If that task fails, it falls back to `adb install -r` using the newest APK it
can find under `build/outputs/apk`.

### `launch`

- If `LAUNCH_ACTIVITY` is set, it runs `adb shell am start -n ...`
- Otherwise it uses `adb shell monkey` with the package name

### `logs`

Runs `adb logcat`. Extra args are passed through:

```bash
./android logs ActivityManager:I *:S
```

## WSL note

In many WSL setups, `adb` is installed on Windows, not Linux. The script tries
to detect these common locations automatically:

- `$ANDROID_SDK_ROOT/platform-tools/adb`
- `$ANDROID_HOME/platform-tools/adb`
- `~/Android/Sdk/platform-tools/adb`
- `/mnt/c/Users/*/AppData/Local/Android/Sdk/platform-tools/adb.exe`

If detection still fails, set `ANDROID_SDK_ROOT` in your shell profile or put
`adb` on your WSL `PATH`. If you already know the right binary, set `ADB_BIN`
in `.android-env` and skip autodetection entirely.

## Recommended bare minimum workflow

If you want a practical Android-Studio-without-Android-Studio setup, keep it
small:

- editor: VS Code, Neovim, or whatever you already use
- build: project `gradlew`
- device: physical phone via `adb`
- logs: `adb logcat`
- inspection: `adb shell`, `dumpsys`, `pm`, `am`

That gets you most of the daily loop without the IDE overhead.
