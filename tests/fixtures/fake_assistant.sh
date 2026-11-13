#!/bin/sh
# A stand-in for the claude CLI, for the assistant's tests (tests/control_api_tests.gd): never the real one. It reads
# the --mcp-config it is given, calls the game's MCP server over HTTP as the real one would (one tools/call), and
# prints a stream-json run a line at a time.
#
#   FAKE_ASSIST_TOOL   the tool to call (default changes_list)
#   FAKE_ASSIST_ARGS   its arguments as JSON (default {})
#   FAKE_CLAUDE_ARGS   where to write its own arguments, one a line, then the prompt on stdin
#   FAKE_ASSIST_HANG   set: say one line, then hang, ignoring SIGTERM (the CANCEL test)
cfg=""
prev=""
for a in "$@"; do
  if [ "$prev" = "--mcp-config" ]; then cfg="$a"; fi
  prev="$a"
done
if [ -n "${FAKE_CLAUDE_ARGS:-}" ]; then
  pwd > "$FAKE_CLAUDE_ARGS"
  for a in "$@"; do printf '%s\n' "$a" >> "$FAKE_CLAUDE_ARGS"; done
  printf '%s\n' "--stdin--" >> "$FAKE_CLAUDE_ARGS"
  cat >> "$FAKE_CLAUDE_ARGS"
else
  cat > /dev/null
fi
# FAKE_ASSIST_HANG: says a line and then works forever, deaf to a polite stop (as a CLI tidying up might be).
if [ -n "${FAKE_ASSIST_HANG:-}" ]; then
  trap '' TERM
  printf '%s\n' '{"type":"system","subtype":"init","session_id":"fake-hang","model":"fake"}'
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Thinking for a long time."}]}}'
  sleep 30
  exit 0
fi
url=$(python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1]))["mcpServers"]["dawlings"]["url"])' "$cfg")
token=$(python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1]))["mcpServers"]["dawlings"]["headers"]["Authorization"])' "$cfg")
tool="${FAKE_ASSIST_TOOL:-changes_list}"
args="${FAKE_ASSIST_ARGS:-}"
[ -z "$args" ] && args='{}'
printf '%s\n' '{"type":"system","subtype":"init","session_id":"fake-session-1","model":"fake"}'
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Looking at the room."},{"type":"tool_use","id":"t1","name":"mcp__dawlings__'"$tool"'","input":'"$args"'}]}}'
body='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"'"$tool"'","arguments":'"$args"'}}'
reply=$(curl -s -m 20 -H "Authorization: $token" -H "Content-Type: application/json" -d "$body" "$url")
iserr=$(printf '%s' "$reply" | python3 -I -c 'import json,sys;print("true" if json.load(sys.stdin)["result"]["isError"] else "false")')
text=$(printf '%s' "$reply" | python3 -I -c 'import json,sys;print(json.dumps(json.load(sys.stdin)["result"]["content"][0]["text"]))')
printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","is_error":'"$iserr"',"content":'"$text"'}]}}'
printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":"Done. SUMMARY","total_cost_usd":0.01,"num_turns":2}'
