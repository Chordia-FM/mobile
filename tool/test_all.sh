#!/usr/bin/env bash
# Runs every suite in the workspace.
#
# Kills stray flutter_tester processes first: on Windows a run that ends badly leaves one holding
# the native sqlite3 DLL drift ships, and the next `flutter test` dies in its native-asset copy
# step with "Deletion failed, Access is denied" — a tool crash that looks nothing like the real
# cause.
set -uo pipefail
cd "$(dirname "$0")/.."

if command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -NoProfile -Command \
    "Get-Process -Name flutter_tester -ErrorAction SilentlyContinue | Stop-Process -Force" \
    >/dev/null 2>&1 || true
fi

fail=0
for pkg in chordia_net chordia_api chordia_db chordia_sync; do
  printf '%-16s ' "$pkg"
  (cd "packages/$pkg" && dart test 2>&1 | tail -1) || fail=1
done
for pkg in chordia_player app; do
  dir="packages/$pkg"
  [ "$pkg" = app ] && dir=app
  printf '%-16s ' "$pkg"
  (cd "$dir" && flutter test 2>&1 | grep -vE 'available\)|Got dependencies|newer versions|pub outdated|Resolving|Downloading' | tail -1) || fail=1
done
exit $fail
