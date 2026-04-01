# Android CLI FAFO Setup

This folder is a lightweight replacement for the parts of Android Studio you
actually need day-to-day when you prefer:

- editing in a normal editor
- using a physical device instead of an emulator
- running build/install/logcat from the terminal

It can now do both:

- initialize a new Android project with a modern Android Studio style layout
- wrap the common CLI flow for an existing Gradle-based Android app

## What is here

- `android`: main command wrapper
- `lib/android_common.sh`: shared detection logic
- `lib/android_init.sh`: project generator
- `.android-env.example`: per-project configuration template

## Expected baseline

- Java installed
- Android SDK platform-tools available somewhere in WSL or Windows
- USB debugging enabled on your device

## Quick start

### Install globally

```bash
cd <path-to-android-studio-less-workspace>
chmod +x android install.sh
./install.sh
```

By default this installs a symlink as `androidws` in `~/.local/bin`.

If `~/.local/bin` is not already on your `PATH`, add this to `~/.bashrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Then reload your shell:

```bash
source ~/.bashrc
```

Check whether the command is available:

```bash
./install.sh --check
```

That checks whether `androidws` is already on your `PATH`.

You can also check directly with:

```bash
command -v androidws
```

You can install a different command name too:

```bash
./install.sh myandroid
```

Global config is stored at:

```bash
~/.config/android-studio-less-workspace/config.env
```

Config lookup order is:

- `--env-file /path/to/file`
- `ANDROID_WORKSPACE_ENV_FILE`
- nearest `.android-env` from your current directory upward
- nearest `.android-workspace.env` from your current directory upward
- nearest `.android-env` from `--project` upward
- nearest `.android-workspace.env` from `--project` upward
- the tool-local `.android-env`
- `~/.config/android-studio-less-workspace/config.env`

For project-local config, the recommended flow is now:

```bash
cd <android-project-dir>
androidws app-info
androidws setup
```

That will detect the app module, application id, launcher activity, and write
`./.android-env` for the project.

### Create a new project

```bash
androidws init <android-project-dir> --package com.example.myapp
cd <android-project-dir>
./gradlew :app:assembleDebug
```

The generated project is intentionally close to a current Android Studio Empty
Activity setup:

- Kotlin DSL
- Gradle wrapper
- version catalog in `gradle/libs.versions.toml`
- one `app` module
- Jetpack Compose entry screen
- modern AGP 9.x built-in Kotlin flow

### Work with an existing project

1. Go to the Android project root
2. Run `androidws app-info` to inspect detected app metadata
3. Run `androidws setup` to generate `.android-env`
4. Review `.android-env`
5. Run:

```bash
cd <android-project-dir>
androidws app-info
androidws setup
androidws doctor
androidws devices
androidws build
androidws install
androidws launch
androidws logs
```

You can also skip `.android-env` and pass values inline:

```bash
androidws init <android-project-dir> --package com.example.myapp
androidws --project <android-project-dir> --serial <device-serial> build
androidws --project <android-project-dir> --serial <device-serial> install
androidws --project <android-project-dir> --app-id com.example.myapp launch
androidws --adb-bin /path/to/adb devices
```

## Commands

### `init`

Creates a new Android app project.

Example:

```bash
androidws init <android-project-dir> --package com.example.myapp
```

Useful options:

- `--app-name "My App"`
- `--min-sdk 24`
- `--compile-sdk 36`
- `--target-sdk 36`
- `--agp 9.1.0`
- `--gradle 9.3.1`

### `doctor`

Prints detected Java, SDK, adb, Gradle, device list, and project config.

### `app-info`

Prints detected project metadata from the current Android app, including:

- app module
- application id
- namespace
- launcher activity
- detected variants
- connected device serial when exactly one device is attached

Use this to double-check what the tool inferred before writing config.

### `setup`

Detects project metadata and writes `./.android-env` in the current project
root.

It prints the detected values again after writing so you can verify:

- `APP_ID`
- `LAUNCH_ACTIVITY`
- `BUILD_VARIANT`
- `ADB_SERIAL`

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
androidws logs ActivityManager:I '*:S'
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
