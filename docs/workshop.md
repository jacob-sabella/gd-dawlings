# The Workshop: asking for a change from inside the game

The Workshop is a dev tool. From inside the running game you type a change you want ("make the
Workshop panel's title a warm amber", "this thing I just grabbed is too small"); Claude Code
makes it in this repo; the game checks it, reloads itself onto the new code and comes back where
you were. If the checks fail it does not reload, and offers to undo the request or ask Claude to
fix it.

It exists only on the developer's own machine. Nobody else sees it, and nothing of it goes over
the network.

## Turning it on

It needs all four of these:

1. **The dev flag**, any one of:
   - `--workshop` on the command line (`godot --path . -- --workshop`),
   - `DAWLINGS_WORKSHOP=1` in the environment,
   - the project setting `dawlings/dev/workshop = true` (put it in `override.cfg`, which is
     ignored by git, rather than in project.godot),
   - `workshop=true` under `[dev]` in `user://workshop.cfg`.
2. **Not an exported build.** `OS.has_feature("template")` turns it off whatever else is set.
3. **`claude` on PATH** (Claude Code 2.1 or later, signed in).
4. **Not in a multiplayer session.** Hosting or joined, it is off, even with the flag on: a change
   built here would reach this machine only, and bandmates would play on with the old code. A
   session begun while a request runs lets the request finish, but its reload waits until the
   session is left (then RELOAD).

`Workshop.enabled()` is the whole rule (and `Workshop.allowed()` the same rule without the
process around it, for the suite). With it off there is no station `workshop` at all: no panel,
no line on the help card, no row on the station board, nothing in I's cycle. The suite always
runs with it off (`Workshop.forced = 0` in tests/run_tests.gd), so a developer's flag never changes
the rooms the suite checks.

`user://workshop.cfg` also takes, under `[dev]`: `screenshot` (true), `auto_reload` (true),
`auto_commit` (false) and `budget_usd` (5.0).

## Using it

The panel hangs on the control room's right wall, toward the live room, behind the patchbay's
stand (`Venue.workshop_spot`). It is station `workshop`: I walks there, the station board lists it,
F1's PLAY · CONTROL ROOM page has its line. At a desk **F9** asks from anywhere, without walking
over: what you were looking at is what the request is about.

- **ASK** (or F9): a text box on the monitor at a desk (`NamePrompt`, up to 400 characters, Enter
  sends it); in a headset, a typing pad under the panel (`TypingPad`, OK sends it). Dictation can go
  in the same place later: anything that ends in `Workshop.ask(text)`.
- The face shows the request running now (or the last), its status and its last lines as they
  stream (tools used, files edited, test summary lines, the result), the HISTORY with each one's
  status, and the context line: how many journal events the next request goes with, and whether a
  screenshot does.
- **CANCEL** stops the run (and everything it started: it is a process group of its own). While a
  reload counts down, the same key is **STAY**.
- **UNDO LAST** puts back exactly the files the last request changed.
- **FIX** asks the same Claude session (`--resume <session>`) to fix the checks that failed.
- **RELOAD** reloads now.
- **SHOT** turns the screenshot with each request on or off.
- **CONTEXT** shows what the next request will be sent with: an overlay on the monitor, a page
  beside the panel in a headset.

One request runs at a time; the others wait, QUEUED.

## What happens to a request

1. **Asked.** The context is taken there and then (below) and written to
   `shots/workshop/<id>/context.md`, the screenshot to `shot.png` beside it.
2. **Checkpoint.** Off the main thread: HEAD's commit, and every file git calls changed or
   untracked, its blob id and a copy (`WorkshopCheckpoint.before`).
3. **Run.** `claude -p` in the repo, the prompt on its stdin from `prompt.md`, its stream-json into
   `events.jsonl`, which the game reads a little each frame (`WorkshopRunner.poll`, never waiting).
   The prompt is the request wrapped in the repo's rules (house style, desktop and headset, targeted
   tests only, never commit, leave the uncommitted work alone), tells it to read the context file
   first, and asks for two last lines, `SUMMARY:` and `TESTS:`.
4. **What changed.** Every file whose blob id differs from before (a file clean before is
   HEAD's): the request's files, copied before and after, with `changes.json` and a readable
   `patch.diff` (`WorkshopCheckpoint.after`). Other uncommitted work does not count, because it did
   not change.
5. **Checks.** A reimport where a script is new (a class_name), every changed `.gd` parse-checked
   (`godot --headless --path . --check-only --script`), then the tests on its `TESTS:` line
   (`DAWLINGS_TESTS=...`). Any failure: FAILED, no reload.
6. **Reload.** Clean: READY, and after four seconds (STAY stops it) the game reloads.

Nothing is committed unless `auto_commit` is on, and then only onto a branch `workshop`, made with
a private index (`GIT_INDEX_FILE`) so the working tree, the index and the checked-out branch are
untouched (`WorkshopCheckpoint.commit_to_branch`). Otherwise you commit by asking.

## Context: what a request is sent with

So that "make this louder" arrives with what "this" was. `WorkshopJournal` keeps, while the
Workshop is on, the last five minutes (at most 400 events) of what the player did, from where those
things already pass rather than calls in the gear: every `ControlAffordance` (a grab and let-go is
one event with the value before and after and the readout; scrolling folds into it), every
`Item` (grabbed, thrown or dropped, put back), the studio's station (I, F, the board, a headset's
travel all end in `Studio.station`), its venue and focused surface, DAW's transport (play, stop,
record, seek), every `Session.notice` (the toasts), the notes and hits this player played (a line
an instrument after a pause), and the engine's own log (a `Logger`: SCRIPT ERRORs and warnings, and
the last lines printed). Once a second it looks round: the trail of where the player stood (kept on
a 0.5 m move or a 25 degree turn) and what is under the cursor or the gaze (its path, script and
hover card).

