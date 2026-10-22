#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p artifacts

swiftc Scripts/ArtworkRecolor/main.swift -o "$work/recolor"
"$work/recolor" Resources/Birdy-original-sketch.png Resources/Birdy-ink.png artifacts/Birdy-icon-preview.png Resources/Birdy-menu.png

iconset="$work/Birdy.iconset"
mkdir -p "$iconset"
for points in 16 32 128 256 512; do
    sips -z "$points" "$points" artifacts/Birdy-icon-preview.png --out "$iconset/icon_${points}x${points}.png" >/dev/null
    pixels=$((points * 2))
    sips -z "$pixels" "$pixels" artifacts/Birdy-icon-preview.png --out "$iconset/icon_${points}x${points}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o Resources/Birdy.icns
