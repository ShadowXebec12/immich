#!/usr/bin/env bash
# Checks the rust core in the release apk: Google Play rejects a LOAD segment below 16 KB alignment,
# and a library linked against an API level above minSdk fails to load on older devices

set -euo pipefail

apk=build/app/outputs/flutter-apk/app-release.apk
min_sdk=$(sed -nE 's/^ *minSdk = ([0-9]+)$/\1/p' android/app/build.gradle)
readelf=$(find "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}/ndk" -name llvm-readelf | sort -V | tail -n 1)
[[ $min_sdk && -x $readelf ]] || { echo "minSdk or llvm-readelf not found" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for abi in armeabi-v7a arm64-v8a x86_64; do
  lib=$tmp/$abi.so
  unzip -p "$apk" "lib/$abi/libimmich_core_ffi.so" > "$lib"

  # every loadable segment must be aligned to 16 KB (0x4000)
  "$readelf" --program-headers --wide "$lib" | awk '$1 == "LOAD" && $NF != "0x4000" { bad = 1 } END { exit bad }' \
    || { echo "$abi: a LOAD segment is not 16 KB aligned" >&2; exit 1; }

  # the Android ELF note starts with the API level the library was linked against, 4 bytes little endian
  note=$("$readelf" --notes "$lib" | sed -nE '/^ *Android/,$ s/.*description data: *//p')
  [[ $note ]] || { echo "$abi: no Android ELF note" >&2; exit 1; }
  read -r b0 b1 b2 b3 _ <<< "$note"
  api=$((16#$b3$b2$b1$b0))
  (( api <= min_sdk )) || { echo "$abi: linked against API $api, minSdk is $min_sdk" >&2; exit 1; }

  echo "$abi ok: 16 KB aligned, API $api"
done
