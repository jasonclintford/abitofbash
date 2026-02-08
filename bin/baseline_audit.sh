#!/usr/bin/env bash
set -euo pipefail

TOOL_NAME="baseline_audit"
TOOL_VERSION="0.1.0"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: baseline_audit.sh [options]

Purpose: Local security baseline checks.

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
  baseline_audit.sh --output-dir /tmp/audit
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

  require_cmd "getent"
  require_cmd "find"

  local ts
  ts=$(timestamp)
  local report="$OUTPUT_DIR/${TOOL_NAME}_${ts}.txt"

  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run enabled; skipping checks."
  else
    {
      echo "Baseline Audit"
      echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      echo
      echo "[INFO] Users"
      getent passwd | cut -d: -f1,3,4
      echo
      echo "[INFO] Groups"
      getent group | cut -d: -f1,3
      echo
      echo "[WARN] World-writable files (bounded scan)"
      echo "Remediation: remove world-writable permissions unless required."
      find /etc /var /home -xdev -type f -perm -0002 2>/dev/null | head -n 200
      echo
      echo "[INFO] SSHD Config"
      echo "Remediation: disable root login and password auth where feasible."
      if [[ -f /etc/ssh/sshd_config ]]; then
        grep -E '^(PermitRootLogin|PasswordAuthentication|AllowUsers|AllowGroups)' /etc/ssh/sshd_config || true
      else
        echo "sshd_config not found"
      fi
      echo
      echo "[INFO] Firewall Status"
      echo "Remediation: ensure firewall is enabled and only required services are allowed."
      if command -v ufw >/dev/null 2>&1; then
        ufw status verbose || true
      elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --state || true
        firewall-cmd --list-all || true
      else
        echo "No firewall tool found"
      fi
      echo
      echo "[INFO] Pending Updates"
      echo "Remediation: apply security updates regularly."
      local mgr
      mgr=$(detect_pkg_mgr || true)
      if [[ $mgr == "apt" ]]; then
        apt-get -s upgrade | grep -E '^Inst' | head -n 50 || true
      elif [[ $mgr == "dnf" ]]; then
        dnf check-update -q || true
      else
        echo "No supported package manager found"
      fi
    } >"$report"
  fi

  if [[ $JSON -eq 1 ]]; then
    printf '{"status":"ok","report":"%s"}\n' "$(json_escape "$report")"
  else
    echo "Baseline audit saved to $report"
  fi
}

main "$@"
