#!/usr/bin/env bash
# Create the library database on MySQL 8 and load 15 months of borrowing history.
# Usage: MYSQL_USER=root MYSQL_PASSWORD=secret ./scripts/build.sh
set -euo pipefail
export MYSQL_PWD="${MYSQL_PASSWORD:-}"
MYSQL=(mysql -h "${MYSQL_HOST:-127.0.0.1}" -u "${MYSQL_USER:-root}")

[ -f data/seed.sql ] || python3 data/generate_seed.py

for f in sql/01_schema.sql sql/02_procedures.sql sql/03_triggers.sql sql/04_views.sql sql/05_indexes.sql; do
  echo "Running $f"
  "${MYSQL[@]}" < "$f" > /dev/null
done
echo "Loading data/seed.sql (replays ~2,200 loans through the stored procedures)..."
"${MYSQL[@]}" < data/seed.sql > /dev/null
echo "Done. Try: mysql library < sql/06_reports.sql"
