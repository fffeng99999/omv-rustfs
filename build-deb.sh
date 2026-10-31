#!/bin/sh
#
# Download the RustFS release archive from GitHub, verify its checksum and
# stage the rustfs server binary under usr/bin/ so that dpkg-buildpackage
# can pack it into the architecture-specific .deb. The upstream version is
# also written to usr/share/rustfs/VERSION so the web interface can display
# the bundled version without executing the binary.
#
# Usage:
#   ./build-deb.sh [deb-architecture] [explicit-version]
#
# Defaults: architecture=amd64, version taken from the +rustfsX.Y.Z suffix
# of debian/changelog (tagged releases are therefore reproducible).
#
# Note that the upstream Git tag has no leading 'v' (tag '1.0.1'), while the
# asset file names embed one (rustfs-linux-x86_64-gnu-v1.0.1.zip).
#
# This file is part of OpenMediaVault openmediavault-rustfs packaging.
# @license https://www.gnu.org/licenses/gpl.html GPL Version 3

set -eu

REPO="rustfs/rustfs"
ARCH="${1:-amd64}"
VERSION="${2:-}"

if [ -n "${GH_TOKEN:-}" ]; then
	AUTH_HEADER="Authorization: Bearer ${GH_TOKEN}"
else
	AUTH_HEADER=""
fi
api_get() {
	if [ -n "$AUTH_HEADER" ]; then
		curl -fsSL -H "$AUTH_HEADER" "$@"
	else
		curl -fsSL "$@"
	fi
}

# Map Debian architecture to the RustFS upstream arch token and pick the
# GNU (glibc) build: OMV 8 is based on Debian 13 (glibc >= 2.31), which is
# exactly the condition under which the upstream installer prefers GNU over
# MUSL.
case "$ARCH" in
	amd64) UARCH="x86_64" ;;
	arm64) UARCH="aarch64" ;;
	*)
		echo "ERROR: unsupported architecture '$ARCH' (use amd64|arm64)" >&2
		exit 1
	;;
esac

# Resolve the upstream version for this build, in order of priority:
#   1. the explicit version argument (CI workflow_dispatch input / local use)
#   2. the +rustfsX.Y.Z suffix pinned in debian/changelog (tagged releases
#      register their RustFS version there, so builds are reproducible)
#   3. the latest stable release from the GitHub API (convenience for
#      untagged local builds only; prints a warning because such a build
#      is not reproducible)
if [ -z "$VERSION" ]; then
	CHANGELOG_HEAD="$(head -n 1 debian/changelog 2>/dev/null || true)"
	PKG_VER="$(printf '%s\n' "$CHANGELOG_HEAD" | sed -n 's/.*(\([^)]*\)).*/\1/p')"
	RUSTFS_FROM_CHANGELOG="$(printf '%s\n' "$PKG_VER" | sed -n 's/.*+rustfs//p')"
	if [ -n "$RUSTFS_FROM_CHANGELOG" ]; then
		VERSION="$RUSTFS_FROM_CHANGELOG"
		echo "Using RustFS version pinned in debian/changelog: ${VERSION}"
	fi
fi

if [ -z "$VERSION" ]; then
	echo "WARNING: no explicit version and no +rustfsX.Y.Z suffix in debian/changelog;" >&2
	echo "WARNING: resolving the latest RustFS release -- this build is NOT reproducible." >&2
	echo "Resolving latest RustFS release tag from GitHub ..."
	VERSION=$(api_get "https://api.github.com/repos/${REPO}/releases" \
		| awk '
			/"tag_name":/   { gsub(/.*"tag_name": *"|",?$/, ""); tag=$0 }
			/"draft":/      { gsub(/.*"draft": *|,?$/, ""); draft=$0 }
			/"prerelease":/ {
				gsub(/.*"prerelease": *|,?$/, ""); pre=$0
				if (draft != "true" && pre == "false") { print tag; exit }
			}
		' \
		| head -n 1)
	VERSION="${VERSION#v}"
	if [ -z "$VERSION" ]; then
		echo "ERROR: could not resolve the latest RustFS release" >&2
		exit 1
	fi
fi

ASSET="rustfs-linux-${UARCH}-gnu-v${VERSION}.zip"
BASE="https://github.com/${REPO}/releases/download/${VERSION}"
URL="${BASE}/${ASSET}"

echo "Version    : ${VERSION}"
echo "Debian arch: ${ARCH} (upstream: ${UARCH})"
echo "Asset      : ${ASSET}"
echo "URL        : ${URL}"

# Prefer /var/tmp over /tmp because the RustFS binary is large (~350MB uncompressed)
# and /tmp is often mounted on a small tmpfs (e.g. 512MB RAM VMs) which would run out of space.
export TMPDIR="${TMPDIR:-/var/tmp}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "Downloading ..."
curl -fL --retry 5 --retry-delay 2 -o "${WORKDIR}/${ASSET}" "$URL"

# Verify the archive against the upstream SHA256SUMS when it is available.
# A missing checksum file only produces a warning so local builds against
# older releases keep working.
if curl -fsSL --max-time 60 -o "${WORKDIR}/SHA256SUMS" "${BASE}/SHA256SUMS" 2>/dev/null; then
	EXPECTED="$(awk -v a="${ASSET}" '$2 == a || $2 == "*"a { print $1 }' "${WORKDIR}/SHA256SUMS" | head -n 1)"
	if [ -n "$EXPECTED" ]; then
		ACTUAL="$(sha256sum "${WORKDIR}/${ASSET}" | awk '{ print $1 }')"
		if [ "$EXPECTED" != "$ACTUAL" ]; then
			echo "ERROR: checksum mismatch for ${ASSET}" >&2
			echo "  expected: ${EXPECTED}" >&2
			echo "  actual  : ${ACTUAL}" >&2
			exit 1
		fi
		echo "Checksum verified against SHA256SUMS."
	else
		echo "WARNING: ${ASSET} not listed in SHA256SUMS, skipping verification." >&2
	fi
else
	echo "WARNING: SHA256SUMS not available for ${VERSION}, skipping verification." >&2
fi

echo "Extracting ..."
mkdir -p "${WORKDIR}/pkg"
if command -v unzip >/dev/null 2>&1; then
	unzip -q -o "${WORKDIR}/${ASSET}" -d "${WORKDIR}/pkg"
elif command -v python3 >/dev/null 2>&1; then
	python3 -c "import zipfile; zipfile.ZipFile('${WORKDIR}/${ASSET}').extractall('${WORKDIR}/pkg')"
else
	echo "ERROR: neither unzip nor python3 is available to extract ${ASSET}" >&2
	exit 1
fi

BIN="$(find "${WORKDIR}/pkg" -type f -name rustfs | head -n 1)"
if [ -z "$BIN" ]; then
	echo "ERROR: rustfs binary not found in ${ASSET}" >&2
	ls -laR "${WORKDIR}/pkg" >&2 || true
	exit 1
fi

DEST="$(dirname "$0")/usr/bin"
echo "Staging into ${DEST} ..."
mkdir -p "$DEST"
cp -a "$BIN" "$DEST/rustfs"
chmod 0755 "$DEST/rustfs"

VDEST="$(dirname "$0")/usr/share/rustfs"
mkdir -p "$VDEST"
printf '%s\n' "$VERSION" > "${VDEST}/VERSION"

echo "Done. Staged files:"
ls -la "$DEST/rustfs" "${VDEST}/VERSION"
file "$DEST/rustfs" || true
