#!/usr/bin/env bash
# Runs the read-only storage inventory and retains local reports safely.
set -Eeuo pipefail

umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_SCRIPT="${INVENTORY_SCRIPT:-${SCRIPT_DIR}/../storage_inventory.sh}"
LOG_DIR="${LOG_DIR:-/var/log/lowify-storage-inventory}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"

case "$RETENTION_DAYS" in
  ''|*[!0-9]*)
    printf 'RETENTION_DAYS must be a non-negative integer\n' >&2
    exit 2
    ;;
esac

[[ -x "$INVENTORY_SCRIPT" ]] || {
  printf 'Inventory script is unavailable: %s\n' "$INVENTORY_SCRIPT" >&2
  exit 1
}

mkdir -p -- "$LOG_DIR"

timestamp="$(date +%Y%m%d-%H%M%S)"
report="${LOG_DIR}/storage-${timestamp}.txt"
temporary_report="${report}.tmp"

cleanup() {
  local status=$?
  [[ -f "$temporary_report" ]] && rm -f -- "$temporary_report"
  exit "$status"
}
trap cleanup EXIT INT TERM

timeout 10m "$INVENTORY_SCRIPT" "$temporary_report" >/dev/null
mv -- "$temporary_report" "$report"

find "$LOG_DIR" -maxdepth 1 -type f -name 'storage-*.txt' -mtime "+${RETENTION_DAYS}" -delete

printf 'Storage inventory saved: %s\n' "$report"
