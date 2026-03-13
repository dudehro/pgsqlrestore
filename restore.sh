#!/usr/bin/env bash
set -euo pipefail

PGBR_IMAGE="percona/percona-pgbackrest:2.56.0"
PGBR_STANZA="local"

usage() {
  cat <<EOF
Nutzung:
  $0 list                          Verfügbare Backup-Sets anzeigen
  $0 restore [SETLABEL]            Backup-Set wiederherstellen (ohne SETLABEL: letztes Backup)
  $0 start                         Restore-Instanz starten
EOF
  exit 2
}

cmd_list() {
  docker run --rm -it \
    --user 999 \
    -v "$(pwd)/pgbackrest:/pgbackrest:ro" \
    "$PGBR_IMAGE" \
    pgbackrest --stanza="$PGBR_STANZA" \
     --repo1-path=/pgbackrest \
        info
}

cmd_restore() {
  local setlabel="${1:-}"

  mkdir -p ./data ./logs
  chown 999:gisadmin ./data ./logs

  local set_arg=()
  if [[ -n "$setlabel" ]]; then
    set_arg=("--set=$setlabel")
  fi

  docker run --rm -it \
    --user 999 \
    --name postgres-restore-job \
    -v "$(pwd)/data:/var/lib/postgresql/data" \
    -v "$(pwd)/pgbackrest:/pgbackrest:ro" \
    -v "$(pwd)/logs:/var/log" \
    --tmpfs /var/spool/pgbackrest:uid=999 \
    "$PGBR_IMAGE" \
    pgbackrest --stanza="$PGBR_STANZA" \
      --repo1-path=/pgbackrest \
      --pg1-path=/var/lib/postgresql/data \
      --log-level-console=detail \
      "${set_arg[@]}" \
      --type=immediate \
      --target-action=promote \
      --recovery-option=archive_mode=off \
      --recovery-option=archive_command='' \
      --delta \
      restore

  echo ""
  echo "Restore abgeschlossen. Starte mit: $0 start"
}

compose_call() {
  if command -v docker-compose &>/dev/null; then
    docker-compose "$@"
  else
    docker compose "$@"
  fi
}

cmd_start() {
  compose_call up -d
}

[[ $# -ge 1 ]] || usage

case "$1" in
  list)
    cmd_list
    ;;
  restore)
    cmd_restore "${2:-}"
    ;;
  start)
    cmd_start
    ;;
  *)
    usage
    ;;
esac
