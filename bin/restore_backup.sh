#!/usr/bin/env bash
set -euo pipefail

TOOL_NAME="restore_backup"
TOOL_VERSION="0.1.0"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: restore_backup.sh [options] --snapshot <path> --dest <path>

Purpose: Guided restore with preview plan.

Options:
  --snapshot <path>  Snapshot directory or archive.
  --dest <path>      Destination restore path.
  --path <subpath>   Subpath within snapshot to restore.
  --force            Apply restore without prompt.
  --help             Show help.
  --version          Show version.
  --dry-run          Show plan only.
  --verbose          Verbose logging.
  --quiet            Suppress non-essential output.
  --json             Emit JSON output only.
  --config <path>    Load config file.
  --log-file <path>  Override log file path.
  --output-dir <dir> Place artifacts in directory.

Examples:
  restore_backup.sh --snapshot /backups/snapshot_20240101 --dest /restore
USAGE
}

timestamp() {
  date -u +"%Y%m%dT%H%M%SZ"
}

parse_flags() {
  SNAPSHOT=""
  DEST=""
  SUBPATH=""
  FORCE=0

  parse_common_flags "$@"
  set -- "${REMAINING_ARGS[@]}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --snapshot)
        shift
        SNAPSHOT=$1
        ;;
      --dest)
        shift
        DEST=$1
        ;;
      --path)
        shift
        SUBPATH=$1
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

main() {
  parse_flags "$@"
  init_log_file "$TOOL_NAME"
  OUTPUT_DIR=$(ensure_output_dir "$OUTPUT_DIR")

  if [[ -z "$SNAPSHOT" || -z "$DEST" ]]; then
    die "--snapshot and --dest are required" 2
  fi
  if [[ ! -d "$SNAPSHOT" ]]; then
    die "Snapshot directory not found: $SNAPSHOT" 2
  fi

  require_cmd "rsync"

  local ts
  ts=$(timestamp)
  local plan="$OUTPUT_DIR/${TOOL_NAME}_plan_${ts}.txt"
  local source_path="$SNAPSHOT"
  if [[ -n "$SUBPATH" ]]; then
    source_path="$SNAPSHOT/$SUBPATH"
  fi

  rsync -a --dry-run --itemize-changes "$source_path/" "$DEST/" >"$plan"

  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run enabled; plan saved to $plan"
  else
    if [[ $FORCE -eq 0 ]]; then
      log_warn "Plan preview saved to $plan"
      read -r -p "Proceed with restore? [y/N] " answer
      if [[ ! $answer =~ ^[Yy]$ ]]; then
        die "Restore cancelled." 1
      fi
    fi
    rsync -a "$source_path/" "$DEST/"
  fi

  if [[ $JSON -eq 1 ]]; then
    printf '{"status":"ok","plan":"%s"}\n' "$(json_escape "$plan")"
  else
    echo "Restore completed. Plan: $plan"
  fi
}

main "$@"
