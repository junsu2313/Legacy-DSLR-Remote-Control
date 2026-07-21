# OpenAI Build Week Project History and Provenance

Status: Draft for Devpost submission
Project: Wireless Nikon D810 Camera Platform
Prepared: 2026-07-21

## Purpose

This document separates the project history before the Hackathon Submission Period from the work added during the Submission Period. The project existed before the Hackathon, so the submission must clearly identify the meaningful extension made after July 13, 2026 and provide evidence of Codex and GPT-5.6 use during that period.

## Project in One Sentence

The project turns a Nikon D810 and a GL.iNet Opal router into a wireless field camera system with browser-based live view, autofocus, shutter control, captured-image preview, and automatic session recovery.

## Executive Timeline

| Date | Development stage | Main result | Model boundary |
|---|---|---|---|
| 2026-06-23 | Concept before hardware | Defined the wireless DSLR field-camera direction | Pre-project concept |
| 2026-06-25–06-26 | Hardware and transport investigation | D810, Opal, ddserver/PTP, and bridge architecture | GPT-5.4 / GPT-5.4 mini |
| 2026-06-27–06-30 | First integrated prototype | Camera detection, AF, shutter, live view, and JPEG serving | GPT-5.4 / GPT-5.4 mini |
| 2026-06-30 | First live-view snapshot | Replaced shutter-like preview polling with WebSocket streaming; approximately 2 FPS baseline and a temporary 15 FPS result after reboot | GPT-5.4 / GPT-5.4 mini |
| 2026-06-30–07-17 | Reliability engineering | Session manager, live-view session separation, numbered session logs, repair/guardian logic, observability, locks, and regression baselines | GPT-5.4 / GPT-5.4 mini |
| 2026-07-18 | Second live-view optimization | Approximately 20 FPS normal operation and 26.3 FPS peak | GPT-5.6 Sol after 11:40 KST |
| 2026-07-19 | Captured-image preview optimization | Earlier optimized payload reduced approximately 19–20 seconds to around 2 seconds; the current 9 MP Fine JPEG path was revalidated at approximately 5.2 seconds | GPT-5.6 Sol |
| 2026-07-20 | Field connectivity and memory efficiency | Tailscale connectivity verified end-to-end; Opal service footprint and RAM usage reduced | GPT-5.6 Sol |
| 2026-07-21 | Preview-path revalidation | Current RAW + Fine JPEG configuration produced a 6.42 MB, 9 MP JPEG and completed end-to-end delivery in approximately 5.2 seconds | GPT-5.6 Sol |

The timeline is complete through July 21, with the current preview measurement tied to an end-to-end transfer from the Opal to the main computer.

## Phase 0 — Concept and Architecture Sketch

### 2026-06-23: Pre-hardware concept phase

Before the hardware was available, the project existed as a product and architecture concept. The work at this point was primarily system framing: wireless DSLR control, a router-hosted UI, a mobile remote, a camera bridge, and a future image-review workflow.

This phase should be described as prior ideation and product direction, not as the working implementation submitted to the Hackathon.

Evidence:

- User-provided project history: the system concept was being developed before the camera hardware arrived.
- `DSLR_Wireless/README.md`: project goal, target hardware, field-use model, and proposed architecture.

## Phase 1 — Hardware Investigation and First Working Path

### 2026-06-25 to 2026-06-26: Camera and transport investigation

Once the hardware was available, the project moved from architecture sketches to implementation. The work investigated Nikon D810 control, gPhoto behavior, digiCamControl as a reference, Nikon PTP live-view commands, and `ddserver` as an OpenWrt-compatible USB/PTP transport layer.

Key decisions:

- Treat `ddserver` as the low-level USB/PTP transport.
- Put Nikon command sequencing and browser-facing behavior in a bridge layer.
- Keep the UI focused on remote shooting rather than reproducing a desktop camera-control application.
- Move away from gPhoto preview polling as the long-term live-view architecture.

Evidence:

- `DSLR_Wireless/ddserver_analytic.md`
- `DSLR_Wireless/digicamcontrol_analytic.md`
- `DSLR_Wireless/README.md`

