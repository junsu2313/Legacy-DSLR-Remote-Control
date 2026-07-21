# DSLR Wireless Platform Notes

## Project Goal

Build a field-ready wireless control platform for a Nikon D810 using a GL.iNet Opal router running OpenWrt.

The target field structure is:

- D810 connected to the Opal router over USB.
- Sub phone acts as a handheld remote/display.
- Main phone or other uplink provides network access when outside.
- Home PC later receives images, evaluates them with Codex, adjusts presets, and gives feedback.

The working assumption from this point forward is outdoor/field use, not a desk-only network.

## Current Hardware And Network Idea

- Camera: Nikon D810.
- Router: GL.iNet Opal / GL-SFT1200, OpenWrt-based.
- Remote device: Galaxy S10-class phone is sufficient for browser UI control.
- Control UI: served from the Opal router over HTTP.
- Current router address: `192.168.8.1`.

The phone should connect to the Opal Wi-Fi and open the router-hosted remote UI. The router should become the camera control hub.

## What Was Built

A simple browser-based remote UI was built and deployed to the router.

Important deployed paths:

- `/cgi-bin/remote-ui`
- `/remote-ui/ui.html`
- `/cgi-bin/status`
- `/cgi-bin/action`
- `/cgi-bin/frame-update`
- `/cgi-bin/liveview`
- `/cgi-bin/liveview-start`
- `/cgi-bin/liveview-stop`

Current UI behavior:

- Portrait mode is treated as handheld remote mode.
- Landscape mode is treated as monitor/preview mode.
- Buttons exist for AF, Shutter, Capture/Preview, Save, Live On, Live Off, and Status.
- The UI was cache-busted with `v=20260625-2` after front-end changes.

## What Worked

The router can detect the D810:

```text
Nikon DSC D810 usb:001,003
```

The following backend endpoints worked during testing:

- `status`: camera detection returned true.
- `af`: autofocus command returned ok.
- `shutter`: camera captured an image on the camera card.
- `frame-update`: produced a preview JPEG file.
- `liveview`: served the generated JPEG over HTTP.
- `download`: copied the current preview JPEG to `/www/remote-ui/last.jpg`.
- `live-on` / `live-off`: gPhoto commands returned success in some cases.

The UI/backend wiring was fixed after finding that the front-end was not actually starting a frame loop when Live On was pressed.

## Problems Found

### 1. The First UI Was Not Really Connected Correctly

The early UI had buttons and labels, but the behavior was misleading.

Problems included:

- Old cached UI could still appear on the phone.
- Buttons did not clearly show backend errors.
- Live On only called a backend action and did not start a repeated frame update loop.
- Some old labels implied automatic live view even when only manual preview capture existed.

Fixes made:

- Added a new `ui.html`.
- Redirected `/cgi-bin/remote-ui` to the new UI.
- Added cache-busting query string.
- Added visible status/error updates.
- Added front-end frame loop logic for 0.5fps preview polling.

### 2. 2-Second Preview Loop Was Not Real Live View

The original idea was to update the displayed frame every 2 seconds.

At first this was treated as "live view", but discussion and testing showed that this is not correct.

Current `gphoto2 --capture-preview` behavior on the D810:

- It creates a preview JPEG.
- It does not appear to create saved files on the camera card.
- However, the camera makes a physical "click" sound.
- Therefore it is not the desired silent sensor live-view stream.

Conclusion:

This should not be called true live view. It is better described as a preview capture loop or preview polling.

### 3. `viewfinder=1` Did Not Stay Enabled Through gPhoto CLI

Testing showed:

```sh
gphoto2 --set-config /main/actions/viewfinder=1
gphoto2 --get-config /main/actions/viewfinder
```

The value returned to:

```text
Current: 0
```

This means the current gPhoto CLI path is not successfully keeping the D810 in a usable live-view state.

### 4. gPhoto CLI Per Request Is Fragile

