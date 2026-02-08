#!/usr/bin/env bash
set -euo pipefail

TOOL_NAME="net_quickdiag"
TOOL_VERSION="0.1.0"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: net_quickdiag.sh [options]

Purpose: DNS/gateway/latency/routes/interfaces quick diagnostics.

Options:
  --target <host>    Target for ping and TLS check.
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
  net_quickdiag.sh --target example.com
USAGE
}

timestamp() {
  date -u +"%Y%m%dT%H%M%SZ"
}

parse_flags() {
  TARGET=""
  parse_common_flags "$@"
  set -- "${REMAINING_ARGS[@]}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target)
        shift
        TARGET=$1
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

  require_cmd "ip"
  require_cmd "ping"
  require_cmd "ss"
  require_cmd "getent"
  require_cmd "openssl"

  local ts
  ts=$(timestamp)
  local report="$OUTPUT_DIR/${TOOL_NAME}_${ts}.txt"

  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run enabled; skipping diagnostics."
  else
    {
      echo "Network Quick Diagnostics"
      echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      echo
      echo "## Interfaces"
      ip -brief addr
      echo
      echo "## Routes"
      ip route
      echo
      echo "## Listening Sockets"
      ss -tulpen
      if [[ -n "$TARGET" ]]; then
        echo
        echo "## Target: $TARGET"
        getent ahosts "$TARGET" || true
        ping -c 4 -n "$TARGET" || true
        echo | openssl s_client -servername "$TARGET" -connect "$TARGET:443" 2>/dev/null | openssl x509 -noout -dates || true
      fi
    } >"$report"
  fi

  if [[ $JSON -eq 1 ]]; then
    printf '{"status":"ok","report":"%s"}\n' "$(json_escape "$report")"
  else
    echo "Diagnostics saved to $report"
  fi
}

main "$@"
