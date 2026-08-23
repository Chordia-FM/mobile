#!/usr/bin/env bash
# Everything CI runs, in one command, with one verdict at the end.
#
# It exists because reading past a failure is easy when each gate prints a wall of its own output:
# `dart format --set-exit-if-changed` says "1 changed" in the middle of a success-looking summary,
# and `flutter analyze` fails on info-level lints that a grep for "error" hides. Both have shipped
# broken commits. This prints PASS or FAIL per gate and exits non-zero if any failed, so the only
# thing that has to be read correctly is the last line.
#
#   bash tool/check.sh
set -uo pipefail
cd "$(dirname "$0")/.."

# On Windows a leftover tester holds drift's native sqlite3 DLL, and the next `flutter test` dies in
# its native-asset copy step with an error that names none of that.
if command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -NoProfile -Command \
    "Get-Process -Name flutter_tester -ErrorAction SilentlyContinue | Stop-Process -Force" \
    >/dev/null 2>&1 || true
fi

failed=()
run() { # run <name> <command...>
  local name="$1"; shift
  local out
  if out=$("$@" 2>&1); then
    printf '  PASS  %s\n' "$name"
  else
    printf '  FAIL  %s\n' "$name"
    printf '%s\n' "$out" | tail -25 | sed 's/^/        /'
    failed+=("$name")
  fi
}

echo "gates"
run "format"  dart format --output=none --set-exit-if-changed .
run "analyze" flutter analyze
run "i18n"    dart tool/sync_i18n.dart --check
run "api gen" dart tool/gen_api.dart --check

echo "tests"
for pkg in packages/*/; do
  [ -d "$pkg/test" ] || continue
  name="$(basename "$pkg")"
  # A package that reaches Flutter must run under `flutter test`; `dart test` compiles it for the
  # plain VM, where `dart:ui` does not exist.
  if grep -q '^  flutter:' "$pkg/pubspec.yaml"; then
    run "$name" bash -c "cd '$pkg' && flutter test"
  else
    run "$name" bash -c "cd '$pkg' && dart test"
  fi
done
run "app" bash -c "cd app && flutter test"

echo
if [ ${#failed[@]} -eq 0 ]; then
  echo "ALL GATES PASS"
  exit 0
fi
printf 'FAILED: %s\n' "${failed[*]}"
exit 1
