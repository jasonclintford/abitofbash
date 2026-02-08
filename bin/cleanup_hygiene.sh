#!/usr/bin/env bash
set -euo pipefail

TOOL_NAME="cleanup_hygiene"
TOOL_VERSION="0.1.0"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: cleanup_hygiene.sh [options]

Purpose: Disk cleanup with guardrails.

Options:
  --include <pattern>  Include glob pattern (repeatable).
  --exclude <pattern>  Exclude glob pattern (repeatable).
  --force              Allow cleanup outside allowlist.
  --help               Show help.
  --version            Show version.
  --dry-run            Show actions without deleting.
  --verbose            Verbose logging.
  --quiet              Suppress non-essential output.
  --json               Emit JSON output only.
  --config <path>      Load config file.
  --log-file <path>    Override log file path.
  --output-dir <dir>   Place artifacts in directory.

Examples:
  cleanup_hygiene.sh --include "*.log" --exclude "*keep*"
  cleanup_hygiene.sh --force --include "*.tmp"
USAGE
}

timestamp() {
  date -u +"%Y%m%dT%H%M%SZ"
}

parse_flags() {
  INCLUDES=()
  EXCLUDES=()
  FORCE=0

  parse_common_flags "$@"
  set -- "${REMAINING_ARGS[@]}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --include)
        shift
        INCLUDES+=("$1")
        ;;
      --exclude)
        shift
        EXCLUDES+=("$1")
        ;;
      --force)
        FORCE=1
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

matches_exclude() {
  local file=$1
  local pat
  for pat in "${EXCLUDES[@]}"; do
    if [[ "$file" == $pat ]]; then
      return 0
    fi
  done
  return 1
}

main() {
  parse_flags "$@"
  init_log_file "$TOOL_NAME"
  OUTPUT_DIR=$(ensure_output_dir "$OUTPUT_DIR")

  require_cmd "du"
  require_cmd "find"
  require_cmd "rm"

  local allowlist=("/var/log" "/tmp" "/var/tmp" "$HOME")
  local targets=()
  if [[ ${#INCLUDES[@]} -eq 0 ]]; then
    INCLUDES=("*.log" "*.tmp" "*.bak" "*.old")
  fi

  local base
  for base in "${allowlist[@]}"; do
    if [[ -d "$base" ]]; then
      targets+=("$base")
    fi
  done

  if [[ $FORCE -eq 1 ]]; then
    targets=("/")
  fi

  local ts
  ts=$(timestamp)
  local report="$OUTPUT_DIR/${TOOL_NAME}_estimate_${ts}.txt"

  local total=0
  local file
  while IFS= read -r -d '' file; do
    if matches_exclude "$file"; then
      continue
    fi
    local size
    size=$(du -b "$file" | awk '{print $1}')
    total=$((total + size))
  done < <(find "${targets[@]}" -type f \( $(printf -- '-name %q -o ' "${INCLUDES[@]}") -false \) -print0 2>/dev/null)

  printf 'Estimated reclaimable bytes: %s\n' "$total" >"$report"
  log_info "Estimate saved to $report"

  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run enabled; no files deleted."
  else
    while IFS= read -r -d '' file; do
      if matches_exclude "$file"; then
        continue
      fi
      rm -f "$file"
    done < <(find "${targets[@]}" -type f \( $(printf -- '-name %q -o ' "${INCLUDES[@]}") -false \) -print0 2>/dev/null)
  fi

  if [[ $JSON -eq 1 ]]; then
    printf '{"status":"ok","estimate_bytes":%s,"report":"%s"}\n' "$total" "$(json_escape "$report")"
  else
    echo "Cleanup complete. Estimated bytes: $total"
  fi
}

main "$@"
