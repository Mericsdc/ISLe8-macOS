#!/bin/sh
# Xcode build phase: compiles the MediaRemote bridge that /usr/bin/perl loads at runtime
# (see isle8_mr.m) into the app's Frameworks folder and signs it with the app's identity.
set -e

out="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
mkdir -p "$out"

arch_flags=""
for arch in $ARCHS; do
    arch_flags="$arch_flags -arch $arch"
done

# shellcheck disable=SC2086
xcrun clang $arch_flags -dynamiclib -fobjc-arc -O2 -Wall \
    -mmacosx-version-min="$MACOSX_DEPLOYMENT_TARGET" \
    -framework Foundation \
    -o "$out/libisle8mr.dylib" "$SRCROOT/Adapter/isle8_mr.m"

if [ -n "$EXPANDED_CODE_SIGN_IDENTITY" ]; then
    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$out/libisle8mr.dylib"
fi
