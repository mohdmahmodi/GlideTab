#!/bin/bash
# Builds GlideTab.app (universal: Apple silicon + Intel).
#   ./build.sh            build into build/GlideTab.app
#   ./build.sh install    build, install to /Applications, add the `glidetab` command, launch
#   ./build.sh test       build and run the unit tests
#   ./build.sh release    Developer ID sign, notarize, staple and zip for a GitHub release (build/GlideTab.zip)
set -euo pipefail
cd "$(dirname "$0")"

APP=build/GlideTab.app
OBJ=build/obj
MIN_OS=14.0
SWIFT_FLAGS=(-O -swift-version 5 -import-objc-header ObjC/Catch.h)
# Developer commands (--stress, --e2e, --snapshot …) are only compiled in when asked for.
[[ -n "${GLIDETAB_DEBUG:-}" || "${1:-}" == "test" ]] && SWIFT_FLAGS+=(-D DEBUG)
SOURCES=(Sources/*.swift Sources/Settings/*.swift)

compile_objc() { # arch
    mkdir -p "$OBJ"
    clang -c -O2 -fobjc-arc -target "$1-apple-macos$MIN_OS" ObjC/Catch.m -o "$OBJ/Catch-$1.o"
}

if [[ "${1:-}" == "test" ]]; then
    arch=$(uname -m)
    compile_objc "$arch"
    app_sources=()
    for f in "${SOURCES[@]}"; do [[ "$f" == Sources/main.swift ]] || app_sources+=("$f"); done
    swiftc "${SWIFT_FLAGS[@]}" -target "$arch-apple-macos$MIN_OS" "${app_sources[@]}" Tests/*.swift \
        "$OBJ/Catch-$arch.o" -o build/tests
    exec build/tests
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
[[ -f Resources/AppIcon.icns ]] || swift scripts/make-icon.swift Resources/AppIcon.icns

binaries=()
for arch in arm64 x86_64; do
    compile_objc "$arch"
    swiftc "${SWIFT_FLAGS[@]}" -target "$arch-apple-macos$MIN_OS" "${SOURCES[@]}" "$OBJ/Catch-$arch.o" \
        -o "$OBJ/GlideTab-$arch"
    binaries+=("$OBJ/GlideTab-$arch")
done
lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/GlideTab"

cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
for lproj in Resources/*.lproj; do [[ -d "$lproj" ]] && cp -R "$lproj" "$APP/Contents/Resources/"; done

# Sign with a stable identity when there is one: macOS ties permissions and update checks to the signature,
# so ad-hoc builds lose them on every rebuild. Identities are picked by SHA-1, in case two share a name.
identity() { # pattern
    security find-identity -v -p codesigning | awk -v pat="$1" '$0 ~ pat { print $2; exit }'
}
if [[ "${1:-}" == "release" ]]; then
    # Releases must be Developer ID signed with the hardened runtime, so they can be notarized.
    IDENTITY="${SIGN_IDENTITY:-$(identity 'Developer ID Application')}"
    [[ -n "$IDENTITY" && "$IDENTITY" != "-" ]] || { echo "error: no Developer ID Application certificate found"; exit 1; }
    codesign --force --options runtime --timestamp --entitlements Resources/GlideTab.entitlements --sign "$IDENTITY" "$APP"
else
    IDENTITY="${SIGN_IDENTITY:-$(identity 'Developer ID Application|Apple Development')}"
    codesign --force --entitlements Resources/GlideTab.entitlements --sign "${IDENTITY:--}" "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"

case "${1:-}" in
install)
    pkill -x GlideTab && sleep 0.5 || true
    rm -rf /Applications/GlideTab.app
    cp -R "$APP" /Applications/
    # A tiny wrapper (not a symlink) so the binary still finds its bundle.
    for dir in /opt/homebrew/bin /usr/local/bin; do
        if [[ -d "$dir" && -w "$dir" ]]; then
            printf '#!/bin/sh\nexec /Applications/GlideTab.app/Contents/MacOS/GlideTab "$@"\n' > "$dir/glidetab"
            chmod +x "$dir/glidetab"
            echo "Installed command: $dir/glidetab"
            break
        fi
    done
    open /Applications/GlideTab.app
    echo "Installed and launched /Applications/GlideTab.app"
    ;;
release)
    # Notarize with Apple and staple the ticket, so Gatekeeper accepts the app offline.
    # One-time setup: xcrun notarytool store-credentials glidetab --apple-id you@example.com --team-id TEAMID
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
    rm -f build/GlideTab.zip
    ditto -c -k --keepParent "$APP" build/GlideTab-notarize.zip
    xcrun notarytool submit build/GlideTab-notarize.zip --keychain-profile "${NOTARY_PROFILE:-glidetab}" --wait
    xcrun stapler staple "$APP"
    spctl --assess --type execute --verbose "$APP"
    rm -f build/GlideTab-notarize.zip
    ditto -c -k --keepParent "$APP" build/GlideTab.zip
    echo "Release zip: build/GlideTab.zip (version $VERSION, notarized and stapled)"
    echo "Publish with: gh release create v$VERSION build/GlideTab.zip --title \"GlideTab $VERSION\""
    ;;
esac