## Phase 2 — Working D810 Remote Prototype

### 2026-06-27 to 2026-06-30: First integrated system

The first integrated path connected the D810, Opal router, bridge scripts, and browser UI. The system demonstrated camera detection, autofocus, shutter control, live-view startup, repeated frame retrieval, and JPEG serving.

On June 30, the project froze a known-good baseline. The baseline recorded a working `ddserver` transport, a D810 bridge, a browser UI, approximately 2.0–2.3 FPS fresh-frame production, and regression checks for live view after a 12-second wait.

Evidence:

- `docs/opal-liveview-frozen-baseline-2026-06-30.md`
- `docs/opal-routing-freeze-2026-06-30.md`
- `docs/variant-workflow-2026-06-30.md`

## Phase 3 — Product Surface and Remote Workflow

### 2026-07-01 to 2026-07-12: Usable remote-control experience

The system expanded from a technical live-view proof into a usable remote-control flow: mobile-oriented UI behavior, capture preview, image delivery, command serialization, session handling, and recovery behavior.

The architectural responsibility split was then made explicit:

```text
D810 -> ddserver transport -> bridge orchestration -> browser UI
```

The bridge was organized around transport, session, status, live view, actions, recovery, captured JPEG handling, cache, helpers, and routing. This preserved the working behavior while making later changes safer.

Evidence:

- `docs/bridge-responsibility-contract-2026-07-12.md`
- `docs/bridge-module-contract-2026-07-13.md`
- `docs/remote-control-priority-snapshot-2026-07-11.md`
- `docs/v2-liveview-stability-snapshot-2026-07-11.md`

## Phase 4 — Hackathon Submission-Period Extension

### 2026-07-13 to 2026-07-19: Meaningful extension for OpenAI Build Week

This is the part that should be presented as the Hackathon contribution. The project was extended from a working wireless camera prototype into a more coherent, failure-aware shooting experience.

The submission-period extension includes:

1. Session retention and recovery behavior for browser, bridge, WebSocket, and PTP failure states.
2. Explicit separation of AF and shutter actions while preserving live view where appropriate.
3. Captured JPEG preview and full-size image delivery as a distinct path from live frames.
4. Recovery guards, cache boundaries, command locks, and runtime-health checks.
5. UI behavior for degraded, recovering, ready, and camera-action states.
6. Contract checks covering live-view recovery, AF/shutter behavior, captured-image streaming, and mobile preview flow.

Evidence:

- `docs/deployment-planned-feature-1-session-retention-recovery-2026-07-19.md`
- `docs/deployment-planned-feature-1-liveview-af-shutter-2026-07-19.md`
- `docs/dependency-stability-foundation-2026-07-19.md`
- `docs/liveview-semi-os-operational-record-2026-07-19.md`
- `scripts/test-liveview-action-contract.ps1`
- `docs/0719-prototype-journey-record.md`

## Codex Conversation Evidence by Development Phase

The following Codex thread IDs are the project-scoped conversation records found under `E:\Underlab_APP\Camera`. Each ID can be opened in the Codex app and reviewed for the original request, reasoning, tool activity, file changes, tests, and deployment notes.

