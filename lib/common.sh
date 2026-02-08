#!/usr/bin/env bash
set -euo pipefail

COMMON_VERSION="0.1.0"

VERBOSE=0
QUIET=0
JSON=0
DRY_RUN=0
CONFIG_PATH=""
LOG_FILE=""
OUTPUT_DIR=""
REMAINING_ARGS=()

is_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]]
}

have_systemd() {
  [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1
}

detect_pkg_mgr() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
    return 0
  fi
  if command -v dnf >/dev/null 2>&1; then
    echo "dnf"
    return 0
  fi
  echo ""
  return 1
}

json_escape() {
  local input=${1:-}
  input=${input//\\/\\\\}
  input=${input//"/\\"}
  input=${input//$'\n'/\\n}
  input=${input//$'\r'/\\r}
  input=${input//$'\t'/\\t}
  printf '%s' "$input"
}

json_kv() {
  local key=$1
  local value=$2
  printf '"%s":"%s"' "$(json_escape "$key")" "$(json_escape "$value")"
}

log_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

_log_write() {
  local level=$1
  local message=$2
  local ts
  ts=$(log_timestamp)
  if [[ -n "$LOG_FILE" ]]; then
    printf '%s [%s] %s\n' "$ts" "$level" "$message" >>"$LOG_FILE"
  fi
  if [[ $JSON -eq 0 && $QUIET -eq 0 ]]; then
    printf '%s [%s] %s\n' "$ts" "$level" "$message" >&2
  fi
}

log_info() {
  _log_write "INFO" "$1"
}

log_warn() {
  _log_write "WARN" "$1"
}

log_error() {
  _log_write "ERROR" "$1"
}

die() {
  local message=$1
  local code=${2:-1}
  if [[ $JSON -eq 1 ]]; then
    printf '{"status":"error","message":"%s"}\n' "$(json_escape "$message")"
  else
    log_error "$message"
  fi
  exit "$code"
}

require_cmd() {
  local cmd=$1
  if ! command -v "$cmd" >/dev/null 2>&1; then
    local mgr
    mgr=$(detect_pkg_mgr || true)
    if [[ $JSON -eq 1 ]]; then
      printf '{"status":"error","missing":"%s","hint":"%s"}\n' "$(json_escape "$cmd")" "$(json_escape "Install via ${mgr:-apt|dnf}.")"
    else
      printf 'Missing required command: %s\n' "$cmd" >&2
      printf 'Install hint: apt-get install %s OR dnf install %s\n' "$cmd" "$cmd" >&2
    fi
    exit 3
  fi
}

ensure_output_dir() {
  local dir=$1
  if [[ -z "$dir" ]]; then
    dir="$(pwd)"
  fi
  mkdir -p "$dir"
  printf '%s' "$dir"
}

safe_write_file() {
  local target=$1
  local content=$2
  local dir
  dir=$(dirname "$target")
  mkdir -p "$dir"
  local tmp
  umask 077
  tmp=$(mktemp "${dir}/.tmp.XXXXXX")
  printf '%s' "$content" >"$tmp"
  mv "$tmp" "$target"
}

init_log_file() {
  local toolname=$1
  if [[ -n "$LOG_FILE" ]]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    return 0
  fi
  local log_dir
  if is_root; then
    log_dir="/var/log/${toolname}"
  else
    log_dir="$HOME/.local/state/${toolname}"
  fi
  mkdir -p "$log_dir"
  LOG_FILE="${log_dir}/${toolname}.log"
}

load_config() {
  local path=$1
  if [[ -z "$path" ]]; then
    return 0
  fi
  if [[ ! -f "$path" ]]; then
    die "Config file not found: $path" 2
  fi
  set -a
  # shellcheck disable=SC1090
  . "$path"
  set +a
}

parse_common_flags() {
  local args=("$@")
  REMAINING_ARGS=()
  local i=0
  while [[ $i -lt ${#args[@]} ]]; do
    local arg=${args[$i]}
    case "$arg" in
      --help|--version)
        REMAINING_ARGS+=("$arg")
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      --verbose)
        VERBOSE=1
        QUIET=0
        ;;
      --quiet)
        QUIET=1
        VERBOSE=0
        ;;
      --json)
        JSON=1
        QUIET=1
        ;;
      --config)
        i=$((i+1))
        CONFIG_PATH=${args[$i]:-}
        ;;
      --log-file)
        i=$((i+1))
        LOG_FILE=${args[$i]:-}
        ;;
      --output-dir)
        i=$((i+1))
        OUTPUT_DIR=${args[$i]:-}
        ;;
      --)
        i=$((i+1))
        while [[ $i -lt ${#args[@]} ]]; do
          REMAINING_ARGS+=("${args[$i]}")
          i=$((i+1))
        done
        break
        ;;
      *)
        REMAINING_ARGS+=("$arg")
        ;;
    esac
    i=$((i+1))
  done
  load_config "$CONFIG_PATH"
}
