# D810 / ddserver Live View Work Log

Recorded for the GL.iNet Opal based wireless camera platform.

## Goal

Build a D810 remote control and live-view platform on the Opal router, with `ddserver` as the low-level camera backbone and a small UI layer on top.

## What We Learned

### Camera connectivity

- The router sees the Nikon D810 over USB.
- `gphoto2 --auto-detect` on the router reports:
  - `Nikon DSC D810`
  - USB path such as `usb:001,006`
- USB sysfs inspection on the router shows:
  - device vendor/product: `04b0:0436`
  - device class: imaging camera
  - interface class: `06`
- So the camera itself is present and detectable at the USB layer.

### Working features

- `AF` works.
- `Shutter` works.
- That means the basic camera communication path is alive.

### Broken / incomplete part

- Live view still fails.
- The UI may show status/perf activity, but the live image is not reliably rendered.
- The main remaining issue is in the ddserver camera-open / live-view handshake path, not the UI itself.

## Architecture Direction

### Earlier direction

We previously explored a gPhoto-based loop:

- UI requests a frame
- CGI launches camera tooling
- image is captured and written to disk
- UI loads the file

That path was too slow and caused visible shutter behavior.

### Final direction

We moved toward:

- `D810` -> `ddserver` -> our adapter -> UI

The idea is:

- keep the camera session alive
- stop doing repeated heavy capture work on every UI refresh
- stream or deliver frames directly to the UI

## Files Changed

### 1. `remote-ui/ui.html`

File:

- [`E:\Underlab_APP\Camera\remote-ui\ui.html`](E:\Underlab_APP\Camera\remote-ui\ui.html)

Changes:

- Added a `Frame type` status field.
- Added response metadata tracking for live frames:
  - `content-type`
  - response byte size
- Added logic to label the frame source as:
  - `D810 detected`
  - `Bridge fallback`
- Kept the perf display that shows:
  - server prep time
  - capture time
  - write time
  - total time
  - network time
  - decode/render time

Purpose:

- Make it obvious whether the browser is receiving a real JPEG or a fallback SVG.
- Separate “request is happening” from “real live image is being rendered”.

### 2. `remote-ui/cgi-bin/bridge-common.sh`

File:

- [`E:\Underlab_APP\Camera\remote-ui\cgi-bin\bridge-common.sh`](E:\Underlab_APP\Camera\remote-ui\cgi-bin\bridge-common.sh)

Changes:

- Reworked the bridge request path.
- Removed the dependency on the old `timeout -t 15 nc` style flow that was not portable on the router.
- Moved toward a simpler direct invocation model.

Purpose:

- Avoid OpenWrt / BusyBox compatibility problems.
- Keep the bridge path more deterministic.

### 3. `remote-ui/cgi-bin/d810bridge.lua`

File:

- [`E:\Underlab_APP\Camera\remote-ui\cgi-bin\d810bridge.lua`](E:\Underlab_APP\Camera\remote-ui\cgi-bin\d810bridge.lua)

Changes:

- Added clearer startup / error logging.
- Added direct command handling for:
  - `PING`
  - `STATUS`
  - `LIVE_START`
  - `LIVE_STOP`
  - `AF`
  - `SHUTTER`
  - `FRAME`
  - `RECOVER`
- Added a fallback device path for the known D810:
  - vendor: `0x04b0`
  - product: `0x0436`
- Added more explicit validation for `CONNECT_DEVICE` and `OPEN_SESSION`.
- Adjusted `execute()` so response handling is more tolerant when ddserver returns responses in a way that does not match the earlier assumptions.

Purpose:

- Make the bridge easier to debug.
- Reduce dependence on a fragile assumption that `GET_DEVICES` must always behave exactly the same way.
- Let us distinguish:
  - ddserver transport failure
  - ddserver device discovery failure
  - camera/session failure

### 4. `_tmp_ddserver/src/communicator.cpp`

File:

- [`E:\Underlab_APP\Camera\_tmp_ddserver\src\communicator.cpp`](E:\Underlab_APP\Camera\_tmp_ddserver\src\communicator.cpp)

Changes:

- Updated USB imaging interface handling to use the actual interface number instead of hardcoding `0` in a couple of places.
- Adjusted kernel-driver detach logic to target the real imaging interface.

Purpose:

- Improve ddserver’s ability to open the D810’s imaging interface correctly.
- Reduce the chance that ddserver fails because it checks or detaches the wrong interface.

## Important Observations During Debugging

### Browser / UI observations

