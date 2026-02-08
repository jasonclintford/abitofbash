#!/usr/bin/env bash
set -euo pipefail

TOOL_NAME="nmap_wrapper"
TOOL_VERSION="0.1.0"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: nmap_wrapper.sh [options] --target <cidr|host>

Purpose: Safe scanning wrapper for lab networks.

Profiles:
  --quick       Fast scan (top ports).
  --default     Default scan (top ports + service detect).
  --full-tcp    Full TCP scan.
  --udp-light   Light UDP scan.

Options:
  --target <t>        Target CIDR or host.
  --aggressive        Increase intensity (requires explicit flag).
  --help              Show help.
  --version           Show version.
  --dry-run           Show actions without executing.
  --verbose           Verbose logging.
  --quiet             Suppress non-essential output.
  --json              Emit JSON output only.
  --config <path>     Load config file.
  --log-file <path>   Override log file path.
  --output-dir <dir>  Place artifacts in directory.

Examples:
  nmap_wrapper.sh --quick --target 192.168.1.0/24
USAGE
}

timestamp() {
  date -u +"%Y%m%dT%H%M%SZ"
}

parse_flags() {
  PROFILE="default"
  TARGET=""
  AGGRESSIVE=0

  parse_common_flags "$@"
  set -- "${REMAINING_ARGS[@]}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --quick)
        PROFILE="quick"
        ;;
      --default)
        PROFILE="default"
        ;;
      --full-tcp)
        PROFILE="full-tcp"
        ;;
      --udp-light)
        PROFILE="udp-light"
        ;;
      --target)
        shift
        TARGET=$1
        ;;
      --aggressive)
        AGGRESSIVE=1
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

  if [[ -z "$TARGET" ]]; then
    die "--target is required" 2
  fi

  require_cmd "nmap"

  local ts
  ts=$(timestamp)
  local base="$OUTPUT_DIR/${TOOL_NAME}_${ts}"
  local gnmap="${base}.gnmap"
  local xml="${base}.xml"
  local summary="${base}.txt"

  local rate_args=("--min-rate" "20" "--max-rate" "100")
  if [[ $AGGRESSIVE -eq 1 ]]; then
    rate_args=("--min-rate" "100" "--max-rate" "500")
  fi

  local profile_args=()
  case "$PROFILE" in
    quick)
      profile_args=("-T3" "--top-ports" "100")
      ;;
    default)
      profile_args=("-T3" "-sV" "--top-ports" "1000")
      ;;
    full-tcp)
      profile_args=("-T3" "-sV" "-p-")
      ;;
    udp-light)
      profile_args=("-T3" "-sU" "--top-ports" "100")
      ;;
  esac

  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run enabled; skipping nmap."
  else
    nmap "${profile_args[@]}" "${rate_args[@]}" -oG "$gnmap" -oX "$xml" "$TARGET" >"$summary"
  fi

  if [[ $JSON -eq 1 ]]; then
    printf '{"status":"ok","gnmap":"%s","xml":"%s","summary":"%s"}\n' \
      "$(json_escape "$gnmap")" "$(json_escape "$xml")" "$(json_escape "$summary")"
  else
    echo "Scan outputs: $gnmap, $xml, $summary"
  fi
}

main "$@"
