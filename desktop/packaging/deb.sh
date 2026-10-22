#!/usr/bin/env bash
# Builds the .deb from the AppImage's AppDir: the app and the Qt it was built with
# under /opt/aikatsu, depending on the system libraries the AppDir leaves out.
# Run on the machine that built the AppDir (release.yml), so dpkg knows those libraries.
# Usage: deb.sh <AppDir> <version> <out.deb>
set -euo pipefail
appdir=$1 version=$2 out=$3
here=$(cd "$(dirname "$0")" && pwd)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT

mkdir -p "$root/DEBIAN" "$root/opt" "$root/usr/bin" "$root/usr/share/applications" "$root/usr/share/icons/hicolor/scalable/apps"
cp -a "$appdir" "$root/opt/aikatsu"
# Not a symlink: AppRun finds its hooks next to the path it was started from.
printf '#!/bin/sh\nexec /opt/aikatsu/AppRun "$@"\n' > "$root/usr/bin/aikatsu"
chmod 755 "$root/usr/bin/aikatsu"
cp "$here/aikatsu.desktop" "$root/usr/share/applications/"
cp "$here/../assets/icon.svg" "$root/usr/share/icons/hicolor/scalable/apps/aikatsu.svg"

bundled=$(find "$root/opt/aikatsu" -name '*.so*' -printf '%f\n' | sort -u)
needed=$(find "$root/opt/aikatsu" -type f -exec sh -c 'head -c4 "$1" | grep -q ELF && objdump -p "$1"' _ {} \; |
  awk '$1 == "NEEDED" { print $2 }' | sort -u)
# The newest glibc any of them uses: apt shouldn't install it where it can't start.
glibc=$(find "$root/opt/aikatsu" -type f -exec sh -c 'head -c4 "$1" | grep -q ELF && objdump -T "$1"' _ {} \; |
  grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1)
depends=()
for lib in $(comm -23 <(echo "$needed") <(echo "$bundled")); do
  pkg=$(dpkg -S "*/$lib" 2>/dev/null | head -1 | cut -d: -f1) || true
  if [ -z "$pkg" ]; then
    echo "::warning::no package provides $lib; the .deb doesn't depend on it" >&2
    continue
  fi
  # Ubuntu 24.04 and Debian 13 renamed some for 64-bit time_t (libasound2t64); older releases have the old name.
  # Not the old name alone: other packages provide it too, and apt may pick a stand-in.
  [[ $pkg == *t64 ]] && pkg="$pkg | ${pkg%t64}"
  [[ $pkg == libc6 && -n $glibc ]] && pkg="libc6 (>= ${glibc#GLIBC_})"
  depends+=("$pkg")
done

cat > "$root/DEBIAN/control" <<EOF
Package: aikatsu
Version: $(echo "$version" | tr - '~')
Architecture: amd64
Maintainer: KidiXDev <KidiXDev@users.noreply.github.com>
Installed-Size: $(du -sk "$root" | cut -f1)
Depends: $(printf '%s\n' "${depends[@]}" | sort -u | paste -sd, - | sed 's/,/, /g')
Section: video
Priority: optional
Homepage: https://github.com/KidiXDev/aikatsu
Description: Anime streaming and local library player
 Watch anime from source plugins and your own folders,
 and keep your history in sync between devices.
EOF
dpkg-deb --build --root-owner-group "$root" "$out"
