# Remote Control Priority Snapshot: 2026-07-11

This note records the command-loop milestone where the browser UI started behaving like a real remote control instead of a generic web control panel.

## Snapshot path

- `snapshots/remote-control-priority-2026-07-11/`

## What was frozen

- active remote UI:
  - `remote-ui/ui-20260628-1-flat.html`
- active command backend:
  - `remote-ui/cgi-bin/d810bridge.lua`
- active liveview CGI:
  - `remote-ui/cgi-bin/liveview`
- action endpoint:
  - `remote-ui/cgi-bin/action`
- bridge bootstrap helper:
  - `remote-ui/cgi-bin/bridge-common.sh`

## Why this snapshot matters

This is the first recorded state where these rules were aligned together:

1. the user command is always first priority
2. liveview frames are only allowed after explicit `LIVE START`
3. `AF`, `SHOT`, and `STOP` preempt frame work
4. command completion happens before accepting the next interrupting command
5. live session intent stays alive across temporary camera liveview drops

## Key technical fixes captured here

- stale lock cleanup for `/tmp/d810-command.lock` and related command-lock flow
- command endpoints fail cleanly when the command lock is genuinely busy
- frame capture no longer auto-starts liveview before user intent exists
- `session_mode_live` is treated as the source of truth for requested live session state
- liveview JPEG recovery works again after `AF` and `shutter`
- UI button press behavior was moved closer to physical remote control feel

## Opal verification at this point

Verified on Opal at `192.168.8.1` on 2026-07-11:

- `action?action=live-on` returned `ok`
- `action?action=af` returned `ok`
- `action?action=shutter` returned `ok`
- `status` remained in live-ready state after `AF` and `shutter`
- `liveview` returned JPEG bytes again after stale-lock cleanup

## How to use this snapshot

- use it as the rollback point if remote command feel regresses
- compare future command-loop work against this version before promoting changes
- keep this snapshot immutable
