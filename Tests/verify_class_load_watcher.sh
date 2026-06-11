#!/bin/bash

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/InterposeKitClassWatcher.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

derived_data="$work_dir/DerivedData"
framework_dir="$derived_data/Build/Products/Debug"
build_settings=()

if [[ "${IKT_FORCE_DYLD_IMAGE_CALLBACK:-0}" == "1" ]]; then
    build_settings+=('GCC_PREPROCESSOR_DEFINITIONS=$(inherited) IKT_FORCE_DYLD_IMAGE_CALLBACK=1 IKT_TEST_DELAY_DYLD_CALLBACK=1')
fi

xcodebuild \
    -project "$project_root/InterposeKit.xcodeproj" \
    -scheme InterposeKit \
    -configuration Debug \
    -sdk macosx \
    -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    "${build_settings[@]}" \
    build \
    -quiet

cat >"$work_dir/Plugin.m" <<'EOF'
#import <Foundation/Foundation.h>

@interface IKTWatcherFixture : NSObject
@end

@implementation IKTWatcherFixture
@end
EOF

cat >"$work_dir/Probe.swift" <<'EOF'
import Darwin
import Foundation
import InterposeKit

let watcherCompletion = DispatchSemaphore(value: 0)
let imageCompletion = DispatchSemaphore(value: 0)
let replayCompletion = DispatchSemaphore(value: 0)

func imageDidLoad() {
    imageCompletion.signal()
}

func replayImageState() {
    replayCompletion.signal()
}

IKTRegisterImageDidLoadCallback(imageDidLoad)
while imageCompletion.wait(timeout: .now() + .milliseconds(50)) == .success {}

IKTRegisterImageDidLoadCallback(replayImageState)
guard replayCompletion.wait(timeout: .now() + .seconds(5)) == .success else {
    fputs("Late image callback did not receive a state replay.\n", stderr)
    exit(1)
}

let waiter = try Interpose.whenAvailable("IKTWatcherFixture", builder: { _ in }, completion: {
    watcherCompletion.signal()
})

RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
while imageCompletion.wait(timeout: .now()) == .success {}

guard dlopen(CommandLine.arguments[1], RTLD_NOW) != nil else {
    fputs("dlopen failed: \(String(cString: dlerror()))\n", stderr)
    exit(1)
}

guard watcherCompletion.wait(timeout: .now() + .seconds(5)) == .success else {
    fputs("Watcher did not observe IKTWatcherFixture after dlopen.\n", stderr)
    exit(1)
}

guard imageCompletion.wait(timeout: .now() + .seconds(5)) == .success else {
    fputs("Independent image callback did not survive watcher registration.\n", stderr)
    exit(1)
}

withExtendedLifetime(waiter) {}
print("Watcher, state replay, and independent callback observed the loaded image.")
EOF

xcrun clang \
    -fobjc-arc \
    -dynamiclib \
    -framework Foundation \
    "$work_dir/Plugin.m" \
    -o "$work_dir/libWatcherFixture.dylib"

xcrun swiftc \
    -F "$framework_dir" \
    -framework InterposeKit \
    -Xlinker -rpath \
    -Xlinker "$framework_dir" \
    "$work_dir/Probe.swift" \
    -o "$work_dir/WatcherProbe"

"$work_dir/WatcherProbe" "$work_dir/libWatcherFixture.dylib"
