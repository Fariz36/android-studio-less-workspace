# Android Studio Less Workspace

`androidws` is a lightweight command-line workflow for Android development
without relying on Android Studio for the daily edit, build, install, and log
cycle.

It is intended for developers who prefer:

- editing in a general-purpose editor
- using a physical device instead of an emulator
- running build and deployment tasks from the terminal

## Capabilities

- Create a new Android project with a modern Android Studio style layout
- Detect metadata from an existing Gradle-based Android application
- Build, install, launch, and inspect an app from the command line
- Work from any directory inside a project tree after setup
- Provide Bash completion for the installed command

## Repository Contents

- `android`: main command entrypoint
- `install.sh`: installer and shell integration helper
- `lib/android_common.sh`: shared detection and runtime helpers
- `lib/android_init.sh`: project generator
- `.android-env.example`: example configuration file

## Prerequisites

- Java installed and available on `PATH`
- Android SDK platform-tools available in WSL or Windows
- USB debugging enabled on the target Android device

## Installation

### Fastest setup for the current shell

Run the following from the repository root:

```bash
chmod +x android install.sh
./install.sh
./install.sh --install-completion
source <(./install.sh --shell-init)
```

After this, `androidws` should be available immediately in the current shell.

### Verify installation

```bash
./install.sh --check
./install.sh --check-completion
androidws help
```

You can also verify the resolved command path directly:

```bash
command -v androidws
type -a androidws
```

### Persistent shell setup

If you want `androidws` and its completion available in future shells, add the
equivalent shell initialization to `~/.bashrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
source ~/.local/share/bash-completion/completions/androidws
```

Then reload your shell:

```bash
source ~/.bashrc
```

### Custom command name

You can install the tool under a different command name:

```bash
./install.sh myandroid
./install.sh --install-completion myandroid
source <(./install.sh --shell-init myandroid)
```

## Configuration Resolution

Configuration is resolved in the following order:

- `--env-file /path/to/file`
- `ANDROID_WORKSPACE_ENV_FILE`
- nearest `.android-env` from the current directory upward
- nearest `.android-workspace.env` from the current directory upward
- nearest `.android-env` from `--project` upward
- nearest `.android-workspace.env` from `--project` upward
- the tool-local `.android-env`
- `~/.config/android-studio-less-workspace/config.env`

The default global configuration file is:

```bash
~/.config/android-studio-less-workspace/config.env
```

## Recommended Project Setup

For an existing Android project:

```bash
cd <android-project-dir>
androidws app-info
androidws setup
```

This inspects the project, detects key metadata, and writes a project-local
`.android-env` file.

The `setup` output is intended to be reviewed. In particular, verify:

- `APP_ID`
- `LAUNCH_ACTIVITY`
- `BUILD_VARIANT`
- `ADB_SERIAL`

## Usage

### Create a new project

```bash
androidws init <android-project-dir> --package com.example.myapp
cd <android-project-dir>
./gradlew :app:assembleDebug
```

The generated project is intentionally close to a contemporary Android Studio
Empty Activity structure:

- Kotlin DSL
- Gradle wrapper
- version catalog in `gradle/libs.versions.toml`
- single `app` module
- Jetpack Compose entry screen
- AGP 9.x built-in Kotlin flow

### Work with an existing project

Recommended sequence:

1. Go to the Android project root.
2. Run `androidws app-info`.
3. Run `androidws setup`.
4. Run `androidws editor-setup vscode`.
5. Review the generated `.android-env`.
6. Use the daily commands below.

```bash
cd <android-project-dir>
androidws app-info
androidws setup
androidws editor-setup vscode
androidws doctor
androidws devices
androidws build
androidws install
androidws launch
androidws logs
```

You can also pass everything inline without a local config file:

```bash
androidws --project <android-project-dir> --serial <device-serial> build
androidws --project <android-project-dir> --serial <device-serial> install
androidws --project <android-project-dir> --app-id com.example.myapp launch
androidws --adb-bin /path/to/adb devices
```

### VS Code integration

Generate VS Code task integration on demand:

```bash
cd <android-project-dir>
androidws setup
androidws editor-setup vscode
code .
```

This writes:

```bash
.vscode/tasks.json
```

The generated tasks call `androidws` directly and assume it is already installed
and available on `PATH`.

The generator is safe by default:

- it creates `.vscode/` if needed
- it writes `.vscode/tasks.json` only if the file does not already exist
- it refuses to overwrite an existing `.vscode/tasks.json`

## Command Reference

### `init`

Create a new Android application project.

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

### `setup`

Detect project metadata and write `./.android-env` in the current project root.

### `app-info`

Print detected project metadata from the current Android application, including:

- app module
- application ID
- namespace
- launcher activity
- detected variants
- connected device serial when exactly one device is attached

### `completion`

Print a shell completion script.

Example:

```bash
androidws completion bash
```

### `editor-setup`

Generate editor integration files.

Currently supported:

```bash
androidws editor-setup vscode
```

### `doctor`

Print detected Java, SDK, adb, Gradle, device list, and active project config.

### `devices`

Equivalent to `adb devices`.

### `tasks`

Run `./gradlew tasks --all`.

### `build`

Run the configured Gradle assemble task, for example:

```bash
./gradlew :app:assembleDebug
```

### `install`

Attempt Gradle installation first:

```bash
./gradlew :app:installDebug
```

If that is not supported in the current WSL layout, `androidws` falls back to
`adb install -r` using the newest detected APK.

### `launch`

- If `LAUNCH_ACTIVITY` is set, run `adb shell am start -n ...`
- Otherwise use `adb shell monkey` with the package name

### `logs`

Run `adb logcat`. Extra arguments are passed through:

```bash
androidws logs ActivityManager:I '*:S'
```

### `clean`

Run `./gradlew clean`.

### `apk-path`

Print the detected APK path for the current module and variant.

## Bash Completion

Install completion:

```bash
./install.sh --install-completion
```

Load completion into the current shell:

```bash
source <(./install.sh --shell-init)
```

Completion should then work for:

- `androidws <TAB>`
- `androidws --<TAB>`
- `androidws completion <TAB>`
- `androidws init <TAB>`

## WSL Notes

In many WSL environments, `adb` is installed on Windows rather than Linux. The
tool attempts to detect common SDK locations automatically, including:

- `$ANDROID_SDK_ROOT/platform-tools/adb`
- `$ANDROID_HOME/platform-tools/adb`
- `~/Android/Sdk/platform-tools/adb`
- `/mnt/c/Users/*/AppData/Local/Android/Sdk/platform-tools/adb.exe`

If autodetection is not sufficient, set `ADB_BIN` in `.android-env` or provide
`--adb-bin` explicitly.

## Minimal Daily Workflow

A practical minimal workflow is:

- editor: VS Code, Neovim, or another editor
- build: project `gradlew`
- device: physical phone via `adb`
- logs: `adb logcat`
- inspection: `adb shell`, `dumpsys`, `pm`, `am`

That covers the majority of the daily Android development loop without the IDE.