| Date | Codex thread ID | Conversation focus | Related project evidence |
|---|---|---|---|
| 2026-06-23 | `019ef0c6-116b-7100-8ece-9c65edfcbc18` | digiCamControl and camera-control direction research | `DSLR_Wireless/digicamcontrol_analytic.md` |
| 2026-06-25 | `019efddd-dd1a-7451-983a-55b6c8c800dc` | Initial wireless D810 platform architecture | `DSLR_Wireless/README.md` |
| 2026-06-26 | `019f029b-55bc-7671-b378-0ec8bb286366` | ddserver-based wireless platform implementation | `DSLR_Wireless/ddserver_analytic.md`, OpenWrt build artifacts |
| 2026-06-28 | `019f0d2b-c357-73b3-ad05-00f7154b665e` | ddserver, bridge, and HTTP/UI integration documentation | `docs/ddserver-bridge-ui-normalization.md` |
| 2026-06-30 | `019f17af-0abd-7762-990b-a48ba6ffeb7a` | Live-view path optimization | `docs/opal-liveview-frozen-baseline-2026-06-30.md` |
| 2026-07-02 | `019f1ed6-eded-72f3-94a7-7290d5a38ed8` | Remote-control UX improvement | `remote-ui` variants and UI snapshots |
| 2026-07-12 | `019f55d5-27f0-7693-bf80-8d5eb3979df9` | Full-system optimization review and candidate improvements | `docs/remote-control-priority-snapshot-2026-07-11.md` |
| 2026-07-15 | `019f65d7-495b-7a70-9700-11cae581e0ee` | Function normalization and live-view stabilization | `remote-ui/cgi-bin`, live-view recovery changes |
| 2026-07-17 | `019f6dbf-5697-7112-9681-bfbc7f8edebe` | Session-to-PTP command-flow diagnosis and tracing | session logs, `0716-1.html`, bridge/action tracing |
| 2026-07-18 | `019f7319-7ed2-7420-9023-2954a743d531` | Camera boot, session condition, and command-loop stabilization | `docs/0719-planned-work-2026-07-19.md` |

### Primary Hackathon Contribution Thread

Only the post-cutoff sessions need to be submitted as Codex evidence. The strongest primary candidate is the July 18 session:

```text
019f7319-7ed2-7420-9023-2954a743d531
```

This thread begins at 2026-07-18 11:41 KST, immediately after the declared GPT-5.6 cutoff, and contains the camera boot, session-condition, and command-loop stabilization work. It should be the primary `/feedback Codex Session ID` candidate.

The current documentation thread, `019f7a51-75ca-7d32-b95a-42d0542a7ad0`, may be included as a supporting session if needed. Earlier sessions do not need to be submitted as Codex evidence; they remain in this document only to explain the project's provenance.

## What Was Prior Work vs. What Is the Hackathon Contribution

| Area | Prior work | Submission-period contribution |
|---|---|---|
| Product idea | Wireless DSLR field-control concept | Refined into a focused remote shooting story |
| Hardware path | D810 + Opal + USB/PTP investigation | Demonstrated and stabilized as the submission path |
| Live view | Working ddserver-backed frame path | Recovery-aware live-view behavior and UI state handling |
| Camera actions | AF and shutter working | Independent serialized actions with explicit UI semantics |
| Images | Preview/JPEG experiments | Captured preview and full-size JPEG delivery flow |
| Reliability | Baseline and manual recovery work | Session retention, guardian behavior, and contract checks |
| Documentation | Architecture and technical notes | Submission-ready provenance, demo, and Codex contribution record |

## Live-View Optimization Lineage

The live-view work has two distinct milestones and should not be presented as one continuous undocumented claim.

### Milestone 1 — 2026-06-30: First live-view architecture

The first major optimization replaced the earlier approach of repeatedly creating preview images through shutter-like capture behavior with a WebSocket-based streaming path. The first stable result was approximately 2 FPS, and a router reboot later produced a temporary result around 15 FPS. This became the first live-view snapshot and established the baseline for further optimization.

Models used for this milestone: GPT-5.4 and GPT-5.4 mini.

Evidence:

- `019f17af-0abd-7762-990b-a48ba6ffeb7a` — Codex thread titled `라이브뷰 경로 최적화`
- `docs/opal-liveview-frozen-baseline-2026-06-30.md`

### Milestone 2 — 2026-07-18: Second live-view optimization

Before the second optimization pass, the project separated live-view sessions from ordinary camera sessions. Sessions that needed to persist live view were retained, while sessions that did not need live view were prevented from carrying live-view state forward. Sessions were numbered and their logs were preserved, and a proper observation path was attached so UI actions, bridge commands, PTP behavior, frame production, and recovery could be correlated.

With that observability and session separation in place, GPT-5.6 Sol was used to optimize the live-view path. It improved the live-view path to approximately 20 FPS in normal operation, with a measured peak of 26.3 FPS. This is the strongest measurable performance contribution for the Hackathon submission.

