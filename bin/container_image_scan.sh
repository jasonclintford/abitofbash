#!/usr/bin/env bash
set -euo pipefail

TOOL_NAME="container_image_scan"
TOOL_VERSION="0.1.0"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: container_image_scan.sh [options] --image <name>

Purpose: Scan container images for vulnerabilities.

Options:
  --image <name>        Image name/tag.
  --offline-db          Use offline DB if supported.
  --output-format <f>   table|json (default table).
  --help                Show help.
  --version             Show version.
  --dry-run             Show actions without executing.
  --verbose             Verbose logging.
  --quiet               Suppress non-essential output.
  --json                Emit JSON output only.
  --config <path>       Load config file.
  --log-file <path>     Override log file path.
  --output-dir <dir>    Place artifacts in directory.

Examples:
  container_image_scan.sh --image ubuntu:24.04
USAGE
}

timestamp() {
  date -u +"%Y%m%dT%H%M%SZ"
}

parse_flags() {
  IMAGE=""
  OFFLINE_DB=0
  OUTPUT_FORMAT="table"

  parse_common_flags "$@"
  set -- "${REMAINING_ARGS[@]}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --image)
        shift
        IMAGE=$1
        ;;
      --offline-db)
        OFFLINE_DB=1
        ;;
      --output-format)
        shift
        OUTPUT_FORMAT=$1
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

  if [[ -z "$IMAGE" ]]; then
    die "--image is required" 2
  fi

  local scanner=""
  if command -v trivy >/dev/null 2>&1; then
    scanner="trivy"
  elif command -v grype >/dev/null 2>&1; then
    scanner="grype"
  else
    die "Missing scanner (trivy or grype)." 3
  fi

  local ts
  ts=$(timestamp)
  local report="$OUTPUT_DIR/${TOOL_NAME}_${ts}.${OUTPUT_FORMAT}"
  local summary="$OUTPUT_DIR/${TOOL_NAME}_summary_${ts}.txt"

  if [[ $DRY_RUN -eq 1 ]]; then
    log_info "Dry-run enabled; skipping scan."
  else
    if [[ $scanner == "trivy" ]]; then
      require_cmd "python3"
      local args=("image" "--format" "$OUTPUT_FORMAT" "--severity" "CRITICAL,HIGH,MEDIUM,LOW")
      if [[ $OFFLINE_DB -eq 1 ]]; then
        args+=("--skip-db-update")
      fi
      trivy "${args[@]}" "$IMAGE" >"$report"
      trivy image --format json "$IMAGE" >"${report}.json"
      python3 - <<'PY' "${report}.json" "$summary"
import json
import sys

data = json.load(open(sys.argv[1], "r", encoding="utf-8"))
severity_counts = {}
fix_available = 0
total = 0
for result in data.get("Results", []):
    for vuln in result.get("Vulnerabilities", []) or []:
        total += 1
        sev = vuln.get("Severity", "UNKNOWN")
        severity_counts[sev] = severity_counts.get(sev, 0) + 1
        if vuln.get("FixedVersion"):
            fix_available += 1
with open(sys.argv[2], "w", encoding="utf-8") as fh:
    fh.write("Summary by severity\\n")
    for sev in sorted(severity_counts):
        fh.write(f"{sev}: {severity_counts[sev]}\\n")
    fh.write(f\"Total: {total}\\n\")
    fh.write(f\"Fix available: {fix_available}\\n\")
PY
    else
      local args=("$IMAGE" "-o" "$OUTPUT_FORMAT")
      grype "${args[@]}" >"$report"
      if command -v python3 >/dev/null 2>&1; then
        grype "$IMAGE" -o json >"${report}.json"
        python3 - <<'PY' "${report}.json" "$summary"
import json
import sys

data = json.load(open(sys.argv[1], "r", encoding="utf-8"))
severity_counts = {}
fix_available = 0
total = 0
for match in data.get("matches", []):
    vuln = match.get("vulnerability", {})
    total += 1
    sev = vuln.get("severity", "Unknown")
    severity_counts[sev] = severity_counts.get(sev, 0) + 1
    if vuln.get("fix", {}).get("state") == "fixed":
        fix_available += 1
with open(sys.argv[2], "w", encoding="utf-8") as fh:
    fh.write("Summary by severity\\n")
    for sev in sorted(severity_counts):
        fh.write(f"{sev}: {severity_counts[sev]}\\n")
    fh.write(f\"Total: {total}\\n\")
    fh.write(f\"Fix available: {fix_available}\\n\")
PY
      fi
    fi
  fi

  if [[ $JSON -eq 1 ]]; then
    printf '{"status":"ok","scanner":"%s","report":"%s","summary":"%s"}\n' "$(json_escape "$scanner")" "$(json_escape "$report")" "$(json_escape "$summary")"
  else
    echo "Image scan report saved to $report"
  fi
}

main "$@"
