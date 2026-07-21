# Variant Workflow For UI, Bridge, And ddserver

As of 2026-06-30, the project adopts a frozen-baseline workflow.

## Baseline snapshot

The current known-good baseline is stored at:

- `snapshots/frozen-baseline-2026-06-30/`

Additional milestone snapshots:

- `snapshots/remote-control-priority-2026-07-11/`
- `snapshots/v2-liveview-stability-2026-07-11/`

That snapshot contains the active UI, CGI bridge, ddserver source, OpenWrt packaging files, and the supporting stabilization notes.

## Editing rule

From this point forward:

- do not treat the current active files as disposable scratch space
- do not stack new experiments directly on top of the active defaults
- create a new file or copied variant for any substantial backend or UI change

Recommended naming examples:

- `remote-ui/ui.liveview-v2.html`
- `remote-ui/ui.session-lab.html`
- `remote-ui/cgi-bin/d810bridge_liveview_v2.lua`
- `_tmp_ddserver/src/communicator_session_v2.cpp`

## Promotion rule

Only promote a variant to the active default after:

1. local verification passes
2. Opal deployment passes
3. AF, shutter, and live-view behavior are rechecked
4. the rollback path remains clear

## Rollback rule

If a change introduces instability, restore behavior from the frozen snapshot before continuing with the next experiment.

## Why this workflow exists

This project already has a working baseline for:

- AF control
- shutter control
- live-view session bring-up
- bridge JPEG frame extraction
- improved UI polling cadence

The main risk now is not lack of functionality, but losing a verified baseline while iterating on live-view quality and runtime stability.