Models used for this milestone: GPT-5.6 Sol.

This milestone should be described as a meaningful extension of the existing prototype: the first pass proved that a wireless live-view stream was possible; the second pass made the stream substantially more responsive and closer to a practical remote-camera experience.

### Milestone 3 — 2026-07-19: Captured JPEG preview optimization

After live view reached the 20–26.3 FPS range, the next bottleneck was the captured-image preview path. A roughly 30-megapixel-class JPEG took approximately 19–20 seconds to become visible in the Opal-served UI, which made the shooting workflow feel disconnected even though live view was responsive.

GPT-5.6 Sol was then used to optimize the preview loop. The path was changed to use an approximately 9-megapixel preview representation and measured chunk-size tuning. An earlier 2.83 MB test payload completed in approximately 2.37–2.72 seconds. On 2026-07-21, the current RAW + Fine JPEG configuration was revalidated with a 6.42 MB, 9 MP JPEG: first byte arrived in approximately 1.51 seconds and end-to-end delivery completed in approximately 5.21 seconds. The current public performance figure is therefore approximately 5.2 seconds, while the earlier 2-second-class result remains recorded as a historical test condition.

This creates a clear two-path product experience:

```text
Live view: fast, continuous, composition-oriented stream
Captured preview: smaller, quickly delivered confirmation image
```

The full-size image path remains a separate concern from the fast preview path.

## Phase 5 — 2026-07-20: Field Connectivity and Memory Efficiency

### Verified final development-day result

The Opal wireless camera platform was connected to the main computer through Tailscale. This extends the project from a local camera remote into a field workflow in which the Opal can reach the main computer without requiring a fixed public IP or manual network reconfiguration.

The planned network path is:

```text
D810 -> Opal camera platform -> Tailscale -> main computer
```

The same phase included a broad RAM-usage optimization pass on the Opal. The combined Tailscale binary was reduced from 24.4 MiB to 16.5 MiB, steady service RSS from approximately 28.6 MiB to approximately 18.1 MiB, and post-optimization MemAvailable was approximately 49.9 MiB. Tailscale ping, camera HTTP access, and SSH were verified end-to-end, while the camera API and existing camera services remained available.

Model attribution for this phase: GPT-5.6 Sol was used extensively across the final optimization portfolio: live-view pipeline optimization, captured-image preview pipeline optimization, and Opal RAM-usage optimization. This included diagnosis, optimization proposals, implementation work, and verification loops. The project owner retained final responsibility for choosing the optimization scope, accepting changes, and validating behavior on the Opal.

This phase is verified against the July 20 service and memory-optimization records. The submission can therefore describe the connectivity and memory results as completed work, while keeping the measured values tied to the documented test environment.

### GPT-5.6 Sol contribution boundary

For submission purposes, the GPT-5.6 Sol contribution should be presented as one connected optimization effort beginning at the declared cutoff of 2026-07-18 11:40 KST:

```text
live-view pipeline -> captured-image preview pipeline -> Opal memory/connectivity efficiency
```

The earlier live-view architecture change and the stability foundation remain prior work performed with GPT-5.4 and GPT-5.4 mini. GPT-5.6 Sol was used for the later optimization passes that made those foundations faster and more usable as one field-camera workflow.

## Phase Between the Two Live-View Milestones — Stability Engineering

### 2026-06-30 to 2026-07-17: Reliability foundation

The period between the two performance milestones was not a gap in development. After the first live-view snapshot, the project shifted from raw frame-rate improvement to reliability engineering. The goal was to make the camera platform survive real operation rather than only succeed in a single happy-path demonstration.

The main architectural additions were:

- A persistent session concept for camera and live-view state.
- A session manager responsible for starting, retaining, clearing, and rehydrating sessions.
- A repair unit/guardian path for detecting degraded runtime conditions and requesting recovery.
- Separate state, frame, battery, and session caches with different lifetimes.
- Command locks and serialized camera actions to prevent PTP collisions.
- UI-to-action correlation and runtime observation so a camera action could be traced across UI, CGI, bridge, and PTP layers.
- Recovery rules that distinguished normal command execution from live-view repair.
- Frozen baselines and regression checks to prevent later optimization from silently breaking working behavior.

