#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$ROOT/config.json"
source "$CFG"

: "${OO_PS4_TOOLCHAIN:?OO_PS4_TOOLCHAIN missing}"
: "${GOLDHEN_SDK:?GOLDHEN_SDK missing}"

CC="${CC:-clang}"
LD="${LD:-ld.lld}"
OUT="$ROOT/build/vcfg"
SRC="$ROOT/plugin"
mkdir -p "$OUT"

VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
DEFS=(
  -D_BSD_SOURCE=1 -D__BSD_VISIBLE=1 -D__PS4__=1 -DOO=1
  -D__OPENORBIS__=1 -D__OOPS4__=1 -D__FINAL__=1 -D__USE_PRINTF__
  -DA21_SLAB2=1 -DA21_POST=1 -DA21_MENU=1 -DA21_SCHED=1 -DA22_UNIVERSAL=1
  -DVCFG_VER="$VERSION"
)
INCLUDES=(
  -isysroot "$OO_PS4_TOOLCHAIN" -isystem "$OO_PS4_TOOLCHAIN/include"
  -I"$GOLDHEN_SDK/include" -I"$SRC/common" -I"$SRC/source" -I"$ROOT/overlay"
)
FLAGS=(--target=x86_64-pc-freebsd12-elf -fPIC -funwind-tables -ffile-prefix-map="$ROOT=." -Wno-c99-designator -Werror=format)

rm -f "$OUT"/*.o "$OUT/vcfg.elf" "$OUT/vcfg.oelf" "$OUT/vcfg.prx"
objs=()
while IFS= read -r -d "" f; do
  o="$OUT/$(basename "${f%.*}").o"
  "$CC" "${FLAGS[@]}" "${DEFS[@]}" "${INCLUDES[@]}" -c "$f" -o "$o"
  objs+=("$o")
done < <(find "$SRC/common" "$SRC/source" -maxdepth 1 -type f -name "*.c" -print0)

"$CC" "${FLAGS[@]}" "${DEFS[@]}" "${INCLUDES[@]}" -c "$ROOT/overlay/vov.c" -o "$OUT/vov.o"
objs+=("$OUT/vov.o")

"$LD" -m elf_x86_64 -pie -e _init --script "$OO_PS4_TOOLCHAIN/link.x" --eh-frame-hdr \
  -L"$OO_PS4_TOOLCHAIN/lib" -L"$GOLDHEN_SDK" \
  "$GOLDHEN_SDK/build/crtprx.o" "${objs[@]}" \
  -lSceLibcInternal -lSceGnmDriver -lSceVideoOut -lScePad -lGoldHEN_Hook \
  -lkernel -lSceSysmodule -lSceSystemService -lSceUserService \
  -o "$OUT/vcfg.elf"

"$OO_PS4_TOOLCHAIN/bin/linux/create-fself" -in="$OUT/vcfg.elf" -out="$OUT/vcfg.oelf" -lib="$OUT/vcfg.prx" --paid 0x3800000000000011

echo "Built: $OUT/vcfg.prx"
sha256sum "$OUT/vcfg.prx"
