# Bridge Responsibility Contract

Date: 2026-07-12

This note freezes the current agreement about how the D810 platform should be grouped and optimized.

The goal is not to remove features.
The goal is to keep the existing behavior, while tightening responsibility boundaries and reducing overlap.

## Core Principle

- Keep all working features.
- Separate responsibilities more strictly.
- Group by function and role.
- Protect the stable low-level transport layer.
- Optimize the bridge and UI first, not `ddserver`.

## Top-Level Architecture

1. `D810` physical body
2. `ddserver` low-level USB / PTP transport
3. `bridge` orchestration layer
4. `UI` presentation layer

The current working assumption is:

- `ddserver` is the transport foundation.
- `bridge` is the orchestration center.
- `UI` should show results, not make camera decisions.

## High-Level Functional Axes

1. Execution
2. Query
3. Recovery

These are the broadest program-level axes.

- Execution covers the user-triggered camera actions.
- Query covers fast state visibility.
- Recovery covers reconnect and repair behavior.

## Bridge Grouping Contract

The bridge is grouped by function and role into these buckets:

1. Low-level transport
2. Session connection
3. Status and state
4. Live view and frame
5. Single-shot command execution
6. Recovery and maintenance
7. Captured still JPEG handling
8. Utility and base helpers
9. Entry and routing

## Concrete Source Map

This is the current code-facing map for `remote-ui/cgi-bin/d810bridge.lua`.
It is not a behavior change.
It is a navigation guide so the same responsibility names can be used in code review, refactor discussion, and future extraction.

### `DdServerWire`

1. Transport bootstrap and connection lifecycle
2. Batch / transport action execution
3. Camera hardware detection and probing
4. PTP / response framing and packet parsing
5. Device session, property, and object access
6. Legacy live-view compatibility path
7. Modern live-view and capture path

### `BridgeSession`

1. Session state load / save / cache
2. Battery and probe state refresh
3. Recovery and reconnect
4. Status query and UI phase derivation
5. Live view start / stop
6. AF and shutter execution
7. Captured still JPEG handling
8. Live frame cache and refresh worker
9. Command router and entry dispatch

## Numbered Group Decisions

### 1. Low-level transport

Keep separate.

Includes the raw `ddserver` wire, container parsing, socket IO, and protocol framing.

Reason:

- This is the lowest layer.
- It should stay stable and boring.
- It should not be mixed with UI or camera behavior.

### 2. Session connection

Keep separate from transport, but grouped internally.

Includes camera detection, device list, connect, open session, rehydrate, and device-ready flow.

Reason:

- This is session orchestration, not raw transport.
- It is the connection layer that sits above `ddserver`.

### 3. Status and state

Keep separate.

Includes cached state, state save/load, battery cache, frame age, probe summary, and `status`.

Reason:

- This is the query layer.
- It should stay lightweight and fast.
- It must not be treated as command execution.

### 4. Live view and frame

Keep together.

Includes live view start/stop, frame fetch, frame cache, refresh worker, and direct JPEG handoff.

Current preferred shape:

- start live view once
- let background production keep the cache warm
- let the live worker write the cache path and let HTTP endpoints consume cached frames
- do not make the browser ask the camera for each image

Reason:

- These behaviors are tightly coupled.
- They represent one live preview responsibility.

### 5. Single-shot command execution

Keep together.

Includes `AF`, `shutter`, and the lock discipline that prevents command collisions.

Reason:

- These are short, direct camera actions.
- They must remain serialized against each other and against live view when needed.

### 6. Recovery and maintenance

Keep separate.

Includes reconnect, maintain, recover, connection revalidation, and repair decisions.

Reason:

- Recovery should not be blended into ordinary execution.
- Keeping it separate improves safety and makes failure handling easier.

### 7. Captured still JPEG handling

Keep separate.

Includes captured preview/object selection, cache write, cache read, and still-image retrieval.

Reason:

- This is not the same as the live frame stream.
- It is a distinct output path after shutter or capture.

### 8. Utility and base helpers

Keep separate as a shared foundation.

Includes JSON, file helpers, lock helpers, parsing helpers, base64, metadata, and general protocol utilities.

Reason:

- This layer is shared infrastructure.
- It should be factored cleanly when the code is split further.

### 9. Entry and routing

Keep minimal.

Includes the server entry point and the command router.

Reason:

- The entry point should only dispatch.
- It should not accumulate business logic.

## Current Merge / Split Decision

### Merge

- `Live view` and `frame` belong together.
- `AF` and `shutter` belong together.

### Split

- `transport` must stay separate from `session`.
- `status` must stay separate from execution.
- `recovery` must stay separate from normal commands.
- `ddserver` must stay separate from bridge logic.
- `helpers` should be kept out of the main command path when possible.

## Cache Contract

Caches must be managed independently.

1. Frame cache
2. State cache
3. Battery cache
4. Session state cache

These caches do not share the same lifetime and should not be treated as one object.

## Protection Rules For `ddserver`

`ddserver` is treated as protected infrastructure.

Do not optimize it first.
Do not frequently rewrite it.
Do not use it as the place to add new orchestration behavior.

The current working belief is:

- `ddserver` is closer to a USB cable than a feature layer.
- It should remain stable.
- If anything breaks, the first place to inspect is the bridge and UI layer above it.

## Stability Rules

- Keep the existing working features.
- Do not change behavior without checking for regressions.
- Prefer responsibility splits over feature removal.
- Prefer bridge simplification over `ddserver` changes.
- Prefer UI simplification over backend churn.

## Operational Bring-Up Rule

The current stable bring-up order is:

1. Power on and connect the `D810` first.
2. Keep the camera attached and ready.
3. Boot or reboot the Opal router after the camera is already on.
4. Let the bridge and session manager enumerate the device from that state.

Reason:

- The camera may not enumerate reliably if the Opal comes up first.
- The bridge can only recover a session after the USB / PTP device is visible to `ddserver`.
- This is a stability requirement, not just a convenience preference.
- If the camera is powered off before Opal boots, the bridge may report `camera_missing` until the next clean enumeration.

## Expected Direction

1. Freeze the stable `ddserver` baseline.
2. Refactor the bridge into clearer responsibility groups.
3. Simplify the UI to show only the intended controls.
4. Keep caches and recovery paths explicit.
5. Avoid touching `ddserver` unless a real transport issue returns.

## Summary

The current agreement is:

- `ddserver` is protected transport infrastructure.
- `bridge` is the orchestration center.
- `UI` is the presentation surface.
- Features stay intact.
- Responsibilities become stricter.
- Grouping is based on function and role.

## Moduleization Follow-Up

The next layer of the same agreement is captured in:

- [`docs/bridge-module-contract-2026-07-13.md`](./bridge-module-contract-2026-07-13.md)

That note keeps the same grouping, but turns it into a module split plan so future extraction can happen without breaking live view or the other working control paths.