This work used GPT-5.4 and GPT-5.4 mini. It created the stability foundation on which the later GPT-5.6 Sol live-view optimization could be performed safely.

Evidence:

- `docs/opal-liveview-frozen-baseline-2026-06-30.md`
- `docs/remote-control-priority-snapshot-2026-07-11.md`
- `docs/v2-liveview-stability-snapshot-2026-07-11.md`
- `docs/bridge-responsibility-contract-2026-07-12.md`
- `docs/bridge-module-contract-2026-07-13.md`
- `docs/dependency-stability-foundation-2026-07-19.md`
- `remote-ui/cgi-bin/session-manager`
- `remote-ui/cgi-bin/runtime-guardian`
- `remote-ui/cgi-bin/stack-guardian`

## Codex and GPT-5.6 Evidence To Attach

### Model-use history

Based on the project owner's account, four model variants were used across this project:

- GPT-5.4
- GPT-5.4 mini
- GPT-5.6 Luna
- GPT-5.6 Sol

The earlier project exploration and implementation primarily used GPT-5.4 or GPT-5.4 mini. The project owner's explicit boundary is that GPT-5.6 use should be attributed only to work performed after **2026-07-18 11:40 KST**. The exact GPT-5.6 variant in that period was GPT-5.6 Luna or GPT-5.6 Sol.

This distinction is favorable because it makes the Hackathon contribution precise without over-claiming earlier work. GPT-5.6 should be associated only with the post-cutoff work that continued the existing camera prototype, including the final stabilization, documentation, and submission-oriented verification. Earlier work remains documented as GPT-5.4 or GPT-5.4 mini work, or as model-unattributed work where the exact variant is not known.

The following details must be completed before submission:

- Primary Codex Session ID: `[INSERT SESSION ID]`
- Codex/GPT-5.6 work period: `2026-07-18 11:40 KST onward`
- Meaningful functionality built or changed with Codex/GPT-5.6: `[DESCRIBE ONLY THE WORK AFTER THE CUTOFF]`
- Timestamped commits or equivalent change record: `[INSERT LINK OR PATH]`
- Additional Codex sessions that materially contributed: `[INSERT IDS]`

The README should state which parts were pre-existing and which parts were built or meaningfully extended during the Hackathon Submission Period. Do not claim that all historical work was created during the Hackathon.

## Submission Demo Narrative

The three-minute demo should show one complete loop:

```text
Connect to the Opal -> see live view -> press AF -> press SHOT
-> see the captured JPEG -> interrupt the connection
-> show automatic recovery -> continue using the camera
```

The narration should explain that Codex and GPT-5.6 were used to inspect the existing system, define module contracts, implement recovery and image-delivery behavior, and verify the resulting contracts.

## Known Limits To State Clearly

- The current supported camera is Nikon D810.
- The system depends on a GL.iNet Opal router and a USB camera connection.
- The project is a working hackathon prototype, not a general camera platform.
- The demo and testing instructions should include a recorded fallback or mock path because judges may not have the physical hardware.

## Competitive Reference and Product Completeness

The project used DigiCamControl and existing mobile camera-control services as functional reference points. This was not a source-code or UI reproduction effort. The references established the minimum feature set needed for a meaningful comparison: live view, autofocus, shutter control, captured-image preview, remote connectivity, and recovery from camera or transport instability.

By July 19, the project had reached that comparison threshold while retaining a different architecture and product emphasis:

- A Nikon D810 connected to a low-resource GL.iNet Opal platform.
- A browser-based field remote rather than a desktop-only camera application.
- Explicit session numbering, retained/non-retained live-view session handling, and observable logs.
- Runtime repair and recovery behavior designed around unreliable USB/PTP and embedded-router conditions.
- Separate fast live-view and captured-image preview paths.

The correct positioning is therefore **reference-informed feature completeness with a distinct field-reliability architecture**, not imitation of an existing commercial application.
