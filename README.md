# omv-rustfs

An [OpenMediaVault](https://www.openmediavault.org/) 8.x plugin that runs [RustFS](https://github.com/rustfs/rustfs) — a high-performance, S3-compatible object storage server built in Rust — as a native OpenMediaVault managed service.

Debian package name: `openmediavault-rustfs`

Versioning: the plugin's major version follows the OpenMediaVault major version (`8.x.y+rustfsX.Y.Z`).

## Features

Single management page under **Services → RustFS**.

### Status (read-only)
- **Service status**: `Running` or `Stopped` (real-time systemd status)
- **Bundled version**: Upstream RustFS version pinned in the package
- **Data directory**: Resolved absolute path of the selected data shared folder

### Settings
- **Enabled**: Start RustFS automatically at boot. A shared folder must be selected before enabling. Click `Save` and then `Apply` to take effect.
- **Data shared folder**: OMV shared folder dedicated to storing RustFS object data.
- **S3 API port**: Port for the S3 API endpoint (default: `9000`).
- **Console port**: Port for the RustFS web console (default: `9001`).
- **Enable console**: Toggle to serve or disable the web console.
- **Credentials**: Strong random Access Key and Secret Key generated automatically at install time. Never uses the default `rustfsadmin` credentials.
- **Log level**: Configurable logging verbosity (`trace`, `debug`, `info`, `warn`, `error`).
- **Extra environment options**: Escape hatch for advanced configuration in `/etc/default/rustfs`.

### Actions
- `Save` / `Apply`: Persist configuration into the OMV database and deploy systemd service via Salt.
- `Start` / `Stop` / `Restart`: Immediate service lifecycle operations via `omv-rustfs-ctl`.
- `Regenerate credentials`: Rotate the Access Key and Secret Key with one click.
- `View logs`: View recent systemd journal logs in a task dialog.
- `View generated config`: Inspect the rendered `/etc/default/rustfs` environment file.
- `Open console`: Directly navigate to the RustFS web console.

> **Scope**: The plugin only handles OpenMediaVault system integration — lifecycle, credentials, configuration rendering, and status. Buckets, IAM policies, and object storage workflows are managed within RustFS itself.

## Architecture

- **Native Service Track**: RustFS runs directly on the host as a systemd unit (`rustfs.service`) with sandboxing hardening (`Type=notify`, `ProtectHome`, `PrivateTmp`, `RestrictRealtime`).
- **Prebuilt Binary**: The upstream GNU glibc binary is fetched during package build (`build-deb.sh`) and verified against official upstream SHA256 sums.
- **Multi-Arch**: Supports both `amd64` and `arm64`.
- **i18n**: Full Simplified Chinese (`zh_CN`) and Traditional Chinese (`zh_TW`) translations.

## Building

```bash
# Render placeholders
./render-vars.sh

# Download upstream binary and verify checksum
./build-deb.sh amd64 1.0.4

# Build Debian package
dpkg-buildpackage -us -uc -b -d
```