- The live frame element exists in the DOM.
- `perf:` text updates continuously.
- The UI can show a live state, but the displayed image still often falls back to placeholder SVG.
- In the browser, `img.complete` can be `true` while the actual `naturalWidth` / `naturalHeight` still look like the placeholder dimensions instead of a real JPEG.

### Live view response observations

- When live view works partially, timing metadata can appear.
- But in many states the browser still receives the fallback SVG instead of a real JPEG.
- That means the pipeline is not just a cache issue.

### ddserver / bridge observations

From router logs and direct bridge commands:

- `PING` can work.
- `STATUS` can fail with:
  - `ddserver returned response 0x2002 without device data`
  - `camera_missing`
  - `socket closed`
- `GET_DEVICES` is the most suspicious early step.
- The bridge can connect to ddserver, read the welcome header, and then fail during device discovery or follow-up reads.

## Protocol Notes

### ddserver

The local ddserver source shows:

- `0x0002` = return USB device list
- `0x0001` = open/select USB imaging device by vendor/product ID
- `0x0004` = interrupt packet request
- default = forward to USB device

ddserver also sends response codes such as:

- `0x2001`
- `0x2002`
- `0x2003`
- `0x201e`

### DigiCamControl

The DigiCamControl ddserver client path shows:

- `Open()` reads the welcome packet.
- `GetDevices()` asks ddserver for the device list.
- `Connect(device)` sends vendor/product IDs.
- `OpenSession()` follows.
- Then live view is done with Nikon commands such as:
  - `0x9201` StartLiveView
  - `0x9203` GetLiveViewImage

This confirmed the architecture:

- ddserver is the transport / USB backend
- our adapter must provide the camera control flow on top

## What We Proved

- The router can see the camera.
- The browser UI is capable of receiving and showing a frame.
- `AF` and `Shutter` are operational.
- The live-view path is not blocked by the UI alone.
- The biggest unresolved issue is the ddserver handshake / device-opening path.

## What We Finished

- We rebuilt `ddserver` in a real Linux environment.
- We confirmed the Opal requires the `mips_siflower` target, not `mipsel_24kc`.
- We deployed the rebuilt Siflower `ddserver` binary to the router.
- We fixed the live-view bridge behavior that was writing `0xD1A3` back immediately after live-view start.
- We confirmed a stable `LIVE_START -> FRAME -> wait 12s -> FRAME -> STATUS` chain.
- We confirmed real JPEG output to:
  - `/tmp/d810-live.jpg`
  - `/tmp/d810-live-last-good.jpg`

## Build Environment Notes

- The OpenWrt SDK is present in the workspace.
- The SDK build requires Linux-like host tools.
- A plain Windows `make.exe` is not enough because the SDK host binaries are Linux ELF executables.
- Git Bash can start the build flow, but host tool execution still fails in this Windows environment.
- That limitation was later resolved by using the Linux server at `192.168.0.23`.

## Current Status

### Working

- USB camera detection
- AF
- Shutter
- Router UI serving
- Live status / perf display
- Stable ddserver rebuild and deploy flow through the Linux server
- Stable live-view JPEG generation
- Stable repeated frame capture after a 12-second wait

### Remaining caveats

- The first live-view frame can still have a warmup cost.
- Browser smoothness depends on UI polling cadence, not only backend speed.
- Bridge daemon startup should use the real deployed script path to avoid `./d810bridge.lua` resolution failures.

## Final Outcome

The original blocker was no longer just "live view is broken."

The final resolved picture is:

- `ddserver` is now stable enough to hold the camera session
- the bridge can keep live view active and fetch real JPEG frames
- repeated frames continue working across the old timeout boundary
- the UI can now be tuned for a DCC-like feel because the backend path is no longer the limiting factor

See the frozen baseline here:

- [`E:\Underlab_APP\Camera\docs\opal-liveview-frozen-baseline-2026-06-30.md`](E:\Underlab_APP\Camera\docs\opal-liveview-frozen-baseline-2026-06-30.md)

## Commands and Checks We Used

- `gphoto2 --auto-detect`
- `ps | grep '[d]dserver'`
- `logread | grep -i ddserver`
- `lua -v`
- `opkg list-installed | grep -Ei 'lua|socket'`
- `printf 'STATUS\n' | nc 127.0.0.1 8089`
- USB sysfs scans under `/sys/bus/usb/devices`

## Bottom Line

The platform is not far off. The camera is there, the UI is ready, and the basic controls work.

The remaining blocker is the ddserver camera-open / live-view handshake, which still needs either:

- a correct protocol fix, or
- a rebuilt ddserver binary with the source patch applied in a real Linux build environment.
