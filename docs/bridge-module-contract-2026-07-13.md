# Bridge Module Contract

Date: 2026-07-13

This note extends the existing bridge responsibility contract with a module-level split.

The goal is still not feature removal.
The goal is to make the current working behavior easier to preserve, test, and change safely.

## Frozen Baseline

- `D810` physical body
- `ddserver` low-level transport
- `bridge` orchestration center
- `UI` presentation layer

The bridge remains the place where optimization and stabilization should happen first.
`ddserver` stays protected infrastructure.

## Why Moduleization

The current grouped design is good, but the file is still doing several jobs at once.
Moduleization adds stronger boundaries so that:

- live view can be protected from unrelated changes
- command execution can stay separate from query/state logic
- recovery can remain isolated from normal flow
- caches can be handled independently
- UI can stay thin and predictable

## Module Split Contract

These are the recommended bridge modules if the monolith is later split into files.

### 1. `transport`

Responsibilities:

- raw socket transport to `ddserver`
- packet/container framing
- protocol read/write helpers
- connection bootstrap and teardown
- hardware probe pass-through

Must stay isolated from:

- UI details
- live view orchestration
- cache handling
- recovery policy

### 2. `session`

Responsibilities:

- camera device selection
- session open / rehydrate
- device-ready flow
- transport session lifecycle
- active device bookkeeping

Must expose:

- `connect`
- `ensure_connected`
- `close`
- device/session state updates

### 3. `status`

Responsibilities:

- fast status query
- state cache load/save
- battery cache
- frame-age summary
- UI phase derivation

This module should remain cheap to call.

It should not perform heavy camera actions unless the query explicitly needs them.

### 4. `liveview`

Responsibilities:

- live view start
- live view stop
- frame production scheduling
- live frame cache
- live frame recovery
- refresh worker
- cached JPEG handoff

This is the most fragile user-facing path and should be treated as a protected module.

Only live-view-specific changes should touch this boundary.

The preferred flow is producer-consumer:

- `LIVE_START` enables the live session and background frame production
- the bridge or its live worker writes frames into the designated cache path
- the HTTP liveview endpoint only reads the latest valid JPEG
- `LIVE_STOP` shuts the producer down and clears the live session

### 5. `actions`

Responsibilities:

- AF
- shutter
- command locking
- short serialized camera actions

This module should remain small and predictable.

### 6. `recovery`

Responsibilities:

- reconnect
- maintain
- repair
- transport recovery
- degraded-state promotion and demotion

Recovery should not be merged into ordinary action flow.

### 7. `cache`

Responsibilities:

- frame cache
- state cache
- battery cache
- session cache
- captured preview/object cache

Cache types must stay separate.
Do not combine frame cache and status cache into a single shared bucket.

### 8. `helpers`

Responsibilities:

- JSON helpers
- file helpers
- lock helpers
- parsing helpers
- base64 helpers
- metadata helpers

This is shared infrastructure.
It should stay boring and dependency-light.

### 9. `entry`

Responsibilities:

- command router
- daemon entry point
- request dispatch

This module should be as thin as possible.

## Mapping From Current Grouping To Modules

The earlier grouping is still valid.
The moduleization just makes each group executable as an isolated unit.

1. Low-level transport -> `transport`
2. Session connection -> `session`
3. Status and state -> `status`
4. Live view and frame -> `liveview`
5. Single-shot command execution -> `actions`
6. Recovery and maintenance -> `recovery`
7. Captured still JPEG handling -> `cache`
8. Utility and base helpers -> `helpers`
9. Entry and routing -> `entry`

## Merge Rules

- Keep `liveview` and its frame path together.
- Keep `AF` and `shutter` together.
- Keep `status` separate from execution.
- Keep `recovery` separate from normal commands.
- Keep `transport` separate from session and UI.

## Stability Rules

- If a module change can affect live view, it needs extra caution.
- If a change crosses module boundaries, it should be discussed before editing.
- If a module split would risk working functionality, keep the code monolithic for now and only add the contract.

## Practical Refactor Order

1. Freeze the current grouped behavior.
2. Add module boundaries in comments and docs.
3. Extract `status`, `actions`, and `helpers` first if needed.
4. Keep `liveview` as a protected module.
5. Leave `ddserver` alone unless transport regressions return.

## Current Intent

We are not trying to rewrite the system all at once.
We are defining a safe split line so future work can happen without breaking:

- shutter
- AF
- live view
- status
- recovery
