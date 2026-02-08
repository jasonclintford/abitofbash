#!/usr/bin/env bash
set -euo pipefail

TOOL_NAME="auth_log_hunter"
TOOL_VERSION="0.1.0"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: auth_log_hunter.sh [options]

Purpose: Detect SSH brute force and auth anomalies.

Options:
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
  auth_log_hunter.sh --output-dir /tmp/auth
USAGE
}

timestamp() {
  date -u +"%Y%m%dT%H%M%SZ"
}

parse_flags() {
  parse_common_flags "$@"
  set -- "${REMAINING_ARGS[@]}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
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

  require_cmd "awk"

  local log_file=""
  if [[ -f /var/log/auth.log ]]; then
    log_file="/var/log/auth.log"
  elif [[ -f /var/log/secure ]]; then
    log_file="/var/log/secure"
  else
    die "No auth log found (auth.log or secure)." 3
  fi

  local ts
  ts=$(timestamp)
  local report="$OUTPUT_DIR/${TOOL_NAME}_${ts}.txt"

  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run enabled; skipping log scan."
  else
    {
      echo "Auth Log Hunter"
      echo "Log: $log_file"
      echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      echo
      echo "Time window:"
      head -n 1 "$log_file" | awk '{print $1, $2, $3}' || true
      tail -n 1 "$log_file" | awk '{print $1, $2, $3}' || true
      echo
      echo "Top failed SSH sources:"
      awk '/Failed password/ {print $(NF-3)}' "$log_file" | sort | uniq -c | sort -nr | head -n 10
      echo
      echo "Top invalid users:"
      awk '/Invalid user/ {print $(NF-5)}' "$log_file" | sort | uniq -c | sort -nr | head -n 10
      echo
      echo "Anomaly flags:"
      awk '/Failed password/ {count++} END {print \"Failed password count:\", count+0}' "$log_file"
      awk '/Accepted password/ {count++} END {print \"Accepted password count:\", count+0}' "$log_file"
      echo
      echo "Recent auth failures (last 50):"
      grep -E 'Failed password|Invalid user' "$log_file" | tail -n 50
    } >"$report"
  fi

  if [[ $JSON -eq 1 ]]; then
    printf '{"status":"ok","report":"%s"}\n' "$(json_escape "$report")"
  else
    echo "Auth report saved to $report"
  fi
}

main "$@"