The CGI approach starts a new `gphoto2` process for many operations.

This caused several issues:

- USB device busy errors.
- Camera session conflicts.
- Occasional OpenWrt memory pressure.
- `gphoto2` processes killed by OOM.
- Need for locks to prevent overlapping commands.

Mitigations added:

- `/tmp/d810-camera.lock` lock directory.
- Cleanup of unrelated `usbmuxd`.
- Avoid overlapping AF/shutter/frame update operations.

These mitigations help but do not change the fundamental limitation.

### 5. Shutter Download Was Not Reliable

`gphoto2 --capture-image-and-download` produced a camera capture but failed during download:

```text
New file is in location /capt0000.nef on the camera
You need to specify a folder starting with /store_xxxxxxxxx/
ERROR: Could not get image.
```

The current safer behavior:

- `Shutter` captures on the camera card only.
- `Save` copies the current preview JPEG to `last.jpg`.

Original full image transfer is not solved yet.

## digiCamControl Investigation

digiCamControl was inspected as a reference implementation because it supports Nikon D810 live view on Windows.

Source inspected locally:

- `_tmp_digicamcontrol/CameraControl.Devices/Nikon/NikonD810.cs`
- `_tmp_digicamcontrol/CameraControl.Devices/Nikon/NikonD600Base.cs`
- `_tmp_digicamcontrol/CameraControl.Devices/Nikon/NikonBase.cs`

Important finding:

digiCamControl does not rely on repeatedly launching `gphoto2 --capture-preview`.

It uses Nikon-specific PTP/MTP commands:

```text
StartLiveView     0x9201
EndLiveView       0x9202
GetLiveViewImage  0x9203
DeviceReady       0x90C8
```

For D810-class cameras, it calls:

```csharp
StillImageDevice.ExecuteReadData(CONST_CMD_GetLiveViewImage)
```

The returned live-view data includes a header before the JPEG image bytes. In the D810/D600-class implementation, the header size is treated as 384 bytes.

This is much closer to the desired true live-view frame path.

## Main Technical Conclusion

The current gPhoto CGI preview loop is not the final architecture.

The project should move toward a small router-side D810 daemon:

```text
D810 USB
  -> d810d on OpenWrt
  -> HTTP API
  -> S10 browser UI
```

The daemon should hold the camera session open instead of launching `gphoto2` for every request.

Desired future API:

- `/status`
- `/live/start`
- `/live/frame.jpg`
- `/live/stop`
- `/af`
- `/shutter`
- `/recover`

## Why The Next Step Is Harder

The difficult part is not the UI. The difficult part is replacing gPhoto CLI convenience with direct camera control.

## DigiCamControl As Reference

The functional reference map for the `ddserver`-first backend is documented here:

- [`docs/digicamcontrol-module-map.md`](../docs/digicamcontrol-module-map.md)

That note breaks the implementation into transport, camera core, Nikon command flow, live view orchestration, presets, and property syncing.

Direct Nikon PTP implementation requires:

- Opening and maintaining a USB/PTP session.
- Sending Nikon vendor commands directly.
- Parsing `GetLiveViewImage` data.
- Skipping the live-view header and serving JPEG bytes.
- Handling camera busy states.
- Preventing AF/shutter/live-view conflicts.
- Recovering if the daemon crashes while live view is active.
- Building and deploying on OpenWrt with limited memory.

However, this is not blind research. digiCamControl already shows the D810 command path and data layout.

## Recommended Direction

Do not port all of digiCamControl.

digiCamControl is Windows/.NET/WPF/WPD-based and is too large for the Opal router.

Instead, use digiCamControl as a reference and build a minimal OpenWrt-native D810 engine.

Recommended plan:

