# pgsqlrestore

Temporäre PostgreSQL-16-Instanz zum Wiederherstellen eines pgbackrest-Backups.
Das Backup wird in `./data/` entpackt und anschließend als eigenständiger Container gestartet, der im bestehenden Docker-Netzwerk erreichbar ist.

---

## Voraussetzungen

| Was | Wo nötig |
|-----|----------|
| Docker + Docker Compose | Host |
| Gruppe `gisadmin` (GID 999) auf dem Host | Host |
| `pgsql`-Service-Verzeichnis auf demselben Host (für Symlinks) | Host |
| pgbackrest-Backup-Verzeichnis unter `./pgbackrest/` | Host (via Symlink aus `../pgsql/pgbackrest/`) |
| Docker-Netzwerk `${NETWORK_NAME:-kvwmap_prod}` existiert | Host |
| Config-Dateien unter `./config/` (`postgresql.conf`, `pg_hba.conf`) | Host (via Symlink aus `../pgsql/config/`) |

---

## Erstmalige Einrichtung (nach dem Klonen)

```bash
sudo bash post-clone.sh
```

Erstellt:
- `./data/`, `./logs/` und `./dumps/` mit Eigentümer `999:gisadmin`
- Symlink `./config/` → `../pgsql/config/`
- Symlink `./pgbackrest/` → `../pgsql/pgbackrest/`

---

## Hauptworkflow

### 1. Verfügbare Backup-Sets anzeigen

```bash
sudo ./restore.sh list
```

Startet einen kurzlebigen `percona/percona-pgbackrest:2.56.0`-Container, der `./pgbackrest/` read-only einbindet und `pgbackrest info` für die Stanza `local` ausführt.

Notiere das gewünschte `SETLABEL` aus der Ausgabe, z. B. `20240101-120000F`.

---

### 2. Backup wiederherstellen

```bash
sudo ./restore.sh restore [SETLABEL] [OPTIONEN]
```

Ohne `SETLABEL` wird das letzte Backup verwendet.

| Parameter | Wert |
|-----------|------|
| Image | `percona/percona-pgbackrest:2.56.0` |
| Stanza | `local` |
| Zielverzeichnis | `./data/` |
| Typ | `--type=immediate --target-action=promote` (Default) |
| Modus | `--delta` (vorhandene Dateien werden aktualisiert, nicht neu angelegt) |
| Archivierung | deaktiviert (`archive_mode=off`, `archive_command=''`) |

**Optionen:**

| Option | Bedeutung |
|--------|-----------|
| `--type=TYP` | Recovery-Typ von pgbackrest. Default: `immediate` (Wiederherstellung bis zum konsistenten Ende des Backups). |
| `--target=TIMESTAMP` | Recovery-Ziel für Point-in-Time-Recovery (PITR). Setzt `--type` automatisch auf `time`, sofern nicht explizit anders angegeben. |

**Beispiele:**

```bash
# Letztes Backup, --type=immediate
sudo ./restore.sh restore

# Bestimmtes Set, --type=immediate
sudo ./restore.sh restore 20240101-120000F

# Point-in-Time-Recovery bis zu einem Zeitpunkt (--type=time)
sudo ./restore.sh restore --target='2024-01-01 12:00:00+00'

# PITR aus einem bestimmten Set heraus
sudo ./restore.sh restore 20240101-120000F --target='2024-01-01 12:00:00+00'
```

> **Hinweis zu PITR (`--type=time`):** Für die Wiederherstellung bis zu einem
> Zeitpunkt muss pgbackrest die WAL-Segmente bis zum Zielzeitpunkt aus dem
> Backup-Repo replayen können. Das setzt voraus, dass die WAL-Archive im Repo
> vorhanden sind (WAL-Archivierung aktiv). Bei reinen Full-Backups ohne
> archivierte WALs funktioniert `--type=time` nicht — nutze dann `immediate`.

Nach Abschluss ist `./data/` eine vollständige, startbereite PostgreSQL-Instanz.

---

### 3. Restore-Instanz starten

```bash
sudo ./restore.sh start
```

Startet den Container via `docker compose up -d`.

| Eigenschaft | Wert |
|-------------|------|
| Image | `pkorduan/postgis:15-3.3` |
| Container-Name | `${NETWORK_NAME:-kvwmap_prod}_pgsqlrestore` |
| Port | `5444` → `5432` |
| Netzwerk-Alias | `pgsqlrestore` (im Docker-Netzwerk) |
| Netzwerk | `${NETWORK_NAME:-kvwmap_prod}` (extern, muss vorher existieren) |

Eingebundene Volumes:

| Host-Pfad | Container-Pfad | Modus |
|-----------|----------------|-------|
| `./data/` | `/var/lib/postgresql/data` | rw |
| `./config/` | `/var/lib/postgresql/config` | ro |
| `./pgbackrest/` | `/pgbackrest` | ro |
| `./logs/` | `/var/log/pgsql` | rw |
| `./dumps/` | `/dumps` | rw |

---

### 4. Instanz wieder beenden

```bash
docker compose down
```

---

## Hilfstool: WAL zurücksetzen

Falls der Restore-Container nicht startet, weil der WAL-Status inkonsistent ist:

```bash
sudo bash pg_resetwal.sh
```

Setzt den WAL der wiederhergestellten Instanz in `./data/` mit `pg_resetwal -f` zurück.
**Nur im Notfall verwenden** – möglicher Datenverlust bei nicht abgeschlossenen Transaktionen.
