#!/bin/bash
# Runs the Swift Testing suites of VaultCore and of the app (ClevaneUI).
# Usage: scripts/test.sh [VaultCore|Clevane]   (default: both)
# With only the Command Line Tools installed, Testing.framework sits outside the default search paths,
# so they are passed explicitly. With Xcode installed, plain `swift test` is enough.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
frameworks=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
libraries=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
flags=()
if [ -d "$frameworks/Testing.framework" ] && ! xcode-select -p | grep -q Xcode.app; then
  flags=(-Xswiftc -F"$frameworks" -Xlinker -F"$frameworks" -Xlinker -rpath -Xlinker "$frameworks" -Xlinker -rpath -Xlinker "$libraries")
fi
for package in ${1:-VaultCore Clevane}; do
  echo "== $package"
  # A plain build first: swift test alone missed source files newly added to the VaultCore dependency.
  swift build --package-path "$root/$package"
  swift test --package-path "$root/$package" "${flags[@]}"
done
