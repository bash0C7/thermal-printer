#!/bin/sh
ROOT=/Users/bash/dev/src/github.com/bash0C7/thermal-printer
BIN=${BIN:-$ROOT/vendor/R2P2-darwin/build/host/bin/picoruby}
TAG=${TAG:-terminal-route1}
LOGS=$ROOT/build/logs
rm -f $LOGS/$TAG-stdout.log $LOGS/$TAG-stderr.log $LOGS/$TAG-exit.log $LOGS/$TAG-scan.log
/Users/bash/.local/bin/timeout 30 "$BIN" $ROOT/spike/scan.rb $LOGS/$TAG-scan.log 6000 > $LOGS/$TAG-stdout.log 2> $LOGS/$TAG-stderr.log
echo "exit=$?" > $LOGS/$TAG-exit.log
exit 0
