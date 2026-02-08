#!/usr/bin/env bash
set -euo pipefail

TOOL_NAME="incident_triage_collect"
TOOL_VERSION="0.1.0"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: incident_triage_collect.sh [options]

Purpose: IR collection bundle.

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
  incident_triage_collect.sh --output-dir /tmp/triage
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

  require_cmd "ps"
  require_cmd "ss"
  require_cmd "ip"
  require_cmd "tar"
  require_cmd "sha256sum"

  local ts
  ts=$(timestamp)
  local workdir
  umask 077
  workdir=$(mktemp -d)
  local bundle="$OUTPUT_DIR/${TOOL_NAME}_${ts}.tar.gz"
  local manifest="$OUTPUT_DIR/${TOOL_NAME}_${ts}_manifest.txt"

  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run enabled; skipping collection."
  else
    mkdir -p "$workdir"
    ps auxf >"$workdir/processes.txt"
    ss -tulpen >"$workdir/network_connections.txt"
    ip addr >"$workdir/ip_addr.txt"
    ip route >"$workdir/ip_route.txt"
    getent passwd >"$workdir/users.txt"
    getent group >"$workdir/groups.txt"
    who >"$workdir/who.txt" || true
    last -a | head -n 50 >"$workdir/last_logins.txt" || true
    uname -a >"$workdir/system_info.txt"
    if have_systemd; then
      journalctl -n 200 --no-pager >"$workdir/journal_tail.txt" || true
    fi
    ls -al /etc/cron* >"$workdir/cron_jobs.txt" || true
    ls -al /etc/systemd/system >"$workdir/systemd_units.txt" || true
    if [[ -f /etc/ssh/sshd_config ]]; then
      sed -E 's/(PasswordAuthentication|PermitRootLogin) .*/\1 redacted/' /etc/ssh/sshd_config >"$workdir/sshd_config.txt" || true
    fi

    tar -czf "$bundle" -C "$workdir" .
    sha256sum "$bundle" >"$manifest"
    rm -rf "$workdir"
  fi

  if [[ $JSON -eq 1 ]]; then
    printf '{"status":"ok","bundle":"%s","manifest":"%s"}\n' "$(json_escape "$bundle")" "$(json_escape "$manifest")"
  else
    echo "Triage bundle saved: $bundle"
  fi
}

main "$@"
