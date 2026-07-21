# DigiCamControl Module Map for the D810 Backend

This note treats DigiCamControl as a reference implementation for the `ddserver`-backed D810 platform.
The goal is not to copy the UI, but to reuse the same functional boundaries:

- transport
- device abstraction
- Nikon command flow
- live view orchestration
- presets and property syncing

## 1. Transport Layer

These classes define how DigiCamControl talks to `ddserver` and how it opens a remote camera session.

- [`_tmp_digicamcontrol/CameraControl/Devices/Wifi/DDServerProvider.cs`](../_tmp_digicamcontrol/CameraControl/Devices/Wifi/DDServerProvider.cs)
- [`_tmp_digicamcontrol/CameraControl/Devices/TransferProtocol/DdServerProtocol.cs`](../_tmp_digicamcontrol/CameraControl/Devices/TransferProtocol/DdServerProtocol.cs)
- [`_tmp_digicamcontrol/CameraControl/Devices/TransferProtocol/DDServer/DdClient.cs`](../_tmp_digicamcontrol/CameraControl/Devices/TransferProtocol/DDServer/DdClient.cs)

What this layer is responsible for:

- connect to `ddserver`
- fetch the remote device list
- select a device
- open the camera session
- send raw PTP-like packets through the transport

## 2. Device Abstraction

This is the common camera interface that the rest of the application consumes.

- [`_tmp_digicamcontrol/CameraControl/Devices/ICameraDevice.cs`](../_tmp_digicamcontrol/CameraControl/Devices/ICameraDevice.cs)
- [`_tmp_digicamcontrol/CameraControl/Devices/BaseCameraDevice.cs`](../_tmp_digicamcontrol/CameraControl/Devices/BaseCameraDevice.cs)
- [`_tmp_digicamcontrol/CameraControl/Devices/CameraDeviceManager.cs`](../_tmp_digicamcontrol/CameraControl/Devices/CameraDeviceManager.cs)

Important responsibilities:

- expose a uniform camera API
- manage camera connection state
- surface property objects like ISO, shutter, aperture, white balance
- route events such as photo captured and disconnect

For our backend, this is the layer that should stay stable while lower-level transport changes.

## 3. Nikon Backend

This is the most important reference for the D810 path.

- [`_tmp_digicamcontrol/CameraControl/Devices/Nikon/NikonBase.cs`](../_tmp_digicamcontrol/CameraControl/Devices/Nikon/NikonBase.cs)
- [`_tmp_digicamcontrol/CameraControl/Devices/Nikon/NikonD810.cs`](../_tmp_digicamcontrol/CameraControl/Devices/Nikon/NikonD810.cs)

Key Nikon commands in `NikonBase`:

- `0x90C1` `AfDrive`
- `0x9201` `StartLiveView`
- `0x9202` `EndLiveView`
- `0x9203` `GetLiveViewImage`
- `0x9207` `InitiateCaptureRecInMedia`
- `0x90CB` `AfAndCaptureRecInSdram`
- `0x90C0` `InitiateCaptureRecInSdram`
- `0x90C7` `GetEvent`
- `0x90C8` `DeviceReady`

For the D810, `NikonD810` mostly specializes property tables, especially ISO values.

What this means for our bridge:

- the D810 feature set should be implemented as Nikon command sequencing on top of `ddserver`
- live view is not a generic HTTP feature, it is a Nikon camera flow

## 4. Live View Orchestration

This layer is the bridge between camera capabilities and UI behavior.

- [`_tmp_digicamcontrol/CameraControl/windows/LiveViewManager.cs`](../_tmp_digicamcontrol/CameraControl/windows/LiveViewManager.cs)

What it does:

- starts and stops live view
- fetches live view frames
- manages a temporary preset state when live view is active
- restores the previous camera state when live view stops

This is the reference for our browser-facing live view flow:

- `live/start`
- `live/frame`
- `live/stop`

## 5. Preset and State Sync

This is the reference for "save current state and restore later".

- [`_tmp_digicamcontrol/CameraControl/Core/Classes/CameraPreset.cs`](../_tmp_digicamcontrol/CameraControl/Core/Classes/CameraPreset.cs)

It captures and restores:

- mode
- compression
- exposure compensation
- metering
- f-number
- ISO
- shutter speed
- white balance
- focus mode
- live view zoom ratio
- capture in SDRAM
- selected advanced properties

This is the right model for our future preset module.

## 6. Feature Gating

These types are useful when deciding whether a feature is available or blocked.

- [`_tmp_digicamcontrol/CameraControl/Devices/Classes/CapabilityEnum.cs`](../_tmp_digicamcontrol/CameraControl/Devices/Classes/CapabilityEnum.cs)
- [`_tmp_digicamcontrol/CameraControl/Devices/Classes/OperationEnum.cs`](../_tmp_digicamcontrol/CameraControl/Devices/Classes/OperationEnum.cs)

Useful capability names:

- `LiveView`
- `LiveViewStream`
- `Bulb`
- `RecordMovie`
- `CanLockFocus`
- `CaptureInRam`
- `CaptureNoAf`
- `SimpleManualFocus`
- `Zoom`

Useful operations:

- `Capture`
- `RecordMovie`
- `AutoFocus`
- `ManualFocus`
- `LiveView`

## 7. Property Model

These are the objects that carry camera values and enabled/disabled state.

- [`_tmp_digicamcontrol/CameraControl/Devices/Classes/PropertyValue.cs`](../_tmp_digicamcontrol/CameraControl/Devices/Classes/PropertyValue.cs)
- [`_tmp_digicamcontrol/CameraControl/Devices/Classes/BaseFieldClass.cs`](../_tmp_digicamcontrol/CameraControl/Devices/Classes/BaseFieldClass.cs)

Why this matters:

- DigiCamControl does not treat camera settings as raw strings only
- it keeps metadata about valid values and current errors
- that makes it easier to restore presets and detect unsupported actions

## 8. Recommended Backend Module Split For Our Project

Based on the DigiCamControl reference, the backend should be split like this:

1. `transport`
- speaks to `ddserver`
- owns socket/session handling and reconnect

2. `camera-core`
- stores the active camera session
- exposes status, ready checks, and property reads/writes

3. `nikon-d810`
- implements Nikon command sequences
- handles live view, AF, shutter, device-ready, and frame extraction

4. `preset`
- snapshots and restores camera state

5. `http-api`
- exposes `status`, `live/start`, `live/frame`, `live/stop`, `af`, `shutter`, `recover`

## 9. Immediate Priority Order

If we are using DigiCamControl as the functional reference, the build order should be:

1. connect and session open
2. status and readiness
3. live view start/stop
4. frame fetch and decode
5. autofocus
6. shutter capture
7. preset save/restore
8. property syncing and advanced settings

That order keeps the work aligned with what DigiCamControl already proves is possible.
