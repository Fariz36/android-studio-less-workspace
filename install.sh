#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
GLOBAL_CONFIG_DIR="${HOME}/.config/android-studio-less-workspace"
GLOBAL_CONFIG_PATH="${GLOBAL_CONFIG_DIR}/config.env"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
COMPLETION_DIR="${XDG_DATA_HOME}/bash-completion/completions"

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

print_shell_init() {
  local target_name="${1:-androidws}"
  local target_path="${BIN_DIR}/${target_name}"
  local completion_path="${COMPLETION_DIR}/${target_name}"

  cat <<EOF
export PATH="${BIN_DIR}:\$PATH"
if [[ -x "${target_path}" ]]; then
  hash -r 2>/dev/null || true
fi
if [[ -f "${completion_path}" ]]; then
  source "${completion_path}"
fi
EOF
}

install_completion() {
  local target_name="${1:-androidws}"
  local completion_path="${COMPLETION_DIR}/${target_name}"

  mkdir -p "$COMPLETION_DIR"
  "${SCRIPT_DIR}/android" completion bash | sed "s/complete -F _androidws_completion androidws$/complete -F _androidws_completion ${target_name}/" >"$completion_path"

  cat <<EOF
Installed bash completion:
  file: $completion_path

Enable it in the current shell:
  source "$completion_path"

Persist it if your shell does not auto-load ~/.local/share/bash-completion/completions:
  echo 'source "$completion_path"' >> ~/.bashrc
EOF
}

check_completion() {
  local target_name="${1:-androidws}"
  local completion_path="${COMPLETION_DIR}/${target_name}"

  if [[ -f "$completion_path" ]]; then
    printf 'found\n'
    printf 'completion=%s\n' "$completion_path"
    return 0
  fi

  printf 'not_found\n'
  printf 'completion=%s\n' "$completion_path"
  return 1
}

if [[ "${1:-}" == "--check" ]]; then
  check_install "${2:-androidws}"
  exit $?
fi

if [[ "${1:-}" == "--install-completion" ]]; then
  install_completion "${2:-androidws}"
  exit 0
fi

if [[ "${1:-}" == "--shell-init" ]]; then
  print_shell_init "${2:-androidws}"
  exit 0
fi

if [[ "${1:-}" == "--check-completion" ]]; then
  check_completion "${2:-androidws}"
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
  1. Run: ./install.sh --install-completion $TARGET_NAME
  2. Run: source <(./install.sh --shell-init $TARGET_NAME)
  3. Run: ./install.sh --check $TARGET_NAME
  4. Edit $GLOBAL_CONFIG_PATH if you want global defaults
  5. Run: $TARGET_NAME doctor

Per-project config:
  Put .android-env in your Android project root and the command will auto-load it
  when run from anywhere inside that project tree.
EOF
