#!/usr/bin/env bash
set -euo pipefail

TOOL_NAME="yara_fs_scan"
TOOL_VERSION="0.1.0"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: yara_fs_scan.sh [options] --target <dir>

Purpose: Scan filesystem using YARA.

Options:
  --rules-dir <dir>   Rules directory (repeatable).
  --target <dir>      Target directory.
  --skip-defaults     Do not exclude /proc, /sys, /dev.
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
  yara_fs_scan.sh --rules-dir /opt/rules --target /srv
USAGE
}

timestamp() {
  date -u +"%Y%m%dT%H%M%SZ"
}

parse_flags() {
  RULES_DIRS=()
  TARGET=""
  SKIP_DEFAULTS=0

  parse_common_flags "$@"
  set -- "${REMAINING_ARGS[@]}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --rules-dir)
        shift
        RULES_DIRS+=("$1")
        ;;
      --target)
        shift
        TARGET=$1
        ;;
      --skip-defaults)
        SKIP_DEFAULTS=1
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

  require_cmd "yara"
  require_cmd "yarac"
  require_cmd "find"
  require_cmd "sha256sum"
  require_cmd "stat"

  if [[ ${#RULES_DIRS[@]} -eq 0 ]]; then
    if [[ -d /usr/share/yara ]]; then
      RULES_DIRS=("/usr/share/yara")
    else
      die "No rules directory provided and /usr/share/yara not found." 2
    fi
  fi

  local ts
  ts=$(timestamp)
  local cache="$OUTPUT_DIR/${TOOL_NAME}_rules_${ts}.yarac"
  local report="$OUTPUT_DIR/${TOOL_NAME}_${ts}.txt"
  local file_list="$OUTPUT_DIR/${TOOL_NAME}_files_${ts}.txt"

  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run enabled; skipping scan."
  else
    yarac "${RULES_DIRS[@]}" "$cache"
    if [[ $SKIP_DEFAULTS -eq 1 ]]; then
      find "$TARGET" -type f -print >"$file_list"
    else
      find "$TARGET" -type f ! -path "/proc/*" ! -path "/sys/*" ! -path "/dev/*" -print >"$file_list"
    fi
    {
      echo "YARA Scan"
      echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      echo
      while IFS= read -r file; do
        local matches
        matches=$(yara -r "$cache" "$file" 2>/dev/null || true)
        if [[ -n "$matches" ]]; then
          local hash first_seen
          hash=$(sha256sum "$file" | awk '{print $1}')
          first_seen=$(stat -c "%y" "$file" 2>/dev/null || echo "unknown")
          echo "$matches | $hash | $file | first_seen: $first_seen"
        fi
      done <"$file_list"
    } >"$report"
  fi

  if [[ $JSON -eq 1 ]]; then
    printf '{"status":"ok","report":"%s"}\n' "$(json_escape "$report")"
  else
    echo "YARA report saved to $report"
  fi
}

main "$@"
