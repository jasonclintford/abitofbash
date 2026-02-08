# A Bit of Bash - Utility & Cybersecurity Script Suite

A cohesive Bash script suite for everyday Linux utility and cybersecurity tasks, tested on Ubuntu 24.04 and Fedora/RHEL-family systems.

## Quickstart (non-root)

```bash
# Clone repo and install into ~/.local/bin
make install

# Add ~/.local/bin to PATH if not already
export PATH="$HOME/.local/bin:$PATH"

# Run any script
sys_update.sh --help
```

To configure defaults, copy the config template and pass it via `--config`:

```bash
cp config/example.env ~/.config/abitofbash.env
net_quickdiag.sh --config ~/.config/abitofbash.env
```

## Scripts

### 1) sys_update.sh
Safe OS update wrapper with package snapshots.

**Example:**
```bash
sys_update.sh --security-only --yes
```

### 2) cleanup_hygiene.sh
Disk cleanup with guardrails and estimation.

**Example:**
```bash
cleanup_hygiene.sh --include "*.log" --exclude "*keep*"
```

### 3) disk_health_report.sh
SMART + filesystem + inode report (Markdown + JSON).

**Example:**
```bash
disk_health_report.sh --warn-disk-pct 90
```

### 4) backup_rsync.sh
Incremental backups with optional encryption.

**Example:**
```bash
backup_rsync.sh --source /etc --dest /mnt/backup
backup_rsync.sh --source /home --dest user@host:/backups --encrypt --recipient ABCDEF
```

### 5) restore_backup.sh
Guided restore with plan/diff preview.

**Example:**
```bash
restore_backup.sh --snapshot /mnt/backup/snapshot_20240101 --dest /restore
```

### 6) net_quickdiag.sh
Network diagnostics (DNS/gateway/latency/routes/interfaces).

**Example:**
```bash
net_quickdiag.sh --target example.com
```

### 7) baseline_audit.sh
Local security baseline checks with severity and remediation hints.

**Example:**
```bash
baseline_audit.sh --output-dir /tmp/audit
```

### 8) firewall_apply.sh
Apply minimal firewall policy with preview and rollback.

**Example:**
```bash
firewall_apply.sh --allow-ssh --ssh-port 2222
```

### 9) open_ports_snapshot.sh
Snapshot listening ports and diff against previous run.

**Example:**
```bash
open_ports_snapshot.sh --output-dir /tmp/ports
```

### 10) nmap_wrapper.sh
Safe scanning wrapper for lab networks with profiles.

**Example:**
```bash
nmap_wrapper.sh --quick --target 192.168.1.0/24
```

### 11) pcap_capture_rotate.sh
tcpdump capture with rotation and compression.

**Example:**
```bash
pcap_capture_rotate.sh --iface eth0 --filter "port 443"
```

### 12) auth_log_hunter.sh
Detect SSH brute force and authentication anomalies.

**Example:**
```bash
auth_log_hunter.sh --output-dir /tmp/auth
```

### 13) ioc_grep_hunt.sh
Hunt IOCs across allowlisted log directories.

**Example:**
```bash
ioc_grep_hunt.sh --ioc-file iocs.txt --log-dir /var/log
```

### 14) yara_fs_scan.sh
Filesystem scan using YARA rules.

**Example:**
```bash
yara_fs_scan.sh --rules-dir /opt/rules --target /srv
```

### 15) incident_triage_collect.sh
IR collection bundle with manifest and hashes.

**Example:**
```bash
incident_triage_collect.sh --output-dir /tmp/triage
```

### 16) file_integrity_baseline.sh
Create and verify file integrity baselines (FIM).

**Example:**
```bash
file_integrity_baseline.sh --create --target /etc
```

### 17) container_image_scan.sh
Scan container images for vulnerabilities (trivy/grype).

**Example:**
```bash
container_image_scan.sh --image ubuntu:24.04
```

### 18) tls_cert_audit.sh
Audit certificate expiry and TLS posture.

**Example:**
```bash
tls_cert_audit.sh --endpoints endpoints.txt --warn-days 30
```

### 19) toolchain_bootstrap.sh
Install and verify dependencies for this suite.

**Example:**
```bash
toolchain_bootstrap.sh --yes
```

## Safety Notes

- Scripts default to safe, non-destructive behavior.
- Actions that could impact systems (firewall, cleanup, updates) require explicit flags such as `--force` or prompts.
- Always review `--dry-run` output before applying changes.

## Legal Note for Scanning Tools

You must have authorization to scan any network or system. Limit scanning to lab environments and assets you are permitted to test.
