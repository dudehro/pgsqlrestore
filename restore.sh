#!/usr/bin/env bash
set -euo pipefail

PGBR_IMAGE="percona/percona-pgbackrest:2.56.0"
PGBR_STANZA="local"

usage() {
  cat <<EOF
Nutzung:
  $0 list                          Verfügbare Backup-Sets anzeigen
  $0 restore [SETLABEL] [OPTIONEN] Backup-Set wiederherstellen (ohne SETLABEL: letztes Backup)
  $0 start                         Restore-Instanz starten

Optionen für 'restore':
  --type=TYP                       Recovery-Typ (Default: immediate)
  --target=TIMESTAMP               Recovery-Ziel; setzt --type automatisch auf 'time',
                                   sofern nicht explizit anders angegeben.

Beispiele:
  $0 restore                                   letztes Backup, --type=immediate
  $0 restore 20240101-120000F                  bestimmtes Set, --type=immediate
  $0 restore --target='2024-01-01 12:00:00+00' Point-in-Time-Recovery (--type=time)
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
  local setlabel=""
  local type=""
  local target=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type=*)
        type="${1#*=}"
        ;;
      --target=*)
        target="${1#*=}"
        ;;
      --type|--target)
        echo "Fehler: '$1' benötigt einen Wert (--$1=WERT)." >&2
        exit 2
        ;;
      --*)
        echo "Fehler: Unbekannte Option '$1'." >&2
        usage
        ;;
      *)
        if [[ -n "$setlabel" ]]; then
          echo "Fehler: Mehrfaches SETLABEL ('$setlabel' und '$1')." >&2
          exit 2
        fi
        setlabel="$1"
        ;;
    esac
    shift
  done

  # Wird ein Ziel angegeben, ist der Typ standardmäßig 'time'.
  if [[ -n "$target" && -z "$type" ]]; then
    type="time"
  fi
  # Default-Typ ohne Ziel.
  if [[ -z "$type" ]]; then
    type="immediate"
  fi

  if [[ "$type" == "immediate" && -n "$target" ]]; then
    echo "Fehler: --target ist mit --type=immediate nicht sinnvoll." >&2
    exit 2
  fi

  mkdir -p ./data ./logs
  chown 999:gisadmin ./data ./logs

  local set_arg=()
  if [[ -n "$setlabel" ]]; then
    set_arg=("--set=$setlabel")
  fi

  local target_arg=()
  if [[ -n "$target" ]]; then
    target_arg=("--target=$target")
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
      --type="$type" \
      "${target_arg[@]}" \
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
    shift
    cmd_restore "$@"
    ;;
  start)
    cmd_start
    ;;
  *)
    usage
    ;;
esac
