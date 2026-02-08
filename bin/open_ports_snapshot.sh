#!/usr/bin/env bash
set -euo pipefail

TOOL_NAME="open_ports_snapshot"
TOOL_VERSION="0.1.0"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: open_ports_snapshot.sh [options]

Purpose: Snapshot listening ports and diff against previous run.

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
  open_ports_snapshot.sh --output-dir /tmp/ports
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

  require_cmd "ss"
  require_cmd "awk"
  require_cmd "readlink"
  require_cmd "sed"

  local ts
  ts=$(timestamp)
  local snapshot="$OUTPUT_DIR/${TOOL_NAME}_${ts}.txt"
  local report="$OUTPUT_DIR/${TOOL_NAME}_diff_${ts}.txt"

  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run enabled; skipping snapshot."
  else
    ss -tulpenH >"$snapshot"
  fi

  local prev
  prev=$(ls -t "$OUTPUT_DIR"/${TOOL_NAME}_*.txt 2>/dev/null | sed -n '2p' || true)
  if [[ -n "$prev" && $DRY_RUN -eq 0 ]]; then
    local current_list
    local prev_list
    current_list=$(awk '{print $5"|"$7}' "$snapshot" | sort)
    prev_list=$(awk '{print $5"|"$7}' "$prev" | sort)
    {
      echo "New listeners since previous snapshot:"
      comm -13 <(echo "$prev_list") <(echo "$current_list") | while IFS= read -r line; do
        local proc_field pid exe
        proc_field=${line#*|}
        pid=$(echo "$proc_field" | sed -n 's/.*pid=\\([0-9]*\\).*/\\1/p')
        exe=""
        if [[ -n "$pid" && -r "/proc/$pid/exe" ]]; then
          exe=$(readlink -f "/proc/$pid/exe" || true)
        fi
        echo "$line | exe: ${exe:-unknown}"
      done
    } >"$report"
  else
    echo "No previous snapshot to compare." >"$report"
  fi

  if [[ $JSON -eq 1 ]]; then
    printf '{"status":"ok","snapshot":"%s","diff":"%s"}\n' "$(json_escape "$snapshot")" "$(json_escape "$report")"
  else
    echo "Snapshot saved: $snapshot"
    echo "Diff report: $report"
  fi
}

main "$@"
