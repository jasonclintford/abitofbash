#!/usr/bin/env bash
set -euo pipefail

TOOL_NAME="disk_health_report"
TOOL_VERSION="0.1.0"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: disk_health_report.sh [options]

Purpose: SMART + filesystem + inode health report.

Options:
  --warn-disk-pct <n>   Warn threshold for disk usage percentage (default 85).
  --warn-inode-pct <n>  Warn threshold for inode usage percentage (default 85).
  --help                Show help.
  --version             Show version.
  --dry-run             Show actions without running commands.
  --verbose             Verbose logging.
  --quiet               Suppress non-essential output.
  --json                Emit JSON output only.
  --config <path>       Load config file.
  --log-file <path>     Override log file path.
  --output-dir <dir>    Place artifacts in directory.

Examples:
  disk_health_report.sh --warn-disk-pct 90
USAGE
}

timestamp() {
  date -u +"%Y%m%dT%H%M%SZ"
}

parse_flags() {
  WARN_DISK=85
  WARN_INODE=85

  parse_common_flags "$@"
  set -- "${REMAINING_ARGS[@]}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --warn-disk-pct)
        shift
        WARN_DISK=$1
        ;;
      --warn-inode-pct)
        shift
        WARN_INODE=$1
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

  require_cmd "df"
  require_cmd "lsblk"
  require_cmd "smartctl"
  require_cmd "awk"
  if ! [[ "$WARN_DISK" =~ ^[0-9]+$ ]] || ! [[ "$WARN_INODE" =~ ^[0-9]+$ ]]; then
    die "Warn thresholds must be numeric." 2
  fi

  local ts
  ts=$(timestamp)
  local md_report="$OUTPUT_DIR/${TOOL_NAME}_${ts}.md"
  local json_report="$OUTPUT_DIR/${TOOL_NAME}_${ts}.json"

  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run enabled; skipping report generation."
  else
    {
      echo "# Disk Health Report"
      echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      echo
      echo "## Filesystem Usage"
      df -h | awk 'NR==1 || $5+0 >= 0 {print}'
      echo
      echo "## Inode Usage"
      df -ih
      echo
      echo "## SMART Summary"
      while read -r name type; do
        if [[ "$type" == "disk" ]]; then
          echo "### /dev/${name}"
          smartctl -H "/dev/${name}" || true
          echo
        fi
      done < <(lsblk -ndo NAME,TYPE)
    } >"$md_report"

    {
      printf '{"generated":"%s","warn_disk_pct":%s,"warn_inode_pct":%s,' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$WARN_DISK" "$WARN_INODE"
      printf '"filesystems":['
      local first=1
      while read -r fs size used avail usep mount; do
        if [[ "$fs" == "Filesystem" ]]; then
          continue
        fi
        local pct=${usep%%%}
        if [[ $first -eq 0 ]]; then
          printf ','
        fi
        first=0
        printf '{"fs":"%s","size":"%s","used":"%s","avail":"%s","use_pct":%s,"mount":"%s"}' \
          "$(json_escape "$fs")" "$(json_escape "$size")" "$(json_escape "$used")" "$(json_escape "$avail")" "$pct" "$(json_escape "$mount")"
      done < <(df -h --output=source,size,used,avail,pcent,target)
      printf '],"inodes":['
      first=1
      while read -r fs inodes iused ifree iusep mount; do
        if [[ "$fs" == "Filesystem" ]]; then
          continue
        fi
        local pct=${iusep%%%}
        if [[ $first -eq 0 ]]; then
          printf ','
        fi
        first=0
        printf '{"fs":"%s","inodes":"%s","used":"%s","free":"%s","use_pct":%s,"mount":"%s"}' \
          "$(json_escape "$fs")" "$(json_escape "$inodes")" "$(json_escape "$iused")" "$(json_escape "$ifree")" "$pct" "$(json_escape "$mount")"
      done < <(df -ih --output=source,inodes,iused,ifree,ipcent,target)
      printf ']}'
    } >"$json_report"
  fi

  if [[ $JSON -eq 1 ]]; then
    printf '{"status":"ok","markdown":"%s","json":"%s"}\n' "$(json_escape "$md_report")" "$(json_escape "$json_report")"
  else
    echo "Reports saved to $OUTPUT_DIR"
  fi
}

main "$@"
