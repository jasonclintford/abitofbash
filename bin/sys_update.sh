#!/usr/bin/env bash
set -euo pipefail

TOOL_NAME="sys_update"
TOOL_VERSION="0.1.0"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: sys_update.sh [options]

Purpose: Safe OS update wrapper with snapshots.

Options:
  --security-only    Best-effort security updates only.
  --reboot           Prompt to reboot after updates (use --yes to skip prompt).
  --yes              Assume yes for package manager prompts.
  --help             Show this help.
  --version          Show version.
  --dry-run          Show actions without applying changes.
  --verbose          Verbose logging.
  --quiet            Suppress non-essential output.
  --json             Emit JSON output only.
  --config <path>    Load config file.
  --log-file <path>  Override log file path.
  --output-dir <dir> Place artifacts in directory.

Examples:
  sys_update.sh --security-only --yes
  sys_update.sh --reboot --output-dir /tmp/update-report
USAGE
}

timestamp() {
  date -u +"%Y%m%dT%H%M%SZ"
}

parse_flags() {
  SECURITY_ONLY=0
  REBOOT=0
  ASSUME_YES=0

  parse_common_flags "$@"
  set -- "${REMAINING_ARGS[@]}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --security-only)
        SECURITY_ONLY=1
        ;;
      --reboot)
        REBOOT=1
        ;;
      --yes)
        ASSUME_YES=1
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

  if ! is_root; then
    die "Must run as root." 4
  fi

  require_cmd "date"
  require_cmd "tee"

  local pkg_mgr
  pkg_mgr=$(detect_pkg_mgr)
  if [[ -z "$pkg_mgr" ]]; then
    die "No supported package manager found (apt or dnf)." 3
  fi

  local ts
  ts=$(timestamp)
  local pre_snapshot="$OUTPUT_DIR/${TOOL_NAME}_packages_before_${ts}.txt"
  local post_snapshot="$OUTPUT_DIR/${TOOL_NAME}_packages_after_${ts}.txt"
  local pm_log="$OUTPUT_DIR/${TOOL_NAME}_pkgmgr_${ts}.log"

  if [[ $pkg_mgr == "apt" ]]; then
    require_cmd "dpkg-query"
    dpkg-query -W -f='${binary:Package}\t${Version}\n' | sort >"$pre_snapshot"
  else
    require_cmd "rpm"
    rpm -qa | sort >"$pre_snapshot"
  fi
  log_info "Captured pre-update package snapshot: $pre_snapshot"

  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run enabled; skipping updates."
  else
    if [[ $pkg_mgr == "apt" ]]; then
      require_cmd "apt-get"
      local args=("update")
      apt-get update | tee -a "$pm_log" >/dev/null
      args=("upgrade")
      if [[ $SECURITY_ONLY -eq 1 ]]; then
        args=("upgrade" "-s")
      fi
      if [[ $ASSUME_YES -eq 1 ]]; then
        args+=("-y")
      fi
      apt-get "${args[@]}" 2>&1 | tee -a "$pm_log" >/dev/null
    else
      require_cmd "dnf"
      local dnf_args=("upgrade")
      if [[ $SECURITY_ONLY -eq 1 ]]; then
        dnf_args+=("--security")
      fi
      if [[ $ASSUME_YES -eq 1 ]]; then
        dnf_args+=("-y")
      fi
      dnf "${dnf_args[@]}" 2>&1 | tee -a "$pm_log" >/dev/null
    fi
  fi

  if [[ $pkg_mgr == "apt" ]]; then
    dpkg-query -W -f='${binary:Package}\t${Version}\n' | sort >"$post_snapshot"
  else
    rpm -qa | sort >"$post_snapshot"
  fi
  log_info "Captured post-update package snapshot: $post_snapshot"

  if [[ $REBOOT -eq 1 ]]; then
    if [[ $ASSUME_YES -eq 1 ]]; then
      log_info "Reboot requested with --yes."
      systemctl reboot || log_warn "Reboot failed or systemctl unavailable."
    else
      read -r -p "Reboot now? [y/N] " answer
      if [[ $answer =~ ^[Yy]$ ]]; then
        systemctl reboot || log_warn "Reboot failed or systemctl unavailable."
      else
        log_info "Reboot skipped by user."
      fi
    fi
  fi

  if [[ $JSON -eq 1 ]]; then
    printf '{"status":"ok","pre_snapshot":"%s","post_snapshot":"%s","pkgmgr_log":"%s"}\n' \
      "$(json_escape "$pre_snapshot")" "$(json_escape "$post_snapshot")" "$(json_escape "$pm_log")"
  else
    echo "Update complete. Snapshots saved to $OUTPUT_DIR"
  fi
}

main "$@"
