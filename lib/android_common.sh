#!/usr/bin/env bash

set -euo pipefail

CLI_PROJECT_DIR=""
CLI_APP_MODULE=""
CLI_BUILD_VARIANT=""
CLI_ADB_SERIAL=""
CLI_APP_ID=""
CLI_LAUNCH_ACTIVITY=""
CLI_ADB_BIN=""
COMMAND=""

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'warn: %s\n' "$*" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

canonical_path() {
  local path="$1"
  if [[ -d "$path" ]]; then
    cd "$path" >/dev/null 2>&1 && pwd
  elif [[ -e "$path" ]]; then
    cd "$(dirname "$path")" >/dev/null 2>&1 && printf '%s/%s\n' "$(pwd)" "$(basename "$path")"
  else
    return 1
  fi
}

detect_project_dir() {
  local start current

  if [[ -n "${CLI_PROJECT_DIR:-}" ]]; then
    canonical_path "$CLI_PROJECT_DIR"
    return
  fi

  if [[ -n "${PROJECT_DIR:-}" ]]; then
    canonical_path "$PROJECT_DIR"
    return
  fi

  start="$(pwd)"
  current="$start"
  while [[ "$current" != "/" ]]; do
    if [[ -f "$current/gradlew" || -f "$current/settings.gradle" || -f "$current/settings.gradle.kts" ]]; then
      printf '%s\n' "$current"
      return
    fi
    current="$(dirname "$current")"
  done
}

detect_android_sdk_root() {
  local candidate
  local -a candidates=()

  if [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
    candidates+=("$ANDROID_SDK_ROOT")
  fi
  if [[ -n "${ANDROID_HOME:-}" ]]; then
    candidates+=("$ANDROID_HOME")
  fi
  candidates+=(
    "$HOME/Android/Sdk"
    "/usr/lib/android-sdk"
  )

  shopt -s nullglob
  for candidate in /mnt/c/Users/*/AppData/Local/Android/Sdk; do
    candidates+=("$candidate")
  done
  shopt -u nullglob

  for candidate in "${candidates[@]}"; do
    if [[ -d "$candidate/platform-tools" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
}

find_adb() {
  local sdk_root candidate

  if [[ -n "${ADB_BIN:-}" && -e "${ADB_BIN:-}" ]]; then
    printf '%s\n' "$ADB_BIN"
    return
  fi

  if command -v adb >/dev/null 2>&1; then
    command -v adb
    return
  fi

  sdk_root="$(detect_android_sdk_root || true)"
  for candidate in \
    "$sdk_root/platform-tools/adb" \
    "$sdk_root/platform-tools/adb.exe"
  do
    if [[ -n "$candidate" && -e "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  shopt -s nullglob
  for candidate in /mnt/c/Users/*/AppData/Local/Android/Sdk/platform-tools/adb.exe; do
    if [[ -e "$candidate" ]]; then
      printf '%s\n' "$candidate"
      shopt -u nullglob
      return
    fi
  done
  shopt -u nullglob
}

find_gradle_cmd() {
  if [[ -n "${PROJECT_DIR:-}" && -x "$PROJECT_DIR/gradlew" ]]; then
    printf '%s\n' "$PROJECT_DIR/gradlew"
    return
  fi

  if command -v gradle >/dev/null 2>&1; then
    command -v gradle
    return
  fi
}

detect_latest_compile_sdk() {
  local sdk_root platform latest
  sdk_root="$(detect_android_sdk_root || true)"
  [[ -n "$sdk_root" && -d "$sdk_root/platforms" ]] || return 0

  latest="$(find "$sdk_root/platforms" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sed -n 's/^android-\([0-9][0-9]*\)$/\1/p' | sort -n | tail -n 1)"
  printf '%s\n' "$latest"
}

detect_latest_build_tools_version() {
  local sdk_root latest
  sdk_root="$(detect_android_sdk_root || true)"
  [[ -n "$sdk_root" && -d "$sdk_root/build-tools" ]] || return 0

  latest="$(find "$sdk_root/build-tools" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V | tail -n 1)"
  printf '%s\n' "$latest"
}

adb_cmd() {
  local adb_path
  adb_path="$(find_adb)"
  [[ -n "$adb_path" ]] || die "adb not found. Set ANDROID_SDK_ROOT/ANDROID_HOME or install platform-tools."

  if [[ -n "${ADB_SERIAL:-}" ]]; then
    "$adb_path" -s "$ADB_SERIAL" "$@"
  else
    "$adb_path" "$@"
  fi
}

run_gradle() {
  local gradle_cmd
  gradle_cmd="$(find_gradle_cmd)"
  [[ -n "$gradle_cmd" ]] || die "Gradle not found. Use a project with ./gradlew or install gradle."
  (cd "$PROJECT_DIR" && "$gradle_cmd" "$@")
}

variant_dir_name() {
  printf '%s\n' "$BUILD_VARIANT" | tr '[:upper:]' '[:lower:]'
}

find_apk_path() {
  local module_dir variant_dir apk_path
  module_dir="$PROJECT_DIR/$APP_MODULE"
  variant_dir="$(variant_dir_name)"

  if [[ ! -d "$module_dir/build/outputs/apk" ]]; then
    return 0
  fi

  apk_path="$(find "$module_dir/build/outputs/apk" -type f -name "*${variant_dir}*.apk" | sort | tail -n 1)"
  if [[ -z "$apk_path" ]]; then
    apk_path="$(find "$module_dir/build/outputs/apk" -type f -name '*.apk' | sort | tail -n 1)"
  fi

  printf '%s\n' "$apk_path"
}

load_android_env() {
  local env_file="$SCRIPT_DIR/.android-env"
  if [[ -f "$env_file" ]]; then
    # shellcheck source=/dev/null
    source "$env_file"
  fi
}

apply_cli_overrides() {
  APP_MODULE="${CLI_APP_MODULE:-${APP_MODULE:-app}}"
  BUILD_VARIANT="${CLI_BUILD_VARIANT:-${BUILD_VARIANT:-Debug}}"
  ADB_SERIAL="${CLI_ADB_SERIAL:-${ADB_SERIAL:-}}"
  APP_ID="${CLI_APP_ID:-${APP_ID:-}}"
  LAUNCH_ACTIVITY="${CLI_LAUNCH_ACTIVITY:-${LAUNCH_ACTIVITY:-}}"
  ADB_BIN="${CLI_ADB_BIN:-${ADB_BIN:-}}"
  PROJECT_DIR="$(detect_project_dir || true)"
}

ensure_project() {
  [[ -n "${PROJECT_DIR:-}" ]] || die "No Android Gradle project detected. Pass --project /path/to/project or set PROJECT_DIR in .android-env."
}

require_adb() {
  [[ -n "$(find_adb || true)" ]] || die "adb not found. Set ANDROID_SDK_ROOT/ANDROID_HOME or add adb to PATH."
}

require_app_id() {
  [[ -n "${APP_ID:-}" ]] || die "APP_ID is required. Pass --app-id or set APP_ID in .android-env."
}
