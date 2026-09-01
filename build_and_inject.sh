#!/bin/bash
set -euo pipefail

rm -rf DerivedData Payload work
xcodebuild -scheme TarabBannerHider \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

DYLIB="$(find DerivedData/Build/Products/Release-iphoneos -name 'libTarabBannerHider.dylib' -o -name 'TarabBannerHider.dylib' | head -1)"
if [ -z "${DYLIB}" ]; then
  echo "TarabBannerHider dylib not found"
  exit 1
fi

cp Tarab_Input.ipa Tarab_HideOriginalBanner_FORCE.ipa
python3 inject_dylib.py Tarab_HideOriginalBanner_FORCE.ipa "$DYLIB"
echo "Created Tarab_HideOriginalBanner_FORCE.ipa"
