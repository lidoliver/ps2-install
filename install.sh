#!/usr/bin/env bash
# install.sh — put ps2-install, ps2-art and the desktop integration in place.
#   ./install.sh                 scripts + launcher entries
#   ./install.sh --hdl-dump      also build the patched hdl_dump from source
set -euo pipefail
cd "$(dirname "$0")"

BIN="$HOME/.local/bin"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
HDL_DUMP_REPO=https://github.com/ps2homebrew/hdl-dump.git
HDL_DUMP_REV=32c296c   # the commit patches/hdl-dump-no-odsync.patch was made against

mkdir -p "$BIN" "$APPS"
install -m755 ps2-install ps2-art "$BIN/"

# --- frontend: KDE (kdialog progress bars, Dolphin right-click menu) ---
# launchers don't always have ~/.local/bin on PATH: point Exec at the full path
exec_path() { sed "s|^Exec=ps2-install|Exec=$BIN/ps2-install|" "$1"; }
exec_path kde/ps2-install.desktop >"$APPS/ps2-install.desktop"
SERVICEMENUS="${XDG_DATA_HOME:-$HOME/.local/share}/kio/servicemenus"
mkdir -p "$SERVICEMENUS"
exec_path kde/ps2-install-servicemenu.desktop >"$SERVICEMENUS/ps2-install.desktop"
chmod 755 "$SERVICEMENUS/ps2-install.desktop"   # KF6 only runs executable service menus
need=(kdialog qdbus6 nbd-client)
# ---

if [[ ${1:-} == --hdl-dump ]]; then
    src=$(mktemp -d)
    git clone -q "$HDL_DUMP_REPO" "$src/hdl-dump"
    git -C "$src/hdl-dump" checkout -q "$HDL_DUMP_REV"
    git -C "$src/hdl-dump" apply "$PWD/patches/hdl-dump-no-odsync.patch"
    make -C "$src/hdl-dump" -s RELEASE=yes -j"$(nproc)"
    install -m755 "$src/hdl-dump/hdl_dump" "$BIN/"
    rm -rf "$src"
    echo "Built patched hdl_dump → $BIN/hdl_dump"
fi

for t in "${need[@]}" hdl_dump pfsshell magick python3; do
    command -v "$t" >/dev/null || [[ -x $BIN/$t ]] || echo "missing: $t (see README)"
done
echo "Installed to $BIN"
