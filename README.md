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
- Pair and connect an Android 11+ physical device over wireless adb
- Run common build/install/launch sequences with single commands
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
- Wireless debugging enabled on the target device for Android 11+ wireless use

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

## Quick Start

Existing project, minimal path:

```bash
cd <android-project-dir>
androidws setup
androidws run
```

Existing project, wireless device:

```bash
cd <android-project-dir>
androidws setup
androidws wireless pair --pair-host <phone-ip> --pair-port <pair-port> --pair-code <pair-code>
androidws wireless connect --host <phone-ip> --port <debug-port>
androidws wireless doctor
androidws run
```

If you want VS Code tasks:

```bash
androidws editor-setup vscode
code .
```

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

## Common Workflows

Fast inner loop:

```bash
androidws run
```

Build and install only:

```bash
androidws sync
```

Interactive menu:

```bash
androidws menu
```

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
androidws device current
androidws wireless status
androidws wireless doctor
androidws build
androidws install
androidws launch
androidws run
androidws sync
androidws logs
```

You can also pass everything inline without a local config file:

```bash
androidws --project <android-project-dir> --serial <device-serial> build
androidws --project <android-project-dir> --serial <device-serial> install
androidws --project <android-project-dir> --app-id com.example.myapp launch
androidws --adb-bin /path/to/adb devices
```

### Wireless debugging on a real device

For Android 11 and newer, `androidws` supports the official adb wireless
debugging flow for a physical device on the same Wi-Fi network.

1. Enable Developer options and Wireless debugging on the phone.
2. Keep the workstation and phone on the same Wi-Fi network.
3. On the phone, open Wireless debugging and choose `Pair device with pairing code`.
4. Run:

```bash
androidws wireless pair --pair-host <phone-ip> --pair-port <pair-port> --pair-code <pair-code>
```

5. Then connect to the current debugging endpoint:

```bash
androidws wireless connect --host <phone-ip> --port <debug-port>
```

6. Use the normal workflow:

```bash
androidws run
androidws install
androidws logs
```

If the debugging endpoint changes or the device does not reconnect
automatically, run `androidws wireless connect` again with the current
`<debug-port>`.

Use `androidws wireless doctor` when the workflow is not behaving as expected.
It reports the selected serial, connected wireless devices, and the next action
to take when adb is missing, no wireless device is selected, a wireless device
is reachable but not connected, or the saved endpoint is unreachable.

If project-local `.android-env` already exists, `androidws wireless connect`
updates `ADB_SERIAL` there so later commands keep targeting the same device.
If the file does not exist yet, the connection still works for the current adb
session and `androidws` tells you to run `androidws setup` before reconnecting
to persist it.

Depending on the network and mDNS availability, paired devices may reconnect
automatically, or you may still need a manual `adb connect` step.

### Explicit device selection

If you have multiple devices connected, pin the active one in `.android-env`:

```bash
androidws device use <serial>
androidws device current
```

You can use either a USB serial such as `2a8df356` or a wireless endpoint such
as `192.168.0.5:41287`.

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

If you need to refresh tasks after updates, remove the file and re-run:

```bash
rm .vscode/tasks.json
androidws editor-setup vscode
```

The VS Code task list includes:

- `androidws: build`
- `androidws: doctor`
- `androidws: install`
- `androidws: launch`
- `androidws: run`
- `androidws: sync`
- `androidws: logs`
- `androidws: wireless doctor`
- `androidws: wireless status`
- `androidws: wireless pair`
- `androidws: wireless connect`
- `androidws: wireless run`

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

The generated VS Code tasks include prompts for wireless host, port, and pairing
code so you can pair, connect, run diagnostics, and execute a sequential
`androidws: wireless run` flow without editing `tasks.json` manually.

### `device`

Manage the selected adb serial.

Pin a device:

```bash
androidws device use <serial>
```

Show the configured serial and connected devices:

```bash
androidws device current
```

### `wireless`

Manage Android 11+ wireless adb device flows.

Pair with a pairing code:

```bash
androidws wireless pair --pair-host <phone-ip> --pair-port <pair-port> --pair-code <pair-code>
```

Connect to the current wireless debugging endpoint:

```bash
androidws wireless connect --host <phone-ip> --port <debug-port>
```

Inspect the configured serial and connected wireless endpoints:

```bash
androidws wireless status
```

Run targeted diagnostics for wireless setup problems:

```bash
androidws wireless doctor
```

Disconnect a wireless endpoint:

```bash
androidws wireless disconnect
androidws wireless disconnect --serial <phone-ip>:<debug-port>
```

### `run`

Build, install, and launch.

```bash
androidws run
```

### `sync`

Build and install only.

```bash
androidws sync
```

### `menu`

Interactive menu for common actions.

```bash
androidws menu
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
- `androidws wireless <TAB>`

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
