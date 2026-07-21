# digiCamControl Analytic

Recorded at: `2026-06-26 00:13:36 +09:00`

This document only covers the digiCamControl parts that matter for the D810 wireless platform:

- Live view frame retrieval
- AF
- Shutter
- ISO
- F-number / aperture
- Shutter speed
- Small set of useful camera settings

The goal is not to port digiCamControl. The goal is to use it as a known-working Nikon D810 command reference for our router-side adapter.

## Source Inspected

Local source path:

```text
_tmp_digicamcontrol
```

Relevant files:

```text
CameraControl.Devices/Nikon/NikonD810.cs
CameraControl.Devices/Nikon/NikonD600.cs
CameraControl.Devices/Nikon/NikonD600Base.cs
CameraControl.Devices/Nikon/NikonD800.cs
CameraControl.Devices/Nikon/NikonBase.cs
```

## D810 Inheritance Path

digiCamControl does not implement the D810 from scratch.

The D810 class inherits most behavior through this chain:

```text
NikonD810
  -> NikonD600
  -> NikonD600Base
  -> NikonD800
  -> NikonBase
```

Important implication:

```text
D810-specific file = mostly value tables
Inherited base files = actual Nikon command behavior
```

This is why digiCamControl can say D810 support is based on D600/D800-style logic. The cameras are not identical, but the PTP command surface for these core controls is similar enough that the D810 can reuse the same implementation with adjusted value tables.

## Core Nikon Commands

The following Nikon PTP operation codes are the important ones for our adapter:

```text
0x90C1  AfDrive
0x90C8  DeviceReady
0x90C0  InitiateCaptureRecInSdram
0x90CB  AfAndCaptureRecInSdram
0x90C2  ChangeCameraMode
0x9201  StartLiveView
0x9202  EndLiveView
0x9203  GetLiveViewImage
0x9204  MfDrive
0x9205  ChangeAfArea
0x9207  InitiateCaptureRecInMedia
```

The most important live-view trio is:

```text
StartLiveView     0x9201
GetLiveViewImage  0x9203
EndLiveView       0x9202
```

This is the route that avoids the bad `gphoto2 --capture-preview` behavior where the D810 physically clicks every preview frame.

## Core Properties

The useful property codes for our planned remote UI are:

```text
0x5007  Fnumber
0xD1A9  MovieFnumber
0x500F  ExposureIndex
0xD0B4  ExposureIndexEx
0xD1AA  MovieExposureIndex
0x500D  ExposureTime
0xD100  ShutterSpeed
0xD1A8  MovieShutterSpeed
0x5005  WhiteBalance
0x500E  ExposureProgramMode
0x5010  ExposureBiasCompensation
0xD1AB  MovieExposureBiasCompensation
0xD161  AFModeSelect
0xD061  AfModeAtLiveView
0x5004  CompressionSetting
0x500B  ExposureMeteringMode
0x500A  FocusMode
0xD1A2  LiveViewStatus
0xD1A6  LiveViewSelector
0xD10B  RecordingMedia
0xD1F0  ApplicationMode
0xD016  RawCompressionType
0xD149  RawCompressionBitMode
0xD032  ColorSpace
0xD183  ISOAutoHighLimit
```

For the first practical version, the most important settings are:

```text
ISO                 0x500F / 0xD0B4 / 0xD1AA
F-number            0x5007
Shutter speed       0xD100
White balance       0x5005
Exposure mode       0x500E
Exposure comp       0x5010
Metering            0x500B
Image quality       0x5004
Focus mode          0xD161 / 0xD061
```

## Live View Behavior

digiCamControl starts live view by:

```text
GetDevicePropValue(LiveViewStatus 0xD1A2)
DeviceReady(0x90C8)
StartLiveView(0x9201)
DeviceReady(0x90C8)
```

Then each live-view frame is requested by:

```text
GetLiveViewImage(0x9203)
```

For D600/D810-class handling, the returned data is treated as:

```text
384-byte live-view header
JPEG image bytes
```

So the adapter should serve the JPEG starting at byte offset:

```text
384
```

This is the key difference from the old gPhoto preview-loop:

```text
Bad current preview loop:
HTTP -> CGI -> launch gphoto2 -> capture preview -> physical click -> JPEG

Desired true live-view loop:
HTTP/WebSocket -> adapter -> existing PTP session -> GetLiveViewImage -> JPEG bytes from memory
```

## Live View Metadata

The D600Base implementation parses useful metadata from the 384-byte live-view header.

For D810-class handling, relevant offsets are:

