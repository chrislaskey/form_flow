#!/usr/bin/env bash
#
# Snapshots the demo's FormFlow data as SQL, so a regenerated demo starts
# with the flows and forms that were built by hand in the admin UI.
#
#   ./examples/snapshot.sh                   # the templates: flows and forms
#   ./examples/snapshot.sh --with-instances  # plus the flow and form instances
#
# Reads demo/demo_dev.db and writes one INSERT per row for every FormFlow
# template table into overlay/priv/repo/form_flow_snapshot.sql (and the same
# file under demo/, so the two stay in step without regenerating). The
# migration priv/repo/migrations/*_load_form_flow_snapshot.exs replays that
# file into an empty database, which is what `mix setup` runs after the
# tables exist.
#
# Build or edit the pet licensing flows at http://localhost:4001/admin, then
# run this and commit the SQL. Ids are kept as built, so subflow references,
# related_form paths, and review sources survive the round trip.
#
# The instance tables - journeys walked and forms filled while trying the
# flows out - are test data more often than demo data, so they are left out
# unless asked for with --with-instances.
#
# form_flow_instance_next_positions is one of them, and is the one worth
# saying out loud: it is the cache of where each journey's flow is open,
# and a reviewer's queue is a query over it. A snapshot without it seeds
# journeys no queue can see - they appear only once someone opens the
# journey's own page, which read-repairs the cache on the way in. Its rows
# are written by the library, never by hand, so they travel with the
# journeys rather than being rebuilt by the loader.
#
# Every INSERT names its columns: sqlite3's insert mode with headers on
# (`INSERT INTO t(a,b,...) VALUES(...)`), rather than `.dump`'s positional
# `INSERT INTO t VALUES(...)`. A positional row breaks the moment the table
# gains a column - the library is pre-release and its one migration is the
# schema, so columns do arrive - while a named row loads into any table that
# still has those columns. One statement per line either way: sqlite3
# escapes embedded newlines with replace(), so the loader can split on
# lines. Tables are listed parents-first so the load also passes with
# foreign keys enforced; the migration defers them regardless.

set -euo pipefail
cd "$(dirname "$0")"

DB="demo/demo_dev.db"
OUT="overlay/priv/repo/form_flow_snapshot.sql"

with_instances=false
for arg in "$@"; do
  case "$arg" in
    --with-instances) with_instances=true ;;
    *) echo "Unknown option: $arg (only --with-instances is understood)" >&2; exit 2 ;;
  esac
done

[ -f "$DB" ] || { echo "No demo database at $DB — run the demo first" >&2; exit 1; }
command -v sqlite3 >/dev/null || { echo "sqlite3 is not installed" >&2; exit 1; }

# Parents before children. form_flow_database_migrations is deliberately
# absent: it records which FormFlow schema version is installed, which the
# add_form_flow migration writes for itself.
TEMPLATE_TABLES=(
  form_flow_template_flows
  form_flow_template_forms
  form_flow_template_form_versions
  form_flow_template_flow_nodes
  form_flow_template_flow_relationships
  form_flow_template_flow_events
)
INSTANCE_TABLES=(
  form_flow_instance_flows
  form_flow_instance_next_positions
  form_flow_instance_forms
  form_flow_instance_form_events
  form_flow_instance_flow_events
)

# Fail if FormFlow has grown a table neither list knows about, rather than
# silently snapshotting without it.
missing=$(sqlite3 "$DB" "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'form_flow_%' AND name != 'form_flow_database_migrations' ORDER BY name" \
  | grep -vxF -f <(printf '%s\n' "${TEMPLATE_TABLES[@]}" "${INSTANCE_TABLES[@]}") || true)
if [ -n "$missing" ]; then
  echo "FormFlow tables not in this script's table lists:" >&2
  echo "$missing" >&2
  exit 1
fi

TABLES=("${TEMPLATE_TABLES[@]}")
if $with_instances; then
  TABLES+=("${INSTANCE_TABLES[@]}")
fi

{
  echo "-- FormFlow data snapshot, written by examples/snapshot.sh."
  echo "-- One INSERT per line, columns named; loaded by priv/repo/migrations/*_load_form_flow_snapshot.exs."
  echo "-- Regenerate with ./examples/snapshot.sh rather than editing by hand."
  for table in "${TABLES[@]}"; do
    sqlite3 "$DB" ".headers on" ".mode insert $table" "SELECT * FROM $table ORDER BY inserted_at, id" \
      | grep '^INSERT INTO ' || true
  done
} > "$OUT"

rows=$(grep -c '^INSERT INTO ' "$OUT" || true)
echo "Wrote $rows rows to $OUT"

# Keep the generated app's copy in step, if it exists
if [ -d demo/priv/repo ]; then
  cp "$OUT" demo/priv/repo/form_flow_snapshot.sql
  echo "Copied to demo/priv/repo/form_flow_snapshot.sql"
fi
