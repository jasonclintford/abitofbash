#!/usr/bin/env bash
set -euo pipefail

TOOL_NAME="file_integrity_baseline"
TOOL_VERSION="0.1.0"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: file_integrity_baseline.sh [options] --create|--verify --target <dir>

Purpose: Create and verify a file integrity baseline.

Options:
  --create            Create baseline.
  --verify            Verify baseline.
  --algo <algo>       sha256|sha1|md5 (default sha256).
  --target <dir>      Target directory (repeatable).
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
  file_integrity_baseline.sh --create --target /etc
  file_integrity_baseline.sh --verify --target /etc
USAGE
}

timestamp() {
  date -u +"%Y%m%dT%H%M%SZ"
}

parse_flags() {
  MODE=""
  ALGO="sha256"
  TARGETS=()

  parse_common_flags "$@"
  set -- "${REMAINING_ARGS[@]}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --create)
        MODE="create"
        ;;
      --verify)
        MODE="verify"
        ;;
      --algo)
        shift
        ALGO=$1
        ;;
      --target)
        shift
        TARGETS+=("$1")
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

hash_cmd() {
  case "$ALGO" in
    sha256) echo "sha256sum" ;;
    sha1) echo "sha1sum" ;;
    md5) echo "md5sum" ;;
    *) die "Unsupported algo: $ALGO" 2 ;;
  esac
}

main() {
  parse_flags "$@"
  init_log_file "$TOOL_NAME"
  OUTPUT_DIR=$(ensure_output_dir "$OUTPUT_DIR")

  if [[ -z "$MODE" ]]; then
    die "--create or --verify required" 2
  fi
  if [[ ${#TARGETS[@]} -eq 0 ]]; then
    die "--target required" 2
  fi

  local hc
  hc=$(hash_cmd)
  require_cmd "$hc"
  require_cmd "find"

  local baseline_dir
  if is_root; then
    baseline_dir="/var/lib/${TOOL_NAME}"
  else
    baseline_dir="$HOME/.local/state/${TOOL_NAME}"
  fi
  mkdir -p "$baseline_dir"

  local baseline_file="$baseline_dir/baseline_${ALGO}.txt"
  local ts
  ts=$(timestamp)
  local diff_report="$OUTPUT_DIR/${TOOL_NAME}_diff_${ts}.txt"

  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run enabled; skipping baseline action."
  else
    if [[ $MODE == "create" ]]; then
      umask 077
      : >"$baseline_file"
      for target in "${TARGETS[@]}"; do
        find "$target" -type f -print0 | while IFS= read -r -d '' file; do
          "$hc" "$file" >>"$baseline_file"
        done
      done
    else
      if [[ ! -f "$baseline_file" ]]; then
        die "Baseline not found: $baseline_file" 2
      fi
      "$hc" -c "$baseline_file" >"$diff_report" 2>&1 || true
    fi
  fi

  if [[ $JSON -eq 1 ]]; then
    printf '{"status":"ok","baseline":"%s","diff":"%s"}\n' "$(json_escape "$baseline_file")" "$(json_escape "$diff_report")"
  else
    echo "Baseline stored at $baseline_file"
    [[ -f "$diff_report" ]] && echo "Diff report: $diff_report"
  fi
}

main "$@"
