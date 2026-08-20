# std-freestanding

The freestanding subset of the C++ standard library, as one module.

⚠️ **libc++'s subset, specifically.** The freestanding subset is defined by the
standard and every implementation is meant to provide one, but this package
provides exactly one of them: it synthesises libc++'s `__config_site` and reads
libc++'s headers. A toolchain carrying libstdc++ or the MSVC standard library is
told so in words rather than failing on a missing header — see
[Which hosts this works from](#which-hosts-this-works-from).

```cpp
import mcpplibs.std.freestanding;

std::array<Task, 4> t{...};
std::ranges::sort(t, {}, &Task::prio);   // on bare metal
```

```toml
[dependencies]
std-freestanding = "0.2.0"
riscv-virt-rt    = "0.4.1"   # the board: crt0, memory layout, emulator
```

## Why this exists

`import std;` is **one module over the whole library** — threads, filesystem
and iostreams included — so there is no subset of *it* to build without an OS.
mcpp turns it off on a freestanding target and says so.

But libc++'s **headers** are almost entirely freestanding-capable already. What
stops them is a single per-target file, `__config_site`, which the toolchain
ships only for its own host triple. Synthesising that file is this package's
whole job.

## What you get

⚠️ Measured, not asserted. `tools/regenerate.sh` compiles every one of libc++'s
110 headers for the target and keeps the ones that work:

| | |
|---|---|
| compiles for `riscv64-none-elf` | **103 / 110** |
| the other 7 | `generator` `hazard_pointer` `rcu` `spanstream` `stacktrace` `stdfloat` `text_encoding` |

⭐ **All 7 fail on an x86_64 host with full libc++ and glibc too** — they are
headers libc++ has not implemented. **The freestanding loss at compile time is
zero.** The regeneration script prints that control group every time it runs,
because without it "libc++ has not written it" reads as "bare metal cannot do
it".

Verified running under the emulator: `array` · `span` · `optional` ·
`expected` · `atomic` · `string_view` · `ranges::sort` with a projection ·
`bit` · `charconv` · `concepts` · `type_traits` · `tuple` · coroutines.

## What you do NOT get, and how you find out

Capabilities turned off in `__config_site` **vanish** rather than leaving a stub
that fails at run time:

```
error: no type named 'mutex' in namespace 'std'
```

That is the diagnostic a bare-metal author wants — at compile time, by name.
`std::thread`, `std::mutex`, `<filesystem>` and locale-dependent formatting are
gone for the same reason: there is no OS under them.

## The boundary

| Tier | Needs | Gets you |
|---|---|---|
| **header-only** (this package) | picolibc headers + the synthesised config | everything listed above |
| **+ `libc.a`** (your board package) | picolibc | the heap, and the `memcpy`/`memmove` the compiler emits by itself |
| **+ a target-built `libc++.a`** | ⚠️ not published | `std::format`, scalar `std::sort`, full `std::string` |

The third row is a real boundary, not an oversight: libc++ keeps those bodies
in its compiled library (`std::sort` for builtin scalars is an `extern template`
with no macro to disable), so they cannot come from headers. Reaching for
`std::format` today fails at **link** time, naming the symbol.

## Requirements

- **mcpp ≥ 2026.8.19.4**, for two things it introduced: `-fno-exceptions` on a
  freestanding target (without it `std::optional::value()` alone pulls in
  `__cxa_throw`, `vtable for std::exception` and two more, none of which exist
  without an unwinder), and the target supplying its own C library.
- **Nothing else.** ⚠️ This package declares no dependencies at all — no C
  library, no architecture, no toolchain. It asks mcpp where the toolchain's
  headers are (`mcpp::toolchain_dir()`), and the target's C headers are already
  on the compile line because the C library belongs to the target. An earlier
  version declared `xim:picolibc-riscv@1.8.12` and `xim:llvm`, which pinned a
  package made entirely of standard-mandated names to one libc, one ISA and one
  standard-library implementation.

## Regenerating

```bash
tools/regenerate.sh <llvm-payload-dir> <picolibc-dir> [rv64gc/lp64d]
```

⚠️ Run it when the toolchain moves, and **read the control group it prints**.
The export table is never hand-written: libc++ ships one `std/<header>.inc` per
header, each `export namespace std { using std::X; }`, and maintains them. This
package only selects.

## License

Apache-2.0. It exports libc++'s names; libc++ is Apache-2.0 WITH
LLVM-exception.

## Which hosts this works from

The target is a cross target, so the host is a separate axis: the compiler and
the target's C library are payloads mcpp resolves for whichever system it runs
on. Nothing about building for `riscv64-none-elf` ought to depend on the host,
and for the rest of this ecosystem it does not.

| Host | Cross-builds this package |
|---|---|
| Linux | yes |
| macOS | yes |
| Windows | **no**, and the reason is this package's, not the platform's |

⚠️ On Windows the LLVM payload ships clang against the **MSVC standard library**
and carries no libc++. The compiler is still clang and the target is still
`riscv64-none-elf` — the cross-compilation is unaffected. What is missing is a
standard library implementation this package knows how to read.

That is a limitation worth stating precisely, because the obvious reading is
wrong twice over. It is not that freestanding C++ needs an operating system, and
it is not that Windows cannot cross-compile: sibling packages in this ecosystem
(`std-freestanding-nolibc`, `std-freestanding-alloc-kal`,
`std-freestanding-alloc-libc`, `openkal-opensbi`) all cross-build from Windows
for the same target, because none of them reads a standard library's headers.

The fix is a second backend. `__config_site` synthesis is libc++'s mechanism;
libstdc++ configures through `c++config.h` and the MSVC standard library through
`yvals_core.h`, and the export lists this package generates are lists of
*standard* names, which is the part that would carry over unchanged.

Until then, `mcpp build` on such a toolchain stops with a message naming the
cause rather than with `'algorithm' file not found`, and CI asserts that message
on Windows — so the day the gap closes, that assertion fails and says so.
