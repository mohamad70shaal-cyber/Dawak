#!/usr/bin/env bash
# Runs the whole SQL suite against a throw-away database.
#
#   PGHOST=... PGPORT=... PGUSER=postgres [PGPASSWORD=...] ./supabase/tests/run.sh [test-name-pattern]
#
# The connecting role must be a superuser (it creates the test database, roles and the Supabase stub).
# The pattern is a SQL LIKE pattern on test function names, e.g. 't\_ord%'. Default: everything.
# Exit status: 0 = every test passed, 1 = a test failed, 2 = setup problem.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DB="${TEST_DB:-dawak_test}"
PATTERN="${1:-%}"
export PGCLIENTENCODING=UTF8
PSQL=(psql -X -q -v ON_ERROR_STOP=1)

"${PSQL[@]}" -d postgres -c "drop database if exists \"$DB\"" -c "create database \"$DB\"" >/dev/null || { echo "cannot create $DB" >&2; exit 2; }

load() {
  echo "load  ${1#"$ROOT"/}"
  "${PSQL[@]}" -d "$DB" -f "$1" 2>&1 | grep -v -e 'already exists, skipping' -e '^NOTICE:  truncate cascades' || true
  # `|| true` above only protects grep; check psql's own status explicitly:
  [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "FAILED to load $1" >&2; exit 2; }
}

load "$ROOT/supabase/tests/00_supabase_stub.sql"
for f in "$ROOT"/supabase/migrations/*.sql; do load "$f"; done
load "$ROOT/supabase/tests/01_helpers.sql"
for f in "$ROOT"/supabase/tests/[1-9]*_tests_*.sql; do load "$f"; done

OUT="$(psql -X -q -At -F '|' -d "$DB" -c "select ok, name, message from tests.run_all('$PATTERN')" 2>&1)" || { echo "$OUT" >&2; exit 2; }
total=0; failed=0
while IFS='|' read -r ok name message; do
  [ -z "$name" ] && continue
  total=$((total + 1))
  if [ "$ok" = "t" ]; then
    echo "PASS  $name"
  else
    failed=$((failed + 1))
    echo "FAIL  $name :: $message"
  fi
done <<< "$OUT"

echo "----"
echo "SQL tests: $((total - failed)) passed, $failed failed, $total total (database: $DB)"
[ "$total" -gt 0 ] || { echo "no tests ran" >&2; exit 2; }
[ "$failed" -eq 0 ]
