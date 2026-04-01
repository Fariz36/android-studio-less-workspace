#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
GLOBAL_CONFIG_DIR="${HOME}/.config/android-studio-less-workspace"
GLOBAL_CONFIG_PATH="${GLOBAL_CONFIG_DIR}/config.env"

check_install() {
  local target_name="${1:-androidws}"
  local resolved

  if ! command -v "$target_name" >/dev/null 2>&1; then
    printf 'not_found\n'
    printf '%s is not on PATH.\n' "$target_name"
    return 1
  fi

  resolved="$(command -v "$target_name")"
  printf 'found\n'
  printf 'command=%s\n' "$target_name"
  printf 'path=%s\n' "$resolved"
}

if [[ "${1:-}" == "--check" ]]; then
  check_install "${2:-androidws}"
  exit $?
fi

TARGET_NAME="${1:-androidws}"
TARGET_PATH="${BIN_DIR}/${TARGET_NAME}"

mkdir -p "$BIN_DIR" "$GLOBAL_CONFIG_DIR"
ln -sfn "${SCRIPT_DIR}/android" "$TARGET_PATH"

if [[ ! -f "$GLOBAL_CONFIG_PATH" ]]; then
  cp "${SCRIPT_DIR}/.android-env.example" "$GLOBAL_CONFIG_PATH"
fi

cat <<EOF
Installed:
  command: $TARGET_PATH -> ${SCRIPT_DIR}/android
  config:  $GLOBAL_CONFIG_PATH

Next:
  1. Ensure ~/.local/bin is on PATH
  2. Edit $GLOBAL_CONFIG_PATH if you want global defaults
  3. Run: ./install.sh --check $TARGET_NAME
  4. Run: $TARGET_NAME doctor

Per-project config:
  Put .android-env in your Android project root and the command will auto-load it
  when run from anywhere inside that project tree.
EOF