At send time `WorkshopContext.build` writes, most useful first: the request; where the player is
(venue and arrangement, desktop or headset, pose, eye height, station, focused surface); what they
look at and hold (path, script, hover-card words, its script's properties); the stations in view
with distances and screen positions; the journal, newest first; the trail; the mix (backend,
project, transport, tempo, every track's level, pan, mute, solo, arm, FX and sends, the sections);
the session (role, who); the settings (Ergonomics, window, engine); the repo (branch, uncommitted
files, last commits); the log's tail. Each section has a share of 40 KB.

**Nothing secret is written** (`WorkshopContext.scrub`): no session code or ticket, nothing after a
ticket, token, secret, password, key or auth word, no run of 40 token-like characters, no address
but localhost, no environment, the repo's own path as `<repo>` and any other home path as `~`.

## Undo

UNDO LAST (or `Workshop.undo(id)`) puts each of the request's files back as it was just before the
request ran (to its uncommitted state where it had one, not to HEAD), and deletes the files it made,
but only where the file is still exactly as the request left it; one you have edited since is left
alone and named. Nothing else in the tree is touched. The checkpoints live in
`shots/workshop/<id>/checkpoint/` and the history in `shots/workshop/history.json`, so Undo works
after a reload too; undoing the request the game is running on says to RELOAD.

## Reload and resume

Live script reload with the room standing is fragile, so a reload is a new process.
`WorkshopResume.snapshot` saves to `user://workshop_resume.json`: the venue and its arrangement,
the walker's feet, heading, pitch and eye height, the station, flying or not, the transport's
position and whether it was playing, the project file, desktop or headset, and the Workshop's
history. The game starts itself again (`OS.create_instance`) with its own command line plus
`--resume user://workshop_resume.json`, and quits. On the new one's start the Workshop restores it:
the venue, the walker where it stood facing the same way (in a headset, the station travelled to
again), the song where it was and playing if it was, the project reopened if it was a file; and the
panel says "reloaded onto <summary>".

**In a session:** never. The Workshop asks nothing and reloads onto nothing while this machine
hosts or has joined a session (`Session.is_networked()`), so there is no host that reloads under
its guests and no two players left on different code.

## What it can and cannot do

The command line, not the prompt, says what it may do (`WorkshopRunner.claude_args`):

```
claude -p --output-format stream-json --verbose
  --restricted --tools Read,Edit,Write,Glob,Grep,Bash
  --permission-mode dontAsk --permission-prompts none
  --strict-mcp-config --max-budget-usd 5.00
  --append-system-prompt "You are running inside the dawlings Workshop ... Work only in <repo>."
  --allowedTools Read Glob Grep Edit(./**) Write(./**)
      "Bash(godot --headless --path . *)" "Bash(timeout * godot --headless --path . *)"
      "Bash(DAWLINGS_TESTS=* timeout * godot --headless --path . *)" ... "Bash(tools/shot.sh *)"
      "Bash(git status*)" "Bash(git diff*)" "Bash(git log*)" "Bash(git show*)" ls wc head tail
  --disallowedTools "Bash(git push*)" "Bash(git commit*)" "Bash(git reset*)" "Bash(git checkout*)"
      "Bash(git restore*)" "Bash(git stash*)" "Bash(git clean*)" ... "Bash(rm *)" "Bash(curl *)"
      "Bash(wget *)" "Bash(ssh *)" ... Edit/Write of vendor/, deploy/, .git/, shots/workshop/
      WebFetch WebSearch
  [--resume <session>]     (FIX)
```

`--restricted` ignores the user's and the project's settings files, confines the file tools to the
repo, and lets only a person approve a write to git or settings files. `dontAsk` with nobody to
answer means anything not allowed is refused, not waited on; the refusal shows on the panel.

It **can**: read the repo, edit and write files in it, run the targeted tests, a parse check, a
reimport, `tools/shot.sh` and the layout tools, and read git's state.

It **cannot**: commit, push, stash, reset, check out or restore; delete with `rm`; reach the network
(no web tools, no curl, wget, ssh); touch `vendor/` (dawkit), `deploy/` or `.git/`; touch its own
checkpoints; spend more than the budget; ask a question.

## Files

- `core/dev/workshop.gd` (Workshop): the gate, the queue, a request's life, checks, undo, fix,
  reload, F9.
- `core/dev/workshop_runner.gd` (WorkshopRunner): the command line, the process, the tail.
- `core/dev/workshop_stream.gd` (WorkshopStream): stream-json into progress lines.
- `core/dev/workshop_checkpoint.gd` (WorkshopCheckpoint): before, after, undo, the branch commit.
- `core/dev/workshop_journal.gd` (WorkshopJournal): the last five minutes.
- `core/dev/workshop_context.gd` (WorkshopContext): the context file, scrubbed.
- `core/dev/workshop_resume.gd` (WorkshopResume): snapshot, restart arguments, restore.
- `core/dev/workshop_panel.gd` (WorkshopPanel): the panel and its keys.
- `tests/workshop_tests.gd`, `tests/fixtures/fake_claude.sh`, `tests/fixtures/workshop_stream_*.jsonl`:
  the suite's `_test_workshop_*`, which never run the real CLI.
