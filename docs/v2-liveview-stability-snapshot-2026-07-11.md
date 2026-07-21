# V2 Liveview Stability Snapshot

Date: 2026-07-11

Snapshot path:

- `snapshots/v2-liveview-stability-2026-07-11/`

Purpose:

- preserve the current main UI and session-backend state as a named V2 milestone
- keep a stable comparison point before deeper liveview speed work
- retain the integrated battery module and remote-control-priority behavior

Frozen files:

- `remote-ui/ui-20260628-1-flat.html`
- `remote-ui/cgi-bin/action`
- `remote-ui/cgi-bin/bridge-common.sh`
- `remote-ui/cgi-bin/d810bridge.lua`
- `remote-ui/cgi-bin/liveview`
- `remote-ui/cgi-bin/battery-worker`

Snapshot characteristics:

- `/cc` main route is based on the flat 0628-1 UI
- command priority is preserved over live frame fetches
- liveview uses direct JPEG fetch from the bridge via `FRAME_JPEG`
- battery percentage is served by the sidecar cache path and returned through bridge `STATUS`
- battery worker is intended to run as a single low-priority module
- the browser liveview loop includes the post-first-frame scheduling fix

Observed state around this milestone:

- bridge-side direct frame timing samples on Opal were around `192ms` to `231ms`
- prep overhead was reduced to approximately `0ms` in direct bridge timing samples
- the remaining major bottleneck appears to be camera-side liveview frame acquisition

Why this snapshot matters:

- it is a safe V2 restore point before more aggressive liveview experiments
- it separates the integrated stable branch from future throughput-focused changes
