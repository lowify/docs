#!/usr/bin/env bash
# Read-only storage inventory for the homologation VPS.
set -Eeuo pipefail

REPORT_FILE="${1:-/var/tmp/lowify-storage-inventory-$(date +%Y%m%d-%H%M%S).txt}"
MARIADB_CONTAINER="${MARIADB_CONTAINER:-data-layer-mariadb}"

section() { printf '\n%s\n%s\n' '================================================================================' "$1"; }
collect() {
  local label="$1"
  shift
  if ! "$@"; then
    printf '[collection unavailable: %s]\n' "$label"
  fi
}

{
  printf 'Storage inventory generated at: %s\n' "$(date -Is)"

  section 'DISK'
  df -hT /
  df -i /

  section 'DOCKER FOOTPRINT'
  docker_root="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
  printf 'Docker root: %s\n' "${docker_root:-unavailable}"
  if [[ -n "$docker_root" && -d "$docker_root" ]]; then
    for part in containers volumes overlay2 image buildkit; do
      [[ -d "$docker_root/$part" ]] || continue
      printf '%-12s ' "$part"
      timeout 20s du -sh -- "$docker_root/$part" 2>/dev/null || printf 'unavailable or timed out\n'
    done
  fi
  printf '\nContainers (writable layer):\n'
  collect 'docker ps --size' timeout 15s docker ps -a --size
  printf '\nLargest JSON logs:\n'
  if [[ -n "$docker_root" ]]; then
    timeout 20s sh -c 'find "$1/containers" -type f -name "*-json.log" -printf "%s %p\n" 2>/dev/null | sort -nr | head -n 30 | numfmt --field=1 --to=iec' sh "$docker_root" || printf '[log scan unavailable or timed out]\n'
  fi
  printf '\nNamed volumes (physical size):\n'
  if [[ -n "$docker_root" && -d "$docker_root/volumes" ]]; then
    while IFS= read -r volume; do
      printf '%s\t' "$volume"
      timeout 15s du -sh -- "$docker_root/volumes/$volume/_data" 2>/dev/null || printf 'unavailable\n'
    done < <(docker volume ls -q)
  fi

  section 'MARIADB DATABASES'
  if [[ "$(docker inspect -f '{{.State.Running}}' "$MARIADB_CONTAINER" 2>/dev/null || true)" == true ]]; then
    collect 'MariaDB database sizes' docker exec "$MARIADB_CONTAINER" sh -ec '
      mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" --batch --skip-column-names -e "
        SELECT table_schema, COUNT(*),
               ROUND(SUM(data_length + index_length) / 1024 / 1024, 2)
        FROM information_schema.tables
        GROUP BY table_schema
        ORDER BY SUM(data_length + index_length) DESC;"
    '
  else
    printf 'MariaDB container unavailable: %s\n' "$MARIADB_CONTAINER"
  fi
} | tee "$REPORT_FILE"

printf 'Report saved to: %s\n' "$REPORT_FILE"
