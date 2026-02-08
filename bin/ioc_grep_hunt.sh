#!/usr/bin/env bash
set -euo pipefail

TOOL_NAME="ioc_grep_hunt"
TOOL_VERSION="0.1.0"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: ioc_grep_hunt.sh [options] --ioc-file <path>

Purpose: Hunt IOCs across allowlisted log dirs.

Options:
  --ioc-file <path>   File with IOCs (one per line).
  --log-dir <path>    Allowlisted log directory (repeatable).
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
  ioc_grep_hunt.sh --ioc-file iocs.txt --log-dir /var/log
USAGE
}

timestamp() {
  date -u +"%Y%m%dT%H%M%SZ"
}

parse_flags() {
  IOC_FILE=""
  LOG_DIRS=()

  parse_common_flags "$@"
  set -- "${REMAINING_ARGS[@]}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ioc-file)
        shift
        IOC_FILE=$1
        ;;
      --log-dir)
        shift
        LOG_DIRS+=("$1")
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

  if [[ -z "$IOC_FILE" ]]; then
    die "--ioc-file is required" 2
  fi
  if [[ ! -f "$IOC_FILE" ]]; then
    die "IOC file not found: $IOC_FILE" 2
  fi

  require_cmd "rg"
  require_cmd "stat"

  if [[ ${#LOG_DIRS[@]} -eq 0 ]]; then
    LOG_DIRS=("/var/log")
  fi

  local ts
  ts=$(timestamp)
  local report="$OUTPUT_DIR/${TOOL_NAME}_${ts}.txt"

  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run enabled; skipping IOC scan."
  else
    {
      echo "IOC Hunt"
      echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      echo
      while IFS= read -r ioc; do
        [[ -z "$ioc" ]] && continue
        echo "## IOC: $ioc"
        rg -n --color never -S "$ioc" "${LOG_DIRS[@]}" 2>/dev/null | head -n 50 || true
        echo "File metadata:"
        rg -n --color never -S "$ioc" "${LOG_DIRS[@]}" 2>/dev/null | awk -F: '{print $1}' | sort -u | while IFS= read -r hit; do
          stat -c "%n %s %y" "$hit" 2>/dev/null || true
        done
        echo
      done <"$IOC_FILE"
      echo "## Metadata"
      for dir in "${LOG_DIRS[@]}"; do
        stat -c "%n %s %y" "$dir" || true
      done
    } >"$report"
  fi

  if [[ $JSON -eq 1 ]]; then
    printf '{"status":"ok","report":"%s"}\n' "$(json_escape "$report")"
  else
    echo "IOC report saved to $report"
  fi
}

main "$@"
