#!/bin/sh
# A stand-in for the claude CLI, for the Workshop's tests (tests/workshop_tests.gd): never the real
# one. Prints a recorded stream-json run a line at a time, and does what the recording says the
# run did to the tree, so the Workshop's checkpoint, checks and undo can be tested end to end.
#
#   FAKE_CLAUDE_EVENTS  the recording to print (default: workshop_stream_ok.jsonl beside this)
#   FAKE_CLAUDE_EDIT    a repo-relative file the "run" appends a comment line to
#   FAKE_CLAUDE_WRITE   a repo-relative file the "run" writes FAKE_CLAUDE_BODY into
#   FAKE_CLAUDE_ARGS    where to write its own arguments and its working directory, one a line
#   FAKE_CLAUDE_SLEEP   seconds between lines (default 0.02)
here="$(cd "$(dirname "$0")" && pwd)"
events="${FAKE_CLAUDE_EVENTS:-$here/workshop_stream_ok.jsonl}"
if [ -n "${FAKE_CLAUDE_ARGS:-}" ]; then
  pwd > "$FAKE_CLAUDE_ARGS"
  for a in "$@"; do printf '%s\n' "$a" >> "$FAKE_CLAUDE_ARGS"; done
  printf '%s\n' "--stdin--" >> "$FAKE_CLAUDE_ARGS"
  cat >> "$FAKE_CLAUDE_ARGS"
else
  cat > /dev/null
fi
if [ -n "${FAKE_CLAUDE_EDIT:-}" ]; then
  printf '## edited by the fake claude\n' >> "$FAKE_CLAUDE_EDIT"
fi
if [ -n "${FAKE_CLAUDE_WRITE:-}" ]; then
  mkdir -p "$(dirname "$FAKE_CLAUDE_WRITE")"
  printf '%b' "${FAKE_CLAUDE_BODY:-}" > "$FAKE_CLAUDE_WRITE"
fi
while IFS= read -r line || [ -n "$line" ]; do
  printf '%s\n' "$line"
  sleep "${FAKE_CLAUDE_SLEEP:-0.02}"
done < "$events"