1. Create a tiny proof of concept that sends Nikon `StartLiveView`, `GetLiveViewImage`, and `EndLiveView`.
2. Prove that `GetLiveViewImage 0x9203` returns a silent live-view JPEG from the D810.
3. If successful, wrap it as `d810d`.
4. Connect existing phone UI to `d810d`.
5. Add AF and shutter only after live-view frame retrieval is stable.
6. Add recovery paths and watchdog behavior.

## Current Decision

The current preview-loop UI is useful only as a temporary remote-control MVP.

For the real platform goal, the next meaningful milestone is:

```text
Get one real D810 live-view frame using Nikon PTP command 0x9203 without triggering the physical click.
```

## Implementation Milestone

The working code now has a ddserver-first bridge in `remote-ui/cgi-bin/d810d.py`.

What it does:

- Keeps a ddserver TCP camera session open in `serve` mode.
- Exposes the current D810 workflow as `status`, `live-start`, `live-stop`, `af`, `shutter`, and `frame`.
- Saves live-view JPEG frames to `/tmp/d810-live.jpg`.
- Lets the existing CGI scripts fall back to gPhoto2 only when the ddserver path is not available yet.

The current CGI entrypoints now prefer that bridge, so the UI is aligned with the ddserver-backed architecture described above.

Typical daemon start on the router:

```sh
python3 /www/remote-ui/cgi-bin/d810d.py serve --bind 127.0.0.1 --port 8089
```

If Python is not available on the target image yet, the CGI endpoints still fall back to the older gPhoto2 path until the router package set is updated.

## Cross-Build Plan

Because the Opal currently has no `gcc`, `g++`, `cmake`, `make`, or `git`, the practical build path is to cross-compile on the PC with an OpenWrt SDK that matches the router target.

Staging helper:

```powershell
.\scripts\stage-ddserver-openwrt.ps1 -SdkRoot C:\path\to\openwrt-sdk
```

Then from inside the SDK root:

```sh
make package/ddserver/compile V=s
```

The resulting `ipk` can then be copied to the Opal and installed with `opkg install`.

If that succeeds, the project can proceed toward a real wireless DSLR monitor/controller.

If that fails on OpenWrt, fallback options are:

- Use HDMI capture for true live view.
- Move camera-control computation to a stronger Linux device.
- Use a PC-side digiCamControl style bridge instead of the Opal for live view.

## Timestamped Discussion: ddserver/PTP Direction

Recorded at: `2026-06-25 23:52:15 +09:00`

After further discussion, the architecture direction shifted from "write all low-level Nikon USB/PTP handling ourselves" toward using `ddserver` as the low-level camera communication backbone.

### Why ddserver Matters

`ddserver` is not just a random example. It is an existing OpenWrt-oriented DSLR USB/PTP network server.

It was originally used with small OpenWrt routers such as TP-Link MR3040 / WR703N, which were weaker than the GL.iNet Opal. The local source inspection showed that ddserver is small:

- Source size: about 46 KB.
- Main implementation files: `communicator.cpp`, `main.cpp`.
- Core dependencies: `libusb-1.0`, `libstdcpp`, `libgcc`, `pthread`.
- It already includes an OpenWrt package `Makefile`.

Therefore, resource usage is unlikely to be the main blocker on the Opal. The larger issues are build compatibility, USB ownership, and protocol integration.

### Revised Layer Model

The project can now be thought of as layered:

```text
D810
  -> USB / PTP
  -> ddserver
  -> PTP Adapter / Camera API Layer
  -> HTML / JS UI
```

More explicitly:

```text
Low-level USB/PTP
  -> ddserver
  -> PTP-to-HTTP/WebSocket adapter
  -> mobile browser UI
```

The important clarification is that HTML is not replaced by PTP. HTML remains the user interface. PTP becomes the camera-control language behind the UI.

Example mapping:

```text
HTML/UI command      Adapter translation
--------------       -------------------
POST /live/start  -> Nikon PTP StartLiveView 0x9201
GET /live/frame   -> Nikon PTP GetLiveViewImage 0x9203
POST /live/stop   -> Nikon PTP EndLiveView 0x9202
POST /shutter     -> Nikon capture command
POST /af          -> Nikon AF command
```

