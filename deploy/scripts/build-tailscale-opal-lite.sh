#!/bin/sh
set -eu

GO_ROOT=${GO_ROOT:-/root/camera-build/toolchains/go1.26.3}
SOURCE_ROOT=${SOURCE_ROOT:-/root/camera-build/src/tailscale}
OUTPUT=${OUTPUT:-/root/camera-build/artifacts/tailscale.combined.opal}

TAGS=ts_include_cli,ts_omit_relayserver,ts_omit_clientupdate,ts_omit_capture,ts_omit_cloud,ts_omit_debug,ts_omit_debugportmapper,ts_omit_drive,ts_omit_serve,ts_omit_ssh,ts_omit_taildrop,ts_omit_systray,ts_omit_c2n,ts_omit_clientmetrics,ts_omit_usermetrics,ts_omit_portmapper,ts_omit_portlist,ts_omit_advertiseroutes,ts_omit_advertiseexitnode,ts_omit_appconnectors,ts_omit_kube,ts_omit_posture,ts_omit_tailnetlock,ts_omit_wakeonlan,ts_omit_webclient,ts_omit_webbrowser,ts_omit_syspolicy,ts_omit_dns,ts_omit_netstack,ts_omit_gro,ts_omit_peerapiclient,ts_omit_peerapiserver,ts_omit_logtail,ts_omit_completion,ts_omit_completion_scripts,ts_omit_cliconndiag,ts_omit_doctor,ts_omit_qrcodes,ts_omit_captiveportal,ts_omit_conn25,ts_omit_aws,ts_omit_tpm,ts_omit_dbus,ts_omit_networkmanager,ts_omit_resolved,ts_omit_sdnotify,ts_omit_useexitnode,ts_omit_useroutes,ts_omit_tap,ts_omit_desktop_sessions,ts_omit_identityfederation,ts_omit_linkspeed,ts_omit_netlog

cd "$SOURCE_ROOT"
env \
    PATH="$GO_ROOT/bin:$PATH" \
    GOOS=linux \
    GOARCH=mipsle \
    GOMIPS=softfloat \
    CGO_ENABLED=0 \
    go build -trimpath -ldflags=-s -tags="$TAGS" -o "$OUTPUT" ./cmd/tailscaled

ls -lh "$OUTPUT"
sha256sum "$OUTPUT"
