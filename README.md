# pgsqlrestore

Temporäre PostgreSQL-15-Instanz zum Wiederherstellen eines pgbackrest-Backups.
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
sudo ./restore.sh restore <SETLABEL>
```

| Parameter | Wert |
|-----------|------|
| Image | `percona/percona-pgbackrest:2.56.0` |
| Stanza | `local` |
| Zielverzeichnis | `./data/` |
| Typ | `--type=immediate --target-action=promote` |
| Modus | `--delta` (vorhandene Dateien werden aktualisiert, nicht neu angelegt) |
| Archivierung | deaktiviert (`archive_mode=off`, `archive_command=''`) |

Nach Abschluss ist `./data/` eine vollständige, startbereite PostgreSQL-15-Instanz.

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