### Role Of ddserver

For this project, ddserver should be treated as the component that actually talks to the camera.

Its likely responsibilities:

- Open the USB camera device.
- Claim the USB imaging interface.
- Maintain low-level PTP transport.
- Forward PTP packets between network and camera.
- Handle the most fragile USB connection layer.

Our higher-level code should focus on:

- Camera command policy.
- Live view UX.
- AF/shutter sequencing.
- Browser-facing HTTP/WebSocket API.
- Remote shooting workflow.
- Image transfer and PC/Codex feedback loop.

In short:

```text
ddserver = camera communication backbone
adapter/UI = product behavior
```

### gPhoto's New Role

gPhoto should not remain the main backend for the final platform.

Good remaining uses for gPhoto:

- Camera detection.
- Quick diagnostics.
- Listing camera configuration.
- Emergency manual tests.

Areas where gPhoto should be replaced:

- True live view.
- Repeated frame retrieval.
- Stable field remote operation.
- Long-running camera session management.

Reason:

- `gphoto2 --capture-preview` causes a physical click on the D810.
- `viewfinder=1` did not stay enabled through the current gPhoto CLI path.
- Running `gphoto2` per CGI request repeatedly claims USB and causes fragility.

Therefore:

```text
gPhoto = diagnostic tool
ddserver/PTP = platform backend direction
```

### Is ddserver Enough By Itself?

Not completely.

ddserver is not a browser HTTP API. It is closer to a PTP-over-network bridge. qDslrDashboard acts as the client that understands what PTP commands to send.

For our platform, we likely need an additional adapter layer:

```text
Browser UI
  -> HTTP/WebSocket adapter
  -> ddserver
  -> D810
```

This adapter is where our D810-specific commands and user-facing API live.

Possible implementation options:

- Write a small ddserver client adapter.
- Fork ddserver and add a small HTTP API.
- Use ddserver source as a reference and build a combined `d810d`.

The current preferred direction is:

```text
ddserver as low-level backbone + our adapter as high-level camera API
```

### Performance Expectation

The current gPhoto/CGI preview loop is slow because each frame requires:

```text
HTTP request
  -> CGI
  -> launch gphoto2
  -> claim USB
  -> request preview
  -> write file
  -> serve file
```

With ddserver/PTP, the target path becomes:

```text
HTTP request
  -> adapter
  -> existing PTP session through ddserver
  -> GetLiveViewImage
  -> return JPEG from memory
```

Expected practical FPS:

- Current gPhoto CGI preview: around 0.5 fps and not the desired true live view.
- ddserver/PTP adapter: stable 1 fps should be a realistic first target.
- If things go well: 2-5 fps may be possible.
- 15-30 fps should not be expected from this DSLR/OpenWrt path.

The important goal is not cinematic smoothness. It is enough responsiveness for composition, focus checking, and remote shooting.

### Current Architectural Decision

The project should not become a full Nikon USB/PTP driver project unless necessary.

The better maker-platform direction is:

```text
Use ddserver to avoid owning the fragile low-level USB/PTP layer.
Build the D810 wireless product experience above it.
```

This keeps the project aligned with the original goal:

```text
Make the D810 more useful, wireless, and powerful in the field.
```

Rather than accidentally turning it into:

```text
Write and maintain a complete Nikon USB/PTP stack.
```

## Analysis Documents

Detailed target-specific analysis documents should live outside this README and use the naming rule:

```text
<target>_analytic.md
```

Current analysis documents:

- [ddserver_analytic.md](./ddserver_analytic.md)
- [digicamcontrol_analytic.md](./digicamcontrol_analytic.md)
- [ddserver-bridge-ui-normalization.md](../docs/ddserver-bridge-ui-normalization.md)
