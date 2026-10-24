#!/bin/bash
repo="$(cd "$(dirname "$0")/../../.." && pwd)"
fixtures="$repo/test/fixtures"
scenario="${FAKE_CLI_SCENARIO:-ok}"
mode=print
result=""
log_line=""
for arg in "$@"; do
  log_line="$log_line $arg"
done
original_args=("$@")
while [ $# -gt 0 ]; do
  case "$1" in
    --status) mode=status ;;
    --dry-run) mode=dry_run ;;
    --result) shift; result="$1" ;;
  esac
  shift
done
if [ -n "$FAKE_CLI_LOG" ]; then
  echo "$mode$log_line" >> "$FAKE_CLI_LOG"
fi
if [ "$mode" = dry_run ]; then
  exec "$repo/bin/phomemo-print" "${original_args[@]}"
fi
case "$scenario:$mode" in
  ok:print) source_name=result_print_ok ;;
  ok:status) source_name=result_status_ok ;;
  not_found:*) source_name=result_not_found ;;
  busy:*) source_name=result_busy ;;
  *) echo "fake-cli: unknown scenario $scenario:$mode" >&2; exit 64 ;;
esac
cp "$fixtures/$source_name.json" "$result"
