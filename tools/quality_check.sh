#!/bin/sh
# Files over the line limit and unreferenced public symbols in the refactor's scope.
# See tools/quality_check.py for the rules. Exit status 1 when anything is reported.
cd "$(dirname "$0")/.." || exit 2
exec python3 -I tools/quality_check.py "$@"
