#!/bin/bash

set -euo pipefail

derived_data="$(mktemp -d "${TMPDIR:-/tmp}/InterposeKitReleaseLinking.XXXXXX")"

xcodebuild \
    -project Example/InterposeExample.xcodeproj \
    -scheme InterposeExample \
    -configuration Release \
    -sdk iphoneos \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    build \
    -quiet

binary="$derived_data/Build/Products/Release-iphoneos/InterposeExample.app/InterposeExample"

if ! xcrun nm -a "$binary" | grep -E '[[:space:]]T[[:space:]]_IKTAddSuperImplementationToClass$' >/dev/null; then
    echo "IKTAddSuperImplementationToClass was stripped from the optimized app binary." >&2
    exit 1
fi

echo "Verified IKTAddSuperImplementationToClass in the optimized app binary."
