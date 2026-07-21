# Opal Routing Freeze (2026-06-30)

This document freezes the current route split between the user-facing D810 app and the debug app on the GL.iNet Opal.

## Intent

- keep the real user entry simple
- keep debug/perf tooling reachable without mixing it into the main flow
- preserve the Opal admin page on the root URL

## Active Routes

### Opal admin

- `/`
- expected destination: `/cgi-bin/luci`

### User app

- `/cc`
- expected destination: `/remote-ui/ui-20260628-1.html?v=20260628-1`

### Debug app

- `/cgi-bin/remote-ui`
- `/remote-ui/index.html`
- expected destination: `/remote-ui/ui-20260628-2.html?v=20260628-2`

## App Roles

### `20260628-1`

User-facing app.

Purpose:

- shooting UX
- simplified interaction
- no obligation to expose all perf/debug internals

### `20260628-2`

Debug-facing app.

Purpose:

- live-view experiments
- perf/FPS instrumentation
- bridge and UI diagnostics

## Files That Define This Split

- [`E:\Underlab_APP\Camera\cc\index.html`](E:\Underlab_APP\Camera\cc\index.html)
- [`E:\Underlab_APP\Camera\remote-ui\ui-20260628-1.html`](E:\Underlab_APP\Camera\remote-ui\ui-20260628-1.html)
- [`E:\Underlab_APP\Camera\remote-ui\ui-20260628-2.html`](E:\Underlab_APP\Camera\remote-ui\ui-20260628-2.html)
- [`E:\Underlab_APP\Camera\remote-ui\index.html`](E:\Underlab_APP\Camera\remote-ui\index.html)
- [`E:\Underlab_APP\Camera\remote-ui\root-index.html`](E:\Underlab_APP\Camera\remote-ui\root-index.html)
- [`E:\Underlab_APP\Camera\remote-ui\index_fixed.html`](E:\Underlab_APP\Camera\remote-ui\index_fixed.html)
- [`E:\Underlab_APP\Camera\remote-ui\cgi-bin\remote-ui`](E:\Underlab_APP\Camera\remote-ui\cgi-bin\remote-ui)

## Current Product Direction

- D810 live view is still useful as a preview/status aid
- D810 live view is not currently treated as a 30fps-class feature target on this stack
- future work should prioritize the user shooting flow in `20260628-1`
- future live-view diagnostics and experiments should stay in `20260628-2`