```text
offset 8   LiveViewImageWidth
offset 10  LiveViewImageHeight
offset 12  ImageWidth
offset 14  ImageHeight
offset 24  FocusFrameXSize
offset 26  FocusFrameYSize
offset 28  FocusX
offset 30  FocusY
offset 48  Focused flag
offset 52  LevelAngleRolling
offset 56  LevelAnglePitching
offset 68  MovieIsRecording
```

For our first implementation, we only need:

```text
JPEG frame bytes
focus box position
focused / not-focused hint
```

The level-angle and movie fields can wait.

## AF

Autofocus is implemented with:

```text
DeviceReady(0x90C8)
AfDrive(0x90C1)
```

Focus area movement is implemented with:

```text
ChangeAfArea(0x9205, x, y)
```

Manual focus drive is implemented with:

```text
MfDrive(0x9204, direction, step)
```

digiCamControl maps manual focus steps roughly like this:

```text
small   10
medium  100
large   500
```

Near/far direction is encoded separately:

```text
far   -> direction 0x00000002
near  -> direction 0x00000001
```

Focus mode values:

Normal shooting focus mode:

```text
Property: AFModeSelect 0xD161

0  AF-S
1  AF-C
2  AF-A
3  MF hard
4  MF soft
```

Live-view focus mode:

```text
Property: AfModeAtLiveView 0xD061

0  AF-S
2  AF-F
3  MF hard
4  MF soft
```

For the phone UI, a good first set is:

```text
AF button
tap-to-focus area
optional MF near/far small-step buttons
```

## Shutter

digiCamControl has two main capture paths.

Capture with AF:

```text
DeviceReady(0x90C8)

if CaptureInSdRam:
  AfAndCaptureRecInSdram(0x90CB)
else:
  InitiateCapture(standard PTP capture)
```

Capture without AF:

```text
DeviceReady(0x90C8)
GetDevicePropValue(LiveViewStatus 0xD1A2)
```

If live view is active:

```text
if CaptureInSdRam:
  InitiateCaptureRecInSdram(0x90C0, 0xFFFFFFFF)
else:
  InitiateCaptureRecInMedia(0x9207, 0xFFFFFFFF, 0x0000)
```

If live view is not active, digiCamControl temporarily switches normal AF mode to soft manual focus:

```text
GetDevicePropValue(AFModeSelect 0xD161)
SetDevicePropValue(AFModeSelect 0xD161, 4)
InitiateCaptureRecInSdram(0x90C0, 0xFFFFFFFF) or standard capture
restore old AFModeSelect
```

For our field platform, the safer first shutter behavior is:

```text
If live view is running:
  use InitiateCaptureRecInMedia(0x9207, 0xFFFFFFFF, 0x0000)

If not live view:
  use the normal capture path, but keep the UI policy simple
```

Open question to validate on the actual D810:

```text
Which shutter path gives the best field behavior while preserving card recording and not destabilizing live view?
```

## ISO

The D810 file mainly defines ISO display/value tables.

D810 ISO values include:

```text
0x0020  Lo 1.0
0x0028  Lo 0.7
0x002d  Lo 0.5
0x0032  Lo 0.3
0x0040  64
0x0064  100
0x00C8  200
0x0190  400
0x0320  800
0x0640  1600
0x0C80  3200
0x1900  6400
0x3200  12800
0x3e80  Hi 0.3
0x4650  Hi 0.5
0x4e20  Hi 0.7
0x6400  Hi 1.0
0xC800  Hi 2.0
```

digiCamControl does not hardcode only these values into the UI. It reads the camera's current valid list using:

```text
GetDevicePropDesc(ExposureIndex 0x500F)
```

Then setting normal ISO uses:

```text
SetDevicePropValue(ExposureIndex 0x500F, value)
```

Movie ISO uses:

```text
GetDevicePropDesc(MovieExposureIndex 0xD1AA)
SetDevicePropValue(MovieExposureIndex 0xD1AA, value)
```

Recommendation:

```text
Always enumerate valid ISO values from the camera first.
Use the D810 ISO table only for display labels.
```

## F-number / Aperture

Normal aperture uses:

```text
GetDevicePropDesc(Fnumber 0x5007)
SetDevicePropValue(Fnumber 0x5007, value)
```

Movie aperture uses:

```text
GetDevicePropDesc(MovieFnumber 0xD1A9)
SetDevicePropValue(MovieFnumber 0xD1A9, value)
```

Values are represented as aperture multiplied by 100:

```text
280 -> f/2.8
400 -> f/4.0
560 -> f/5.6
800 -> f/8.0
```

digiCamControl only sets F-number when the camera mode allows it:

```text
A mode
M mode
```

