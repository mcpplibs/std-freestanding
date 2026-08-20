#!/usr/bin/env bash
# Regenerate src/std_freestanding.cppm by MEASURING which libc++ headers
# compile for a freestanding target — never by curating a list.
#
# ⚠️ Run this when the toolchain moves, and read the host control group it
# prints. Headers that fail here AND on the host are headers libc++ has not
# implemented; recording those as "bare metal cannot do it" is the mistake this
# script exists to make impossible.
#
#   tools/regenerate.sh <llvm-payload-dir> <picolibc-dir> [profile]
set -euo pipefail
LLVM="${1:?usage: regenerate.sh <llvm-dir> <picolibc-dir> [profile]}"
PICO="${2:?usage: regenerate.sh <llvm-dir> <picolibc-dir> [profile]}"
PROFILE="${3:-rv64gc/lp64d}"
ARCH="${PROFILE%%/*}"; ABI="${PROFILE##*/}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/cfg/c++/v1"
sed -e 's/^#define _LIBCPP_HAS_THREADS .*/#define _LIBCPP_HAS_THREADS 0/' \
    -e 's/^#define _LIBCPP_HAS_MONOTONIC_CLOCK .*/#define _LIBCPP_HAS_MONOTONIC_CLOCK 0/' \
    -e 's/^#define _LIBCPP_HAS_FILESYSTEM .*/#define _LIBCPP_HAS_FILESYSTEM 0/' \
    -e 's/^#define _LIBCPP_HAS_LOCALIZATION .*/#define _LIBCPP_HAS_LOCALIZATION 0/' \
    -e 's/^#define _LIBCPP_HAS_TERMINAL .*/#define _LIBCPP_HAS_TERMINAL 0/' \
    -e 's/^#define _LIBCPP_HAS_RANDOM_DEVICE .*/#define _LIBCPP_HAS_RANDOM_DEVICE 0/' \
    -e 's/^#define _LIBCPP_HAS_TIME_ZONE_DATABASE .*/#define _LIBCPP_HAS_TIME_ZONE_DATABASE 0/' \
    -e 's/^#define _LIBCPP_HAS_WIDE_CHARACTERS .*/#define _LIBCPP_HAS_WIDE_CHARACTERS 0/' \
    -e 's/^#define _LIBCPP_LIBC_PICOLIBC .*/#define _LIBCPP_LIBC_PICOLIBC 1/' \
    -e 's/^#define _LIBCPP_PSTL_BACKEND_STD_THREAD/#define _LIBCPP_PSTL_BACKEND_SERIAL/' \
    "$LLVM"/include/*/c++/v1/__config_site > "$WORK/cfg/c++/v1/__config_site"

: > "$WORK/ok"; : > "$WORK/bad"
for inc in "$LLVM"/share/libc++/v1/std/*.inc; do
    h="$(basename "$inc" .inc)"
    printf '#include <%s>\nint main(){return 0;}\n' "$h" > "$WORK/t.cpp"
    if "$LLVM/bin/clang++" --target=riscv64-none-elf -march="$ARCH" -mabi="$ABI" \
        -mcmodel=medany -std=c++23 -ffreestanding -fno-exceptions -fno-rtti \
        -nostdinc++ --no-default-config -isystem "$WORK/cfg/c++/v1" \
        -isystem "$LLVM/include/c++/v1" -isystem "$PICO/include/$PROFILE" \
        -fsyntax-only "$WORK/t.cpp" >/dev/null 2>&1
    then echo "$h" >> "$WORK/ok"; else echo "$h" >> "$WORK/bad"; fi
done
echo "compiles for $PROFILE: $(wc -l < "$WORK/ok") / $(ls "$LLVM"/share/libc++/v1/std/*.inc | wc -l)"

# ⭐ The control group. Without it the next line is unreadable.
echo "── the ones that failed, retried on THIS host with full libc++ ──"
while read -r h; do
    printf '#include <%s>\nint main(){return 0;}\n' "$h" > "$WORK/h.cpp"
    if "$LLVM/bin/clang++" -std=c++23 -stdlib=libc++ -fsyntax-only "$WORK/h.cpp" >/dev/null 2>&1
    then echo "  $h: HOST OK   ← a real freestanding loss"
    else echo "  $h: host fails too (libc++ has not implemented it)"; fi
done < "$WORK/bad"

# ── The headers that need a C library, for the `nolibc` feature ─────────────
#
# ⚠️ MEASURED HERE, NOT LISTED BY HAND. The `nolibc` feature makes the subset
# usable on a target whose sysroot is empty, and 94 of these headers compile
# there once the four shim headers are on the path. The rest want a real C
# library and are compiled out.
#
# The list lives in this script rather than in the module for the same reason
# the module's own list does: a hand-written set drifts from the toolchain, and
# the check that regeneration is a no-op is what keeps them together.
NOLIBC_EXCLUDE="cinttypes cmath complex cstdlib exception format print random valarray"

# ── The headers C++26 made freestanding, and the macro that announces each ──
#
# ⚠️ THE RULE IS "A MACRO PRESENT AND TOO OLD EXCLUDES; A MACRO ABSENT DOES
# NOT", AND THE ASYMMETRY IS THE WHOLE POINT.
#
# C++26 gives an implementation a way to say which headers it has made
# freestanding. Using that as a gate would be wrong today in the loudest
# possible way: measured 2026-08-20, libc++ 22.1.8 defines NONE of these macros
# and libstdc++ 16.1.0 defines seven — so a gate would report that libc++
# provides no freestanding headers at all, and empty this package on the
# implementation it is built for.
#
# Neither implementation defines `__cpp_lib_freestanding_feature_test_macros`
# either, so there is not even a reliable way to ask "do you implement this
# mechanism". Absence is therefore ambiguous: it means "not freestanding" or "no
# opinion yet", and the two are indistinguishable.
#
# So absence falls back to what this script MEASURED by compiling. A macro that
# is present and below the required value is the only unambiguous statement
# available — the implementation has considered the header and says no — and it
# is the only case that excludes.
#
# The value beside each name is the one the standard assigns to that macro.
FS_MACROS="
algorithm:202311
array:202311
charconv:202306
cstdlib:202306
cstring:202311
cwchar:202306
execution:202502
expected:202311
functional:202306
iterator:202306
mdspan:202311
memory:202306
numeric:202311
optional:202311
random:202502
ranges:202306
ratio:202306
string_view:202311
tuple:202306
utility:202306
variant:202311
"

fs_macro_value() {   # $1 = header name; echoes the required value, or nothing
    printf '%s' "$FS_MACROS" | while IFS=: read -r n v; do
        if [ "$n" = "$1" ]; then printf '%s' "$v"; fi
    done
}

guarded() {   # $1 = template with %s for the header name
    while read -r h; do
        nolibc=no
        case " $NOLIBC_EXCLUDE " in *" $h "*) nolibc=yes ;; esac
        want="$(fs_macro_value "$h")"

        # ⚠️ `if` rather than `[ ... ] && ...`. Under `set -e` a trailing
        # `&&` whose test is false makes the FUNCTION return non-zero, and the
        # script stops there — which truncated the generated module to zero
        # includes while every individual piece was correct.
        if [ "$nolibc" = yes ]; then printf '#ifndef MCPP_FEATURE_NOLIBC\n'; fi
        if [ -n "$want" ]; then
            m="__cpp_lib_freestanding_$h"
            printf '#if !defined(%s) || %s >= %sL\n' "$m" "$m" "$want"
        fi
        printf "$1\n" "$h"
        if [ -n "$want" ];        then printf '#endif\n'; fi
        if [ "$nolibc" = yes ]; then printf '#endif\n'; fi
    done < "$WORK/ok"
}

{
  echo "// mcpplibs.std.freestanding — the freestanding subset of the standard library."
  echo "//"
  echo "// GENERATED by tools/regenerate.sh. The list is not a curated opinion: it is"
  echo "// every libc++ header that compiles for a freestanding target, measured by"
  echo "// compiling each one."
  echo "//"
  echo "// ⚠️ NINE HEADERS ARE GUARDED BY \`MCPP_FEATURE_NOLIBC\`, AND THAT LIST IS"
  echo "// MEASURED TOO. On a target whose sysroot is empty there is no C library at"
  echo "// all; 94 of the headers below still compile, because the \`nolibc\` feature"
  echo "// supplies the four C headers libc++'s own wrappers reach for. The nine that"
  echo "// want a real one are compiled out, and their export tables with them — an"
  echo "// export table naming absent declarations is an error in the module"
  echo "// interface, not in the consumer."
  echo "//"
  echo "// ⚠️ The export table is NOT here and must never be written here. libc++ ships"
  echo "// one \`std/<header>.inc\` per header — each \`export namespace std { using"
  echo "// std::X; }\` — and maintains them. This file only SELECTS."
  echo "module;"
  guarded '#include <%s>'
  echo "export module mcpplibs.std.freestanding;"
  guarded '#include "std/%s.inc"'
} > "$ROOT/src/std_freestanding.cppm"
echo "wrote src/std_freestanding.cppm"
