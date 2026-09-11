#!/usr/bin/env bash
#
# Snapshots the demo's FormFlow data as SQL, so a regenerated demo starts
# with the flows and forms that were built by hand in the admin UI.
#
#   ./examples/snapshot.sh
#
# Reads demo/demo_dev.db and writes one INSERT per row for every FormFlow
# table into overlay/priv/repo/form_flow_snapshot.sql (and the same file
# under demo/, so the two stay in step without regenerating). The migration
# priv/repo/migrations/*_load_form_flow_snapshot.exs replays that file into
# an empty database, which is what `mix setup` runs after the tables exist.
#
# Build or edit the pet licensing flows at http://localhost:4001/admin, then
# run this and commit the SQL. Ids are kept as built, so subflow references,
# related_form paths, and review sources survive the round trip.
#
# The dump is plain `sqlite3 .dump --data-only`, one statement per line
# (sqlite3 escapes embedded newlines with replace(), so the loader can split
# on lines). Tables are listed parents-first so the load also passes with
# foreign keys enforced; the migration defers them regardless.

set -euo pipefail
cd "$(dirname "$0")"

DB="demo/demo_dev.db"
OUT="overlay/priv/repo/form_flow_snapshot.sql"

[ -f "$DB" ] || { echo "No demo database at $DB — run the demo first" >&2; exit 1; }
command -v sqlite3 >/dev/null || { echo "sqlite3 is not installed" >&2; exit 1; }

# Parents before children. form_flow_database_migrations is deliberately
# absent: it records which FormFlow schema version is installed, which the
# add_form_flow migration writes for itself.
TABLES=(
  form_flow_template_flows
  form_flow_template_forms
  form_flow_template_form_versions
  form_flow_template_flow_nodes
  form_flow_template_flow_relationships
  form_flow_template_flow_events
  form_flow_instance_flows
  form_flow_instance_forms
  form_flow_instance_form_events
  form_flow_instance_flow_events
)

# Fail if FormFlow has grown a table this list does not know about, rather
# than silently snapshotting without it.
missing=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'form_flow_%' AND name != 'form_flow_database_migrations' ORDER BY name" \
  | grep -vxF -f <(printf '%s\n' "${TABLES[@]}") || true)
if [ -n "$missing" ]; then
  echo "FormFlow tables not in this script's TABLES list:" >&2
  echo "$missing" >&2
  exit 1
fi

{
  echo "-- FormFlow data snapshot, written by examples/snapshot.sh."
  echo "-- One INSERT per line; loaded by priv/repo/migrations/*_load_form_flow_snapshot.exs."
  echo "-- Regenerate with ./examples/snapshot.sh rather than editing by hand."
  for table in "${TABLES[@]}"; do
    sqlite3 "$DB" ".dump --data-only $table" | grep '^INSERT INTO ' || true
  done
} > "$OUT"

rows=$(grep -c '^INSERT INTO ' "$OUT" || true)
echo "Wrote $rows rows to $OUT"

# Keep the generated app's copy in step, if it exists
if [ -d demo/priv/repo ]; then
  cp "$OUT" demo/priv/repo/form_flow_snapshot.sql
  echo "Copied to demo/priv/repo/form_flow_snapshot.sql"
fi