Recommendation:

```text
Disable aperture changes in the UI unless mode is A or M.
```

## Shutter Speed

Normal shutter speed uses:

```text
GetDevicePropDesc(ShutterSpeed 0xD100)
SetDevicePropValue(ShutterSpeed 0xD100, value)
```

Movie shutter speed uses:

```text
GetDevicePropDesc(MovieShutterSpeed 0xD1A8)
SetDevicePropValue(MovieShutterSpeed 0xD1A8, value)
```

Bulb is represented as:

```text
0xFFFFFFFF
```

digiCamControl only sets shutter speed when the camera mode allows it:

```text
S mode
M mode
```

Recommendation:

```text
Disable shutter-speed changes in the UI unless mode is S or M.
```

## Other Useful Settings

White balance:

```text
GetDevicePropDesc(WhiteBalance 0x5005)
SetDevicePropValue(WhiteBalance 0x5005, uint16 value)
```

Exposure compensation:

```text
GetDevicePropDesc(ExposureBiasCompensation 0x5010)
SetDevicePropValue(ExposureBiasCompensation 0x5010, value)
```

Metering:

```text
GetDevicePropDesc(ExposureMeteringMode 0x500B)
SetDevicePropValue(ExposureMeteringMode 0x500B, uint16 value)
```

Image quality / compression:

```text
GetDevicePropDesc(CompressionSetting 0x5004)
SetDevicePropValue(CompressionSetting 0x5004, byte value)
```

Recording media:

```text
SetDevicePropValue(RecordingMedia 0xD10B, value)
```

These are useful, but they should come after the first live-view/AF/shutter/ISO/aperture loop works reliably.

## Adapter API Mapping

The router-side adapter can expose a simple product-level API:

```text
GET  /status
POST /live/start
GET  /live/frame.jpg
POST /live/stop
POST /af
POST /focus/point
POST /focus/manual
POST /shutter
GET  /settings
POST /settings/iso
POST /settings/aperture
POST /settings/shutter-speed
POST /settings/white-balance
POST /settings/exposure-compensation
POST /settings/metering
```

Internal mapping:

```text
/live/start              -> DeviceReady + StartLiveView
/live/frame.jpg          -> GetLiveViewImage, skip 384-byte header, return JPEG
/live/stop               -> DeviceReady + EndLiveView
/af                      -> DeviceReady + AfDrive
/focus/point             -> ChangeAfArea(x, y)
/focus/manual            -> MfDrive(direction, step)
/shutter                 -> live-view-aware capture command
/settings/*              -> GetDevicePropDesc + SetDevicePropValue
```

## ddserver Relationship

ddserver can carry the PTP packets over TCP, but it does not decide which Nikon commands to send.

So the layered architecture becomes:

```text
D810
  -> USB/PTP
  -> ddserver
  -> our D810 adapter
  -> phone browser UI
```

digiCamControl gives us the Nikon command reference.

ddserver gives us the OpenWrt-friendly transport backbone.

Our adapter becomes the product brain.

## Implementation Priorities

Recommended order:

1. Open camera through ddserver.
2. Send `DeviceReady`.
3. Send `StartLiveView`.
4. Send `GetLiveViewImage`.
5. Confirm that byte offset `384` begins a valid JPEG.
6. Serve the JPEG to the existing phone UI.
7. Add `EndLiveView`.
8. Add AF.
9. Add shutter.
10. Add ISO / F-number / shutter-speed settings.

The milestone that matters most:

```text
Get one silent D810 live-view JPEG through 0x9203.
```

If that works, the rest becomes engineering rather than uncertainty.

## Risks And Unknowns

Things to validate on the actual D810:

- Whether `GetLiveViewImage 0x9203` works through ddserver exactly as it does through digiCamControl's Windows stack.
- Whether the returned D810 live-view header is always 384 bytes.
- Whether `AfDrive 0x90C1` works reliably during live view.
- Which capture path best preserves card recording while live view is active.
- How often the camera returns busy states during rapid frame polling.
- Whether 1 fps is stable on the Opal.
- Whether 2-5 fps is possible without overheating, USB instability, or router CPU pressure.

## Current Conclusion

digiCamControl strongly supports the project direction:

```text
Do not keep using gPhoto preview capture as live view.
Use Nikon PTP live-view commands.
Use ddserver or a similar low-level transport.
Build our own small adapter and browser UI above it.
```

For the features we care about, digiCamControl is not mysterious. It mainly shows:

```text
which Nikon command to send
which property code to read/write
when to call DeviceReady
how to split live-view header from JPEG bytes
```

That is exactly the level of reference we need.
