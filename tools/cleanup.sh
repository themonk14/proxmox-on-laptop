#!/usr/bin/env bash
# cleanup-proxmox.sh
# Stop and destroy ALL VMs and CTs on this node.

set -euo pipefail

DRY_RUN=0
ASSUME_YES=0
TIMEOUT=60   # seconds to wait for graceful shutdown

usage() {
  echo "Usage: $0 [--dry-run] [--yes]"
  echo "  --dry-run   Show what would be done without making changes"
  echo "  --yes       Do not prompt for confirmation"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --yes)     ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done

confirm() {
  if [[ $ASSUME_YES -eq 1 ]]; then return 0; fi
  read -r -p "This will STOP and DESTROY all VMs and CTs on this node. Continue? [y/N] " ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

log() { printf "[%s] %s\n" "$(date +'%F %T')" "$*"; }

wait_until_stopped_vm() {
  local vmid="$1" waited=0
  while qm status "$vmid" 2>/dev/null | grep -q "running"; do
    (( waited++ ))
    if (( waited >= TIMEOUT )); then return 1; fi
    sleep 1
  done
  return 0
}

wait_until_stopped_ct() {
  local ctid="$1" waited=0
  while pct status "$ctid" 2>/dev/null | grep -q "status: running"; do
    (( waited++ ))
    if (( waited >= TIMEOUT )); then return 1; fi
    sleep 1
  done
  return 0
}

do_or_echo() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "DRY-RUN: $*"
  else
    eval "$@"
  fi
}

main() {
  if ! confirm; then
    log "Aborted by user."
    exit 0
  fi

  # Collect IDs first (stable snapshot of targets)
  mapfile -t VM_IDS < <(qm list 2>/dev/null | awk 'NR>1 {print $1}')
  mapfile -t CT_IDS < <(pct list 2>/dev/null | awk 'NR>1 {print $1}')

  log "Found ${#VM_IDS[@]} VMs and ${#CT_IDS[@]} containers."

  # Handle VMs
  for VMID in "${VM_IDS[@]}"; do
    if qm status "$VMID" 2>/dev/null | grep -q "running"; then
      log "VM $VMID is running: attempting graceful shutdown (timeout ${TIMEOUT}s)."
      do_or_echo "qm shutdown $VMID" || true
      if ! wait_until_stopped_vm "$VMID"; then
        log "VM $VMID did not stop gracefully: forcing stop."
        do_or_echo "qm stop $VMID"
      else
        log "VM $VMID stopped gracefully."
      fi
    else
      log "VM $VMID is not running."
    fi

    log "Destroying VM $VMID."
    do_or_echo "qm destroy $VMID"
  done

  # Handle Containers
  for CTID in "${CT_IDS[@]}"; do
    if pct status "$CTID" 2>/dev/null | grep -q "status: running"; then
      log "CT $CTID is running: attempting stop (timeout ${TIMEOUT}s)."
      # Try a polite stop first
      do_or_echo "pct stop $CTID --timeout $TIMEOUT" || true
      if ! wait_until_stopped_ct "$CTID"; then
        log "CT $CTID did not stop with timeout: forcing stop."
        # Force stop by sending SIGKILL via 'pct kill' if present; fallback to stop again
        if command -v pct >/dev/null 2>&1 && pct help 2>&1 | grep -q ' kill '; then
          do_or_echo "pct kill $CTID"
        else
          do_or_echo "pct stop $CTID"
        fi
      else
        log "CT $CTID stopped."
      fi
    else
      log "CT $CTID is not running."
    fi

    log "Destroying CT $CTID."
    do_or_echo "pct destroy $CTID"
  done

  log "Cleanup complete."
  if [[ $DRY_RUN -eq 1 ]]; then
    log "Note: this was a dry run; no changes were made."
  fi
}

main "$@"
