#!/usr/bin/env bash
set -euo pipefail

TOOL_NAME="pcap_capture_rotate"
TOOL_VERSION="0.1.0"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: pcap_capture_rotate.sh [options]

Purpose: tcpdump capture with rotation and compression.

Options:
  --iface <name>     Interface to capture.
  --auto             Auto-detect interface.
  --filter <bpf>     BPF filter.
  --size-mb <n>      Rotate size in MB (default 50).
  --rotate-mins <n>  Rotate time in minutes (default 10).
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
  pcap_capture_rotate.sh --iface eth0 --filter "port 443"
USAGE
}

timestamp() {
  date -u +"%Y%m%dT%H%M%SZ"
}

parse_flags() {
  IFACE=""
  AUTO=0
  FILTER=""
  SIZE_MB=50
  ROTATE_MINS=10

  parse_common_flags "$@"
  set -- "${REMAINING_ARGS[@]}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --iface)
        shift
        IFACE=$1
        ;;
      --auto)
        AUTO=1
        ;;
      --filter)
        shift
        FILTER=$1
        ;;
      --size-mb)
        shift
        SIZE_MB=$1
        ;;
      --rotate-mins)
        shift
        ROTATE_MINS=$1
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

  require_cmd "tcpdump"
  require_cmd "ip"
  require_cmd "gzip"
  if ! [[ "$SIZE_MB" =~ ^[0-9]+$ ]] || ! [[ "$ROTATE_MINS" =~ ^[0-9]+$ ]]; then
    die "--size-mb and --rotate-mins must be numeric." 2
  fi

  if [[ -z "$IFACE" && $AUTO -eq 0 ]]; then
    die "--iface required unless --auto is set" 2
  fi

  if [[ -z "$IFACE" && $AUTO -eq 1 ]]; then
    IFACE=$(ip route get 1.1.1.1 | awk '{for (i=1;i<=NF;i++) if ($i=="dev") print $(i+1); exit}')
  fi

  local ts
  ts=$(timestamp)
  local base="$OUTPUT_DIR/${TOOL_NAME}_${ts}"
  local rotation=$((ROTATE_MINS * 60))

  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run enabled; tcpdump not started."
  else
    log_info "Starting tcpdump on $IFACE"
    tcpdump -i "$IFACE" -G "$rotation" -C "$SIZE_MB" -w "${base}_%Y%m%dT%H%M%SZ.pcap" ${FILTER:+"$FILTER"}
  fi

  find "$OUTPUT_DIR" -name "${TOOL_NAME}_*.pcap" -type f -mmin +5 -print0 2>/dev/null | while IFS= read -r -d '' file; do
    gzip -f "$file"
  done

  if [[ $JSON -eq 1 ]]; then
    printf '{"status":"ok","output_dir":"%s"}\n' "$(json_escape "$OUTPUT_DIR")"
  else
    echo "Captures stored in $OUTPUT_DIR"
  fi
}

main "$@"
