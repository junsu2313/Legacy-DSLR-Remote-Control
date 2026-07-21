# Opal Live View Frozen Baseline (2026-06-30)

This document freezes the known-good D810 live-view baseline on the GL.iNet Opal.

If we revisit the stack later, this file should be treated as the "do not casually regress" checklist.

## Final Working State

- Camera: Nikon D810
- Router target: GL.iNet Opal / `siflower/sf19a28-fullmask`
- Package architecture: `mips_siflower`
- Low-level transport: `ddserver`
- Camera command layer: `remote-ui/cgi-bin/d810bridge.lua`
- Web UI entry: `/remote-ui/ui.html?v=20260628-2`

## What Is Confirmed Working

- `AF`
- `SHUTTER`
- `LIVE_START`
- repeated `FRAME` capture
- live-view session survives a 12-second wait between frames
- `/tmp/d810-live.jpg` is written
- `/tmp/d810-live-last-good.jpg` is written

## Performance We Measured

- first frame after live-view warmup can take about `2349ms`
- steady-state frames were observed around:
  - `26ms`
  - `35ms`
  - `38ms`
  - `29ms`

This means the backend is no longer the main pacing bottleneck.

## Final Frame-Rate Check

One last direct check was run against `/tmp/d810-live.meta` by sampling `captureDoneAt` changes on the router itself.

Observed frame intervals:

- `469ms`
- `459ms`
- `567ms`
- `462ms`
- `469ms`
- `459ms`
- `465ms`
- `451ms`
- `458ms`
- `443ms`
- `463ms`
- `447ms`
- `469ms`
- `464ms`
- `530ms`
- `482ms`

Interpretation:

- actual fresh live-view frames are being produced roughly every `0.44s` to `0.57s`
- that corresponds to about `2.0` to `2.3 fps`
- the remaining cap is therefore upstream frame generation cadence, not bridge or UI render cost

## Files That Define The Current Good State

- [`E:\Underlab_APP\Camera\_tmp_ddserver\src\communicator.cpp`](E:\Underlab_APP\Camera\_tmp_ddserver\src\communicator.cpp)
- [`E:\Underlab_APP\Camera\_tmp_ddserver\src\communicator.h`](E:\Underlab_APP\Camera\_tmp_ddserver\src\communicator.h)
- [`E:\Underlab_APP\Camera\_tmp_ddserver\src\main.cpp`](E:\Underlab_APP\Camera\_tmp_ddserver\src\main.cpp)
- [`E:\Underlab_APP\Camera\remote-ui\cgi-bin\d810bridge.lua`](E:\Underlab_APP\Camera\remote-ui\cgi-bin\d810bridge.lua)
- [`E:\Underlab_APP\Camera\remote-ui\cgi-bin\bridge-common.sh`](E:\Underlab_APP\Camera\remote-ui\cgi-bin\bridge-common.sh)
- [`E:\Underlab_APP\Camera\remote-ui\ui.html`](E:\Underlab_APP\Camera\remote-ui\ui.html)

## Critical Invariants

### 1. Build the right architecture

Do not deploy a `ramips/mt7621` or `mipsel_24kc` build to the Opal.

Use the Siflower SDK and produce `mips_siflower`.

Wrong-architecture builds can start a crash loop or fail immediately.

### 2. Keep the ddserver session-friendly patch

The stable behavior depends on:

- removing the aggressive 10-second socket timeout behavior
- reading TCP payloads with an exact read loop instead of assuming one `read()`
- avoiding the `accept()` thread-argument race

If these are reverted, session stability may fall back to the earlier `0x2003` failure pattern.

### 3. Do not write back `0xD1A3` immediately after live-view start

The bridge used to:

- read live-view zoom ratio (`0xD1A3`)
- immediately write it back with `0x1016`

That write-back made live view unstable.

Current rule:

- reading `0xD1A3` is fine
- immediate write-back during live-view entry is not

### 4. Start the bridge daemon with its real script path

We confirmed that sourcing `bridge-common.sh` from the wrong shell context can make:

- `SCRIPT_DIR=$(dirname "$0")`

resolve incorrectly, which leads to:

- `/usr/bin/lua: cannot open ./d810bridge.lua`

Current safe rule:

- the daemon must be started against the real deployed script path
- avoid ad hoc shell sourcing that changes `$0`

### 5. UI pacing matters

The backend can now return frames much faster than the old UI cadence expected.

Old UI pacing:

- success path: `650ms`
- pending/error path: `1000ms`

Updated UI pacing:

- success path: `40ms`
- pending path: `250ms`
- retry path: `250ms`
- initial live delay: `150ms`

If the UI feels slow again, check UI polling first before blaming `ddserver`.

## Main Trial-And-Error Lessons

### What looked like a ddserver failure but was not

- `opkg` segfaulted during package install on the router
- that did not mean the rebuilt `ddserver` binary itself was bad
- direct binary replacement was the safer recovery path

### What looked like a UI problem but was not

- the browser could show "live" status while receiving placeholder content
- the real issue was deeper in live-view command sequencing and session handling

### What looked like a transport problem but was partly bridge behavior

- after `LIVE_START`, the bridge's `D1A3` write-back was destabilizing live view
- removing that write-back let steady-state frame capture work

### What looked like a camera limitation but was actually pacing/config

- once the session and bridge stabilized, repeated frames became fast
- the remaining "unnatural" feel was mostly the UI polling delay

## Recommended Recovery Procedure

If live view regresses again:

1. verify `/usr/bin/ddserver` is the Siflower build
2. verify `ddserver` is listening on `127.0.0.1:4757`
3. verify the bridge daemon is listening on `127.0.0.1:8089`
4. test `LIVE_START`
5. test `FRAME`
6. wait 12 seconds
7. test `FRAME` again
8. inspect `/tmp/d810-bridge-debug.log`

## Baseline Test Sequence

Use this exact sequence for future regression checks:

1. `LIVE_START`
2. `FRAME`
3. wait `12s`
4. `FRAME`
5. `STATUS`

Expected result:

- both frame calls succeed
- `STATUS` reports `liveView=true`
- JPEG files exist in `/tmp`

## Variant Workflow Rule

From this baseline onward, new UI, bridge, and ddserver work should begin as copied variants or new files instead of direct overwrite edits on the active defaults.

Rollback snapshot:

- `snapshots/frozen-baseline-2026-06-30/`
