#!/usr/bin/env bash
set -euo pipefail

TOOL_NAME="backup_rsync"
TOOL_VERSION="0.1.0"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: backup_rsync.sh [options] --source <path> --dest <target>

Purpose: Incremental backups with optional encryption.

Options:
  --source <path>          Source path to back up.
  --dest <target>          Destination path or SSH target (user@host:/path).
  --exclude-file <path>    Rsync exclude file.
  --encrypt                Enable encryption at rest.
  --encrypt-tool <tool>    gpg or age (default gpg).
  --recipient <key>        Recipient key id or public key.
  --help                   Show help.
  --version                Show version.
  --dry-run                Show actions without executing.
  --verbose                Verbose logging.
  --quiet                  Suppress non-essential output.
  --json                   Emit JSON output only.
  --config <path>          Load config file.
  --log-file <path>        Override log file path.
  --output-dir <dir>       Place artifacts in directory.

Examples:
  backup_rsync.sh --source /etc --dest /mnt/backup
  backup_rsync.sh --source /home --dest user@host:/backups --encrypt --recipient ABCDEF
USAGE
}

timestamp() {
  date -u +"%Y%m%dT%H%M%SZ"
}

parse_flags() {
  SOURCE=""
  DEST=""
  EXCLUDE_FILE=""
  ENCRYPT=0
  ENCRYPT_TOOL="gpg"
  RECIPIENT=""

  parse_common_flags "$@"
  set -- "${REMAINING_ARGS[@]}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --source)
        shift
        SOURCE=$1
        ;;
      --dest)
        shift
        DEST=$1
        ;;
      --exclude-file)
        shift
        EXCLUDE_FILE=$1
        ;;
      --encrypt)
        ENCRYPT=1
        ;;
      --encrypt-tool)
        shift
        ENCRYPT_TOOL=$1
        ;;
      --recipient)
        shift
        RECIPIENT=$1
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

  if [[ -z "$SOURCE" || -z "$DEST" ]]; then
    die "--source and --dest are required" 2
  fi
  if [[ ! -e "$SOURCE" ]]; then
    die "Source not found: $SOURCE" 2
  fi
  if [[ -n "$EXCLUDE_FILE" && ! -f "$EXCLUDE_FILE" ]]; then
    die "Exclude file not found: $EXCLUDE_FILE" 2
  fi

  require_cmd "rsync"
  require_cmd "tar"

  if [[ $ENCRYPT -eq 1 ]]; then
    if [[ -z "$RECIPIENT" ]]; then
      die "--recipient required for encryption" 2
    fi
    if [[ "$ENCRYPT_TOOL" == "gpg" ]]; then
      require_cmd "gpg"
    elif [[ "$ENCRYPT_TOOL" == "age" ]]; then
      require_cmd "age"
    else
      die "Unsupported encrypt tool: $ENCRYPT_TOOL" 2
    fi
  fi

  local ts
  ts=$(timestamp)
  local snapshot_dir="$OUTPUT_DIR/snapshot_${ts}"
  local log_file="$OUTPUT_DIR/${TOOL_NAME}_${ts}.log"
  local dest_snapshot="$DEST/snapshot_${ts}"

  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run enabled; skipping rsync."
  else
    mkdir -p "$snapshot_dir"
    local rsync_args=("-a" "--numeric-ids" "--delete-delay" "--stats")
    if [[ -n "$EXCLUDE_FILE" ]]; then
      rsync_args+=("--exclude-from=$EXCLUDE_FILE")
    fi
    rsync "${rsync_args[@]}" "$SOURCE" "$snapshot_dir/" 2>&1 | tee "$log_file" >/dev/null
    rsync "${rsync_args[@]}" "$snapshot_dir/" "$dest_snapshot/" 2>&1 | tee -a "$log_file" >/dev/null
  fi

  local artifact="$snapshot_dir"
  if [[ $ENCRYPT -eq 1 && $DRY_RUN -eq 0 ]]; then
    local tarball="$OUTPUT_DIR/backup_${ts}.tar"
    tar -cf "$tarball" -C "$snapshot_dir" .
    if [[ "$ENCRYPT_TOOL" == "gpg" ]]; then
      gpg --batch --yes -r "$RECIPIENT" -o "${tarball}.gpg" -e "$tarball"
      artifact="${tarball}.gpg"
    else
      age -r "$RECIPIENT" -o "${tarball}.age" "$tarball"
      artifact="${tarball}.age"
    fi
    if [[ ! -s "$artifact" ]]; then
      die "Encryption failed or produced empty file." 1
    fi
    rm -f "$tarball"
  fi

  if [[ $JSON -eq 1 ]]; then
    printf '{"status":"ok","snapshot":"%s","artifact":"%s"}\n' "$(json_escape "$snapshot_dir")" "$(json_escape "$artifact")"
  else
    echo "Backup completed. Snapshot: $snapshot_dir"
  fi
}

main "$@"
