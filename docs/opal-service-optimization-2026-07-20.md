# Opal service optimization record (2026-07-20)

## Result

- Tailscale v1.98.8 combined binary: 24.4 MiB -> 16.5 MiB.
- Tailscale steady RSS: 28,588 KiB -> about 18,100 KiB.
- `MemAvailable` after service reduction: about 49,900 KiB.
- Tailscale address remains `100.123.59.97`; camera API remained ready.
- Tailscale DNS acceptance and subnet-route acceptance are disabled.
- Previous binary is retained at `/overlay/usr/sbin/tailscale.combined.lite.prev`.

## Runtime services disabled

- `gl_clients`: GL.iNet client-list tracking.
- `gl_led`: LED state daemon; LEDs are intentionally off.
- `mwan3`: multi-WAN policy and health tracking. The active Wi-Fi WAN default route is managed by netifd.

## Boot-only services disabled

OpenVPN, VPN policy, DNSCrypt, Stubby, Tor, GL cloud/DDNS/S2S/eQoS,
SMS tools, tethering/modem helpers, modem signal, and WAN speed reporting.

## Retained intentionally

- Wi-Fi/router: repeater, hostapd, wpa_supplicant, netifd, firewall, dnsmasq.
- Management/camera web path: nginx, fcgiwrap, rpcd, gl-ngx-session.
- Camera/USB: usbmode, usbmuxd, ddserver, D810 bridge and guardians.

## Recovery

Restore the previous Tailscale binary:

```sh
/etc/init.d/tailscaled stop
mv /overlay/usr/sbin/tailscale.combined /overlay/usr/sbin/tailscale.combined.opal.failed
mv /overlay/usr/sbin/tailscale.combined.lite.prev /overlay/usr/sbin/tailscale.combined
/etc/init.d/tailscaled start
```

Re-enable the three stopped services if needed:

```sh
for service in gl_clients gl_led mwan3; do
    /etc/init.d/$service enable
    /etc/init.d/$service start
done
```

The main Windows computer was connected later as `100.94.174.121`.
Tailscale ping, camera HTTP, and SSH to Opal `100.123.59.97` were verified end to end.
