#!/usr/bin/env bash

set -euo pipefail

CLI_PROJECT_DIR=""
CLI_APP_MODULE=""
CLI_BUILD_VARIANT=""
CLI_ADB_SERIAL=""
CLI_APP_ID=""
CLI_LAUNCH_ACTIVITY=""
CLI_ADB_BIN=""
CLI_ENV_FILE=""
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

find_upward_file() {
  local start name current
  start="$1"
  name="$2"
  current="$start"

  while [[ -n "$current" && "$current" != "/" ]]; do
    if [[ -f "$current/$name" ]]; then
      printf '%s\n' "$current/$name"
      return
    fi
    current="$(dirname "$current")"
  done

  if [[ -f "/$name" ]]; then
    printf '/%s\n' "$name"
  fi
}

trim_whitespace() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
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

project_root_name() {
  if [[ -n "${PROJECT_DIR:-}" ]]; then
    basename "$PROJECT_DIR"
    return
  fi
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

find_project_build_files() {
  [[ -n "${PROJECT_DIR:-}" ]] || return 0
  find "$PROJECT_DIR" -maxdepth 3 \( -name 'build.gradle.kts' -o -name 'build.gradle' \) -type f | sort
}

detect_app_module() {
  local candidate build_file

  if [[ -n "${CLI_APP_MODULE:-}" ]]; then
    printf '%s\n' "$CLI_APP_MODULE"
    return
  fi

  if [[ -n "${APP_MODULE:-}" ]]; then
    printf '%s\n' "$APP_MODULE"
    return
  fi

  if [[ -n "${PROJECT_DIR:-}" && -f "$PROJECT_DIR/app/build.gradle.kts" || -f "$PROJECT_DIR/app/build.gradle" ]]; then
    printf 'app\n'
    return
  fi

  while IFS= read -r build_file; do
    candidate="${build_file#$PROJECT_DIR/}"
    candidate="${candidate%/build.gradle.kts}"
    candidate="${candidate%/build.gradle}"
    if [[ -f "$PROJECT_DIR/$candidate/src/main/AndroidManifest.xml" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done < <(find_project_build_files)
}

module_build_file() {
  local module="${1:-}"
  [[ -n "$module" ]] || return 0

  if [[ -f "$PROJECT_DIR/$module/build.gradle.kts" ]]; then
    printf '%s\n' "$PROJECT_DIR/$module/build.gradle.kts"
    return
  fi

  if [[ -f "$PROJECT_DIR/$module/build.gradle" ]]; then
    printf '%s\n' "$PROJECT_DIR/$module/build.gradle"
    return
  fi
}

module_manifest_file() {
  local module="${1:-}"
  [[ -n "$module" ]] || return 0

  if [[ -f "$PROJECT_DIR/$module/src/main/AndroidManifest.xml" ]]; then
    printf '%s\n' "$PROJECT_DIR/$module/src/main/AndroidManifest.xml"
  fi
}

extract_assignment_value() {
  local file="$1"
  local key="$2"
  [[ -f "$file" ]] || return 0

  sed -n "s/^[[:space:]]*$key[[:space:]]*=[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$file" | head -n 1
}

extract_manifest_package_name() {
  local manifest="$1"
  [[ -f "$manifest" ]] || return 0
  sed -n 's/.*package="\([^"]*\)".*/\1/p' "$manifest" | head -n 1
}

extract_launcher_activity() {
  local manifest="$1"
  python3 - <<'PY' "$manifest"
import sys
import xml.etree.ElementTree as ET

manifest_path = sys.argv[1]
android_ns = "{http://schemas.android.com/apk/res/android}"

try:
    root = ET.parse(manifest_path).getroot()
except Exception:
    sys.exit(0)

application = root.find("application")
if application is None:
    sys.exit(0)

for activity_tag in ("activity", "activity-alias"):
    for activity in application.findall(activity_tag):
        name = activity.attrib.get(android_ns + "name", "")
        if not name:
            continue
        for intent_filter in activity.findall("intent-filter"):
            actions = {item.attrib.get(android_ns + "name", "") for item in intent_filter.findall("action")}
            categories = {item.attrib.get(android_ns + "name", "") for item in intent_filter.findall("category")}
            if "android.intent.action.MAIN" in actions and "android.intent.category.LAUNCHER" in categories:
                print(name)
                sys.exit(0)
PY
}

extract_build_variants() {
  local build_file="$1"
  [[ -f "$build_file" ]] || return 0
  python3 - <<'PY' "$build_file"
import re
import sys

text = open(sys.argv[1], "r", encoding="utf-8").read()
start = re.search(r'buildTypes\s*\{', text)
variants = []
if start:
    i = start.end()
    depth = 1
    body_chars = []
    while i < len(text) and depth > 0:
        ch = text[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                break
        body_chars.append(ch)
        i += 1
    body = "".join(body_chars)
    variants = re.findall(r'^\s*([A-Za-z0-9_]+)\s*\{', body, re.M)

if not variants:
    variants = ["debug", "release"]
elif "debug" not in variants:
    variants = ["debug"] + variants

for item in dict.fromkeys(variants):
    print(item)
PY
}

detect_application_id() {
  local module build_file manifest value
  module="${1:-$(detect_app_module || true)}"
  build_file="$(module_build_file "$module")"
  manifest="$(module_manifest_file "$module")"

  value="$(extract_assignment_value "$build_file" 'applicationId')"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return
  fi

  value="$(extract_assignment_value "$build_file" 'namespace')"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return
  fi

  extract_manifest_package_name "$manifest"
}

detect_namespace() {
  local module build_file
  module="${1:-$(detect_app_module || true)}"
  build_file="$(module_build_file "$module")"
  extract_assignment_value "$build_file" 'namespace'
}

detect_launcher_activity() {
  local module manifest app_id activity
  module="${1:-$(detect_app_module || true)}"
  manifest="$(module_manifest_file "$module")"
  activity="$(extract_launcher_activity "$manifest")"
  [[ -n "$activity" ]] || return 0

  if [[ "$activity" == .* ]]; then
    printf '%s\n' "$activity"
    return
  fi

  app_id="$(detect_application_id "$module")"
  if [[ -n "$app_id" && "$activity" == "$app_id"* ]]; then
    printf '.%s\n' "${activity#"$app_id."}"
    return
  fi

  printf '%s\n' "$activity"
}

detect_connected_device_serial() {
  local adb_path devices
  adb_path="$(find_adb || true)"
  [[ -n "$adb_path" ]] || return 0

  devices="$("$adb_path" devices 2>/dev/null | awk 'NR > 1 && $2 == "device" { print $1 }')"
  if [[ "$(printf '%s\n' "$devices" | sed '/^$/d' | wc -l)" -eq 1 ]]; then
    printf '%s\n' "$devices" | sed '/^$/d'
  fi
}

print_detected_app_info() {
  local module build_file manifest app_id namespace activity variants serial
  module="$(detect_app_module || true)"
  build_file="$(module_build_file "$module")"
  manifest="$(module_manifest_file "$module")"
  app_id="$(detect_application_id "$module" || true)"
  namespace="$(detect_namespace "$module" || true)"
  activity="$(detect_launcher_activity "$module" || true)"
  serial="$(detect_connected_device_serial || true)"

  printf 'project_dir=%s\n' "${PROJECT_DIR:-}"
  printf 'project_name=%s\n' "$(project_root_name || true)"
  printf 'app_module=%s\n' "$module"
  printf 'build_file=%s\n' "$build_file"
  printf 'manifest=%s\n' "$manifest"
  printf 'application_id=%s\n' "$app_id"
  printf 'namespace=%s\n' "$namespace"
  printf 'launch_activity=%s\n' "$activity"
  printf 'detected_device_serial=%s\n' "$serial"
  printf 'variants='
  variants="$(extract_build_variants "$build_file" | paste -sd, -)"
  printf '%s\n' "$variants"
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

read_project_sdk_dir() {
  local local_props sdk_dir
  local_props="$PROJECT_DIR/local.properties"
  [[ -f "$local_props" ]] || return 0

  sdk_dir="$(sed -n 's/^sdk\.dir=//p' "$local_props" | head -n 1)"
  printf '%s\n' "$sdk_dir"
}

gradle_install_supported() {
  local sdk_root
  sdk_root="$(read_project_sdk_dir || true)"
  if [[ -z "$sdk_root" ]]; then
    sdk_root="$(detect_android_sdk_root || true)"
  fi

  [[ -n "$sdk_root" ]] || return 0

  if [[ -x "$sdk_root/platform-tools/adb" ]]; then
    return 0
  fi

  if [[ -e "$sdk_root/platform-tools/adb.exe" && ! -e "$sdk_root/platform-tools/adb" ]]; then
    return 1
  fi

  return 0
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
  local env_file candidate

  if [[ -n "${CLI_ENV_FILE:-}" ]]; then
    env_file="$(canonical_path "$CLI_ENV_FILE" || true)"
    [[ -n "$env_file" ]] || die "Env file not found: $CLI_ENV_FILE"
    # shellcheck source=/dev/null
    source "$env_file"
    return
  fi

  if [[ -n "${ANDROID_WORKSPACE_ENV_FILE:-}" ]]; then
    env_file="$(canonical_path "$ANDROID_WORKSPACE_ENV_FILE" || true)"
    [[ -n "$env_file" ]] || die "Env file not found: $ANDROID_WORKSPACE_ENV_FILE"
    # shellcheck source=/dev/null
    source "$env_file"
    return
  fi

  for candidate in \
    "$(find_upward_file "$PWD" ".android-env" || true)" \
    "$(find_upward_file "$PWD" ".android-workspace.env" || true)" \
    "$(find_upward_file "${CLI_PROJECT_DIR:-}" ".android-env" || true)" \
    "$(find_upward_file "${CLI_PROJECT_DIR:-}" ".android-workspace.env" || true)" \
    "$SCRIPT_DIR/.android-env" \
    "$HOME/.config/android-studio-less-workspace/config.env"
  do
    if [[ -n "$candidate" && -f "$candidate" ]]; then
      # shellcheck source=/dev/null
      source "$candidate"
      return
    fi
  done
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
