#!/bin/bash

mkdir -p ./data ./logs ./dumps
chown 999:gisadmin ./data ./logs ./dumps
ln -s ../pgsql/config/ .
if [ -d ../pgsql/backup ]; then
    ln -s ../pgsql/backup/ pgbackrest
elif [ -d ../pgsql/pgbackrest ]; then
    ln -s ../pgsql/pgbackrest/ pgbackrest
else
    echo "Warning: neither ../pgsql/backup nor ../pgsql/pgbackrest found" >&2
fi
