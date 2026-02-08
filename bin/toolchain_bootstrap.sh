#!/usr/bin/env bash
set -euo pipefail

TOOL_NAME="toolchain_bootstrap"
TOOL_VERSION="0.1.0"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: toolchain_bootstrap.sh [options]

Purpose: Install and verify dependencies for this suite.

Options:
  --yes              Non-interactive install.
  --help             Show help.
  --version          Show version.
  --dry-run          Show actions without executing.
  --verbose          Verbose logging.
  --quiet            Suppress non-essential output.
  --json             Emit JSON output only.
  --config <path>    Load config file.
  --log-file <path>  Override log file path.
  --output-dir <dir> Place artifacts in directory.

Examples:
  toolchain_bootstrap.sh --yes
USAGE
}

parse_flags() {
  ASSUME_YES=0
  parse_common_flags "$@"
  set -- "${REMAINING_ARGS[@]}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --yes)
        ASSUME_YES=1
        ;;
      --help)
        usage
        exit 0
        ;;
      --version)
        echo "$TOOL_VERSION"
        exit 0
        ;;
      *)
        die "Unknown argument: $1" 2
        ;;
    esac
    shift
  done
}

main() {
  parse_flags "$@"
  init_log_file "$TOOL_NAME"
  OUTPUT_DIR=$(ensure_output_dir "$OUTPUT_DIR")

  if ! is_root; then
    die "Must run as root for installation." 4
  fi

  local mgr
  mgr=$(detect_pkg_mgr)
  if [[ -z "$mgr" ]]; then
    die "No supported package manager found." 3
  fi

  local packages=(rsync smartmontools nmap tcpdump yara ripgrep)
  local cmd=("")
  if [[ $mgr == "apt" ]]; then
    cmd=(apt-get install)
    [[ $ASSUME_YES -eq 1 ]] && cmd+=("-y")
  else
    cmd=(dnf install)
    [[ $ASSUME_YES -eq 1 ]] && cmd+=("-y")
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run enabled; skipping installs."
  else
    "${cmd[@]}" "${packages[@]}"
  fi

  local versions="$OUTPUT_DIR/${TOOL_NAME}_versions.txt"
  {
    echo "Versions"
    for tool in rsync smartctl nmap tcpdump yara rg; do
      if command -v "$tool" >/dev/null 2>&1; then
        "$tool" --version 2>&1 | head -n 1
      fi
    done
  } >"$versions"

  if [[ $JSON -eq 1 ]]; then
    printf '{"status":"ok","versions":"%s"}\n' "$(json_escape "$versions")"
  else
    echo "Toolchain installed. Versions file: $versions"
  fi
}

main "$@"
