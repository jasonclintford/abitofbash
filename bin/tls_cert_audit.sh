#!/usr/bin/env bash
set -euo pipefail

TOOL_NAME="tls_cert_audit"
TOOL_VERSION="0.1.0"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: tls_cert_audit.sh [options] --endpoints <file>

Purpose: Audit cert expiry and TLS posture for endpoints.

Options:
  --endpoints <file>  File with host:port per line.
  --warn-days <n>     Warn threshold days remaining (default 14).
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
  tls_cert_audit.sh --endpoints endpoints.txt --warn-days 30
USAGE
}

timestamp() {
  date -u +"%Y%m%dT%H%M%SZ"
}

parse_flags() {
  ENDPOINTS=""
  WARN_DAYS=14

  parse_common_flags "$@"
  set -- "${REMAINING_ARGS[@]}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --endpoints)
        shift
        ENDPOINTS=$1
        ;;
      --warn-days)
        shift
        WARN_DAYS=$1
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

  if [[ -z "$ENDPOINTS" ]]; then
    die "--endpoints is required" 2
  fi
  if [[ ! -f "$ENDPOINTS" ]]; then
    die "Endpoints file not found: $ENDPOINTS" 2
  fi
  if ! [[ "$WARN_DAYS" =~ ^[0-9]+$ ]]; then
    die "--warn-days must be numeric" 2
  fi

  require_cmd "openssl"
  require_cmd "date"

  local ts
  ts=$(timestamp)
  local report="$OUTPUT_DIR/${TOOL_NAME}_${ts}.txt"

  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run enabled; skipping audit."
  else
    {
      echo "TLS Cert Audit"
      echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      echo
      while IFS= read -r endpoint; do
        [[ -z "$endpoint" ]] && continue
        local host=${endpoint%%:*}
        local port=${endpoint##*:}
        local cert
        cert=$(echo | openssl s_client -servername "$host" -connect "$endpoint" 2>/dev/null | openssl x509 -noout -enddate -dates 2>/dev/null || true)
        local enddate
        enddate=$(echo "$cert" | awk -F= '/notAfter/ {print $2}')
        local end_ts
        if [[ -n "$enddate" ]]; then
          end_ts=$(date -d "$enddate" +%s 2>/dev/null || echo 0)
        else
          end_ts=0
        fi
        local now
        now=$(date +%s)
        local days_left=0
        if [[ $end_ts -gt 0 ]]; then
          days_left=$(( (end_ts - now) / 86400 ))
        fi
        local status="OK"
        if [[ $days_left -le $WARN_DAYS ]]; then
          status="WARN"
        fi
        echo "$endpoint | expires: $enddate | days_left: $days_left | status: $status"
      done <"$ENDPOINTS"
    } >"$report"
  fi

  if [[ $JSON -eq 1 ]]; then
    printf '{"status":"ok","report":"%s"}\n' "$(json_escape "$report")"
  else
    echo "TLS audit report saved to $report"
  fi
}

main "$@"
