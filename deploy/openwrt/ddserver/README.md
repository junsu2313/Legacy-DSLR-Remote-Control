# OpenWrt ddserver Package

This folder is a package-ready OpenWrt wrapper for the local ddserver source in `_tmp_ddserver`.

## What it does

- Builds `ddserver` with the OpenWrt SDK/toolchain.
- Installs the binary to `/usr/bin/ddserver`.
- Installs an OpenWrt init script at `/etc/init.d/ddserver`.
- Disables the desktop systemd unit during OpenWrt builds.

## Build Flow

1. Copy this package folder into an OpenWrt SDK under `package/ddserver`.
2. Copy `_tmp_ddserver/src` into `package/ddserver/src`.
3. Run `make package/ddserver/compile V=s`.

## Expected Dependencies

- `libusb-1.0`
- `libpthread`

## Notes

- The package is intended for the GL.iNet Opal / OpenWrt target.
- If you later want to test a desktop build, keep the root CMake build enabled with `DDSERVER_INSTALL_SYSTEMD=ON`.
