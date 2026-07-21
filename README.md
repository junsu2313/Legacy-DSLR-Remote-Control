# Wireless Nikon D810 Field Camera Platform

An AI-assisted, hardware-backed project that turns a Nikon D810 and a GL.iNet Opal router into a wireless field camera system.

The project provides browser-based live view, autofocus, shutter control, captured-image preview, session-aware recovery, runtime observation, and a path toward remote image transfer.

This repository is both a working prototype and a record of how a developer and Codex built, measured, debugged, and stabilized a real camera system together.

The current prototype supports the Nikon D810, with plans to support more cameras and provide additional capabilities over time.

## Why This Project Is Needed

Modern mirrorless cameras include many conveniences that make photography more enjoyable, such as film simulations and wireless photo transfer. Should these conveniences be limited to current products? Can older cameras offer some of the same modern experiences?

This project began with those questions: how can modern convenience be brought to older cameras? Starting with the Nikon D810, it explores a wireless field-camera experience built with a small OpenWrt router, a browser UI, and a purpose-built camera-control stack.

**Bringing modern convenience to older cameras.**

## What Works

- Nikon D810 detection through USB/PTP transport
- Browser-based remote control through the Opal router
- Live-view streaming through the `ddserver -> bridge -> UI` path
- AF and shutter actions with serialized command handling
- Numbered camera sessions and preserved session logs
- Separate handling for live-view sessions and ordinary camera sessions
- Runtime observation across UI, CGI, bridge, PTP, and frame-production layers
- Recovery behavior for degraded session and live-view conditions
- Captured JPEG preview and full-size image delivery paths
- Live-view performance: early development approximately 2 FPS → final approximately 20 FPS, with a 26.3 FPS peak
- Captured-image preview: early development approximately 19–20 seconds → currently approximately 5.2 seconds for a 6.42 MB, 9 MP Fine JPEG

## System Shape

```text
Nikon D810
    |
    | USB / PTP
    v
GL.iNet Opal / OpenWrt
    |
    +-- ddserver: low-level USB/PTP transport
    +-- bridge: Nikon command and session orchestration
    +-- session manager: session lifecycle and rehydration
    +-- repair/guardian units: runtime recovery signals
    +-- frame workers and caches: live-view production
    +-- CGI/WebSocket endpoints: browser-facing API
    v
Mobile or desktop browser UI
```

## Development Story

| Period | Result |
|---|---|
| 2026-06-23 | Product direction and wireless DSLR architecture were defined before the hardware was available. |
| 2026-06-25–06-30 | The D810, Opal, ddserver, bridge, and first browser-control path were connected. |
| 2026-06-30 | Preview polling was replaced with a WebSocket live-view path; the first baseline was approximately 2 FPS, with a temporary approximately 15 FPS result after reboot. |
| 2026-06-30–07-17 | Reliability engineering became the priority: numbered sessions, session logs, live-view session separation, repair units, observation, locks, and regression baselines. |
| 2026-07-18 | GPT-5.6 Sol was used for the second live-view optimization, reaching approximately 20 FPS operation and a measured 26.3 FPS peak. |
| 2026-07-19 | GPT-5.6 Sol was used to optimize captured-image preview delivery; the earlier optimized payload reached around 2 seconds. |
| 2026-07-20 | Tailscale connectivity was verified end-to-end, while Opal RAM usage and service footprint were reduced for field operation. |
| 2026-07-21 | The current RAW + Fine JPEG path was revalidated at 9 MP: a 6.42 MB JPEG completed end-to-end delivery in approximately 5.2 seconds. |

## AI-Assisted Development and Developer Responsibility

This project was developed with Codex as an active engineering collaborator. The work was not limited to generating isolated code snippets. Codex was used to inspect a growing codebase, trace failures across hardware and software boundaries, compare reference implementations, propose architecture changes, implement fixes, run tests, inspect logs, and document the resulting system.

Four model variants were used across the project: GPT-5.4, GPT-5.4 mini, GPT-5.6 Luna, and GPT-5.6 Sol. The project uses a strict attribution boundary: GPT-5.6 contributions are attributed only to work performed after 2026-07-18 11:40 KST. Earlier architecture, implementation, and reliability work used GPT-5.4 or GPT-5.4 mini.

The developer remained responsible for:

- Defining the product goal and deciding what the system should do
- Choosing the architecture and accepting or rejecting proposed changes
- Connecting and operating the physical D810 and Opal hardware
- Interpreting camera, USB, PTP, memory, latency, and frame-rate behavior
- Validating changes on the real device rather than trusting generated code
- Preserving original images and protecting the recovery path from regressions
- Deciding what is ready to be called working and what remains experimental

The value of this project is therefore not that AI wrote everything. The value is that AI accelerated investigation and implementation while the developer supplied intent, judgment, verification, and accountability.

## Repository Guide

- `app/remote-ui/` — browser UI, CGI endpoints, bridge, session manager, workers, and recovery units
- `deploy/openwrt/` — router startup and package integration files
- `deploy/scripts/` — build, deployment, memory, upload, and contract-test helpers
- `docs/DSLR_Wireless/` — architecture and reference-implementation analysis
- `docs/` — development history, stability contracts, performance records, and operational notes

## Hardware and Platform

- Camera: Nikon D810
- Router: GL.iNet Opal / GL-SFT1200 running OpenWrt
- Camera transport: USB/PTP through `ddserver`
- User interface: mobile- and desktop-browser UI served by the Opal

The current prototype is intentionally D810-focused. It is not yet a general-purpose multi-camera platform.

## Running and Testing

The camera platform requires the physical D810, the Opal router, the correct OpenWrt architecture, and the deployed camera-side services. Start with the documents in `docs/` and the scripts in `deploy/scripts/` before changing the active router deployment.

The repository intentionally does not include camera originals, router credentials, local caches, SDK archives, or generated dependency directories.

If you want to try this project in practice, show the repository to an AI assistant and work through the setup with it. With an AI collaborator, you can explore and enjoy the project step by step.

**This is only the beginning.** As the project matures into a product, I will package it into an accessible and practical experience that more people can install, use, and enjoy. Until then, please stay with the project as it takes its next step—from a working prototype toward a real product.

## Hackathon Context

This project began before OpenAI Build Week. I selected it for Build Week because I wanted to use the event as a focused period to strengthen and extend a project that was already in progress. Build Week is documented here as part of the project's development process, not as its starting point.

The primary hackathon contribution is the post-cutoff optimization and stabilization work: a more responsive live-view pipeline, a much faster captured-image preview path, and continued field reliability work. The primary Codex project thread is recorded in [`docs/hackathon-development-history-2026-07-19.md`](docs/hackathon-development-history-2026-07-19.md).

## Known Limitations

- The supported camera is currently Nikon D810.
- The system depends on specific OpenWrt router hardware and USB/PTP behavior.
- Live-view performance depends on camera, session, router, and network state.
- The final Tailscale and RAM-optimization measurements are recorded in the project history and service-optimization notes.
- This project is an alpha-stage prototype, not a finished commercial product.

## License

Original code in this repository is licensed under the MIT License. See [`LICENSE`](LICENSE).

Third-party code and dependencies remain subject to their respective licenses and notices.
