#!/usr/bin/env bash
# How many of this package's headers compile for a target with NO C library.
#
# ⚠️ THE MEASUREMENT IS MADE WITH THIS PACKAGE'S OWN INCLUDE PATHS, NOT FROM A
# CONSUMER PROJECT, AND THAT DISTINCTION IS THE WHOLE REASON THIS FILE EXISTS.
#
# The CI step this replaces built a consumer project with
# `std-freestanding = { path = ..., features = ["nolibc"] }` and then compiled
# `#include <array>` in it. That worked only while `include_dir` leaked from a
# dependency to its consumer. It is package-private by design — this package's
# own build program says so, and it is why `std-freestanding-nolibc` cannot add
# its headers for us — so when the leak closed the step reported
#
#     zero-libc: 0 compile, 103 do not
#
# and the number it was checking dropped to zero without anything about the
# package changing. A measurement that depends on a leak is not a measurement.
#
# What is actually being claimed is a property of THIS package's compile: given
# libc++'s headers, the synthesised `__config_site`, and the four C headers the
# `nolibc` feature brings, how many of the 103 still compile with no C library
# under them. So the probe uses those paths directly.
#
# Measured 2026-08-20 for rv64gc/lp64d: 94 of 103. The nine that fail are
# exactly the `NOLIBC_EXCLUDE` list in tools/regenerate.sh, which is what makes
# the two files consistent rather than merely agreeing by accident.
set -euo pipefail
export LC_ALL=C

LLVM="${1:?usage: probe-zero-libc.sh <llvm-payload-dir> <nolibc-include-dir> [config-site-dir]}"
NLINC="${2:?usage: probe-zero-libc.sh <llvm-payload-dir> <nolibc-include-dir> [config-site-dir]}"
CFG="${3:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CL="$LLVM/bin/clang++"
[ -x "$CL" ] || { echo "no clang++ under $LLVM"; exit 1; }

# ⚠️ The synthesised `__config_site`, not a copy of it. libc++ ships that file
# only for the payload's own host triple, so a cross target has none; this
# package generates one during a build, and re-deriving it here would be the
# same decision written twice. The caller passes the directory a build produced.
if [ -z "$CFG" ]; then
    CFG="$(find "$ROOT" -type d -path '*/libcxx-config/c++/v1' 2>/dev/null | head -1)"
fi
[ -n "$CFG" ] && [ -f "$CFG/__config_site" ] \
    || { echo "no synthesised __config_site; build the package first"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

BASE="--no-default-config --target=riscv64-none-elf -march=rv64gc -mabi=lp64d"
BASE="$BASE -mcmodel=medany -ffreestanding -fno-exceptions -fno-rtti -std=c++23"
BASE="$BASE -nostdinc++ -nostdlibinc"
INC="-isystem $CFG -isystem $LLVM/include/c++/v1 -isystem $LLVM/lib/clang/22/include"
INC="$INC -isystem $NLINC"

ok=0; bad=0; failed=""
for h in $(grep -oE '^#include <[a-z_]+>' "$ROOT/src/std_freestanding.cppm" \
           | sed 's/#include <//;s/>//'); do
    printf '#include <%s>\n' "$h" > "$WORK/t.cpp"
    if "$CL" $BASE $INC -fsyntax-only "$WORK/t.cpp" 2>/dev/null
    then ok=$((ok + 1)); else bad=$((bad + 1)); failed="$failed $h"; fi
done

echo "zero-libc: $ok compile, $bad do not"
echo "failed:$failed"

# The nine are not an arbitrary set: they are the headers tools/regenerate.sh
# guards behind `MCPP_FEATURE_NOLIBC`. Asserting the agreement here is what
# keeps the two files from drifting into separately-plausible lists.
expected="$(sed -n 's/^NOLIBC_EXCLUDE="\(.*\)"$/\1/p' "$ROOT/tools/regenerate.sh")"
got="$(echo $failed | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"
want="$(echo $expected | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"
if [ "$got" != "$want" ]; then
    echo "the failing set and NOLIBC_EXCLUDE disagree:"
    echo "  probe:    $got"
    echo "  excluded: $want"
    exit 1
fi
echo "the failing set is exactly NOLIBC_EXCLUDE"

[ "$ok" -ge 94 ] || { echo "expected at least 94"; exit 1; }
