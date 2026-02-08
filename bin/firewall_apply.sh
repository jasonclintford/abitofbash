#!/usr/bin/env bash
set -euo pipefail

TOOL_NAME="firewall_apply"
TOOL_VERSION="0.1.0"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: firewall_apply.sh [options]

Purpose: Apply minimal firewall policy using UFW or firewalld.

Options:
  --allow-ssh         Allow SSH (default port 22).
  --ssh-port <n>      SSH port override.
  --allow-outbound    Allow outbound traffic (default yes).
  --force             Apply without prompt.
  --rollback          Attempt rollback (disable firewall).
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
  firewall_apply.sh --allow-ssh --ssh-port 2222
USAGE
}

timestamp() {
  date -u +"%Y%m%dT%H%M%SZ"
}

parse_flags() {
  ALLOW_SSH=0
  SSH_PORT=22
  ALLOW_OUTBOUND=1
  FORCE=0
  ROLLBACK=0

  parse_common_flags "$@"
  set -- "${REMAINING_ARGS[@]}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --allow-ssh)
        ALLOW_SSH=1
        ;;
      --ssh-port)
        shift
        SSH_PORT=$1
        ;;
      --allow-outbound)
        ALLOW_OUTBOUND=1
        ;;
      --force)
        FORCE=1
        ;;
      --rollback)
        ROLLBACK=1
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

apply_ufw() {
  if [[ $ROLLBACK -eq 1 ]]; then
    ufw disable
    return 0
  fi
  ufw --force reset
  if [[ $ALLOW_OUTBOUND -eq 1 ]]; then
    ufw default allow outgoing
  else
    ufw default deny outgoing
  fi
  ufw default deny incoming
  if [[ $ALLOW_SSH -eq 1 ]]; then
    ufw allow "$SSH_PORT"/tcp
  fi
  ufw --force enable
}

apply_firewalld() {
  if [[ $ROLLBACK -eq 1 ]]; then
    firewall-cmd --panic-on || true
    return 0
  fi
  if [[ $ALLOW_OUTBOUND -eq 0 ]]; then
    log_warn "firewalld outbound policy cannot be fully restricted with this script."
  fi
  firewall-cmd --permanent --set-default-zone=public
  if [[ $ALLOW_SSH -eq 1 ]]; then
    firewall-cmd --permanent --add-port="${SSH_PORT}/tcp"
  fi
  firewall-cmd --permanent --remove-service=ssh || true
  if [[ $ALLOW_SSH -eq 1 ]]; then
    firewall-cmd --permanent --add-service=ssh
  fi
  firewall-cmd --reload
}

main() {
  parse_flags "$@"
  init_log_file "$TOOL_NAME"
  OUTPUT_DIR=$(ensure_output_dir "$OUTPUT_DIR")

  if ! is_root; then
    die "Must run as root." 4
  fi
  if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [[ "$SSH_PORT" -lt 1 || "$SSH_PORT" -gt 65535 ]]; then
    die "Invalid --ssh-port value: $SSH_PORT" 2
  fi

  local ts
  ts=$(timestamp)
  local plan="$OUTPUT_DIR/${TOOL_NAME}_plan_${ts}.txt"

  local tool=""
  if command -v ufw >/dev/null 2>&1; then
    tool="ufw"
  elif command -v firewall-cmd >/dev/null 2>&1; then
    tool="firewalld"
  else
    die "No supported firewall tool found (ufw or firewalld)." 3
  fi

  {
    echo "Firewall Plan"
    echo "Tool: $tool"
    echo "Allow SSH: $ALLOW_SSH"
    echo "SSH Port: $SSH_PORT"
    echo "Allow Outbound: $ALLOW_OUTBOUND"
    echo "Rollback: $ROLLBACK"
  } >"$plan"

  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run enabled; plan saved to $plan"
  else
    if [[ $FORCE -eq 0 ]]; then
      read -r -p "Apply firewall changes? [y/N] " answer
      if [[ ! $answer =~ ^[Yy]$ ]]; then
        die "Firewall change cancelled." 1
      fi
    fi
    if [[ $tool == "ufw" ]]; then
      apply_ufw
    else
      apply_firewalld
    fi
  fi

  if [[ $JSON -eq 1 ]]; then
    printf '{"status":"ok","plan":"%s","tool":"%s"}\n' "$(json_escape "$plan")" "$(json_escape "$tool")"
  else
    echo "Firewall plan saved to $plan"
  fi
}

main "$@"
