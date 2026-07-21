# DCC-Based Normalization Checklist

We already have a working `AF` and `shutter` path on the Opal.
The next step is not a rewrite of everything. The next step is to normalize three axes against DigiCamControl:

1. `ddserver`
2. bridge
3. UI

The rule is simple:

- use DigiCamControl as the functional baseline
- keep our implementation aligned with our router and browser environment
- prefer real end-to-end verification over feature claims

## Axis 1: `ddserver`

### Current state

- OpenWrt packaging exists.
- The Opal-compatible package has now been rebuilt and installed as `0.2-14`.
- The router target is `siflower/sf19a28-fullmask`, so `mips_siflower` is the correct package architecture.
- The source tree exists locally in `_tmp_ddserver`.
- The package currently builds only as a transport package, not as a full camera experience.

### DCC reference

- `DDServerProvider`
- `DdServerProtocol`
- `DdClient`

### What is already covered

- USB/PTP transport
- session open / reconnect concept
- basic camera device list flow

### What was missing and is now resolved

- verified OpenWrt rebuild on the Linux server
- stable deployment flow back to the router
- proof that the transport works under repeated live-view frame load

### Normalization goal

- `ddserver` must be boring and reliable.
- it should not know about UI or browser concerns.
- it should only provide a stable camera transport backbone.

### Verification

- build on the Linux server
- install on the router or target image
- confirm the daemon starts cleanly
- confirm the bridge can connect consistently

## Axis 2: Bridge

### Current state

- The bridge exists and already controls `AF` and `shutter`.
- The bridge now has a daemon-backed command path, so CGI requests can talk to one long-lived camera session instead of re-opening the world per request.
- It exposes `status`, `live-start`, `live-stop`, `af`, `shutter`, `frame`, and `recover`.
- It can keep a session and write frame artifacts.

### DCC reference

- `NikonBase`
- `LiveViewManager`
- `CameraPreset`
- `ICameraDevice`

### What is already covered

- Nikon command sequencing
- live view start / stop commands
- autofocus command
- shutter command
- frame capture entrypoint
- reconnect logic

### What is still worth improving

- live view behavior that feels even closer to DCC at the UI level
- stronger camera state modeling
- property synchronization and preset restoration
- DCC-style capability and prohibition checks
- better handling of live view conflicts and recovery
- explicit command-queue discipline for overlapping `AF`, `shutter`, and `frame` calls
- DCC-style session priming on connect:
  - `DeviceReady`
  - `CaptureInSdRam = true`
  - `LiveViewSelector` and `LiveViewStatus` reads
  - cautious live-view zoom ratio handling after start

### Normalization goal

- the bridge should become our Nikon command brain
- it should keep the camera session open
- it should expose clean HTTP/CGI behavior to the UI
- it should not drift back toward per-request ad hoc work

### Verification now achieved

- live view start returns the camera to a usable live state
- frames are real and consistent JPEGs
- AF and shutter remain available in the stabilized backend
- the daemon-backed session survives repeated browser-style requests
- the old 10-second boundary no longer tears the session down

## Axis 3: UI

### Current state

- the UI is already useful
- AF, shutter, status, live on/off, frame fetch, and save are wired
- status and performance text are visible

### DCC reference

- the DCC UI and live view behavior
- the stateful camera control model behind its windows

### What is already covered

- browser-based remote control
- visible connection and frame status
- portrait / landscape behavior
- live frame display area

### What is missing

- DCC-like state awareness
- obvious unsupported/blocked feature display
- preset UI
- stronger live view feedback
- more truthful distinction between preview polling and true live view

### Normalization goal

- the UI should reflect truth, not hope
- it should show whether the camera is actually in live view
- it should surface errors clearly enough that we can debug from the phone

### Verification

- confirm the UI does not hide stale cached assets
- confirm live state changes are visible immediately
- confirm the frame shown is the same frame reported by the bridge

## Priority Order

1. preserve the stabilized `ddserver` + bridge baseline
2. UI smoothness tuning
3. AF / shutter regression check
4. preset and property syncing
5. richer camera-state modeling

## Test Ladder

### Level 1

- bridge process starts
- `status` returns a valid JSON response

### Level 2

- `AF` works
- `shutter` works
- these still work after a live view cycle

### Level 3

- `live-start` actually puts the camera into live view
- `frame` returns a stable JPEG
- `live-stop` cleanly exits live view

### DCC-style live-view priming

The current bridge direction is to mirror DCC's Nikon startup behavior more closely:

1. connect the ddserver transport
2. open the device session
3. run `DeviceReady`
4. set `CaptureInSdRam` to the DCC default state
5. read live-view selector/status properties
6. start live view
7. handle `LiveViewImageZoomRatio` carefully without destabilizing live-view entry
8. request frames

This now behaves much more like a real camera session, but we learned that blindly writing `D1A3` back after start is unsafe on the D810 path.

### Level 4

- recover from a dropped session
- reconnect from a cold bridge start
- verify repeated frame requests do not corrupt the session

### Level 5

- add presets
- restore current camera state
- verify property synchronization against DCC expectations

## Linux Server Rebuild Note

We now have a Linux server at `192.168.0.23`.
That should be treated as the first-class rebuild environment for package verification.

The important detail we learned from the router is that the Opal is `siflower/sf19a28-fullmask`, not `ramips/mt7621`.
That means the rebuild target must be the Siflower SDK and the resulting package must be `mips_siflower`.

The rebuild workflow is now:

1. sync the working tree to the Linux box
2. rebuild `ddserver`
3. deploy to the router or runtime target
4. deploy the rebuilt binary to the router
5. run bridge checks
6. run UI checks
7. only then work on higher-level features
