# std-freestanding

The freestanding subset of the C++ standard library, as one module.

⭐ **All 34 headers the standard mandates for a freestanding implementation, and
41 more.** Measured for `riscv64-none-elf`; see
[What the standard asks for](#what-the-standard-asks-for).

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

## What the standard asks for

C++23 and C++26 define the freestanding subset as a list, and the list is
shorter and differently shaped than this package's headline numbers suggest.
Three tiers are worth separating, because they fail for different reasons:

| Tier | Count | What it is |
|---|---|---|
| **Mandated, "All"** | 22 | `<cstddef>` `<cfloat>` `<climits>` `<limits>` `<version>` `<cstdint>` `<new>` `<typeinfo>` `<source_location>` `<exception>` `<initializer_list>` `<compare>` `<coroutine>` `<cstdarg>` `<concepts>` `<type_traits>` `<ratio>` `<utility>` `<tuple>` `<bit>` `<atomic>` `<debugging>` |
| **Mandated, "Partial"** | 12 | `<cstdlib>` `<cerrno>` `<system_error>` `<memory>` `<functional>` `<charconv>` `<string>` `<cstring>` `<cwchar>` `<iterator>` `<ranges>` `<cmath>` `<random>` `<execution>` — the parts that do not allocate or depend on an environment |
| **Beyond the standard** | 41 | `<array>` `<span>` `<optional>` `<expected>` `<string_view>` `<algorithm>` `<vector>` and the rest — libc++ compiles them for this target, and the standard does not require any implementation to |

⚠️ The third tier is where this package's advertised examples live. `std::array`
and `std::span` are **not** freestanding-mandated; that they work here is
libc++'s doing, not the standard's. Stating it the other way round would credit
the standard with a guarantee it does not make.

⭐ Measured for `riscv64-none-elf` with this package's synthesised
configuration: **34 of 34 mandated headers compile**, and so do the 41 beyond
them. The "Partial" tier is partial in *content* rather than in availability —
`<memory>`'s allocating half needs an `operator new`, which is what the `alloc`
features supply.

## Which hosts this works from

The target is a cross target, so the host is a separate axis: the compiler and
the target's C library are payloads mcpp resolves for whichever system it runs
on. Nothing about building for `riscv64-none-elf` ought to depend on the host.

| Host | Cross-builds this package |
|---|---|
| Linux | yes |
| macOS | yes |
| Windows | **no**, and the cause is in the payload |

⚠️ **The obvious reading is wrong twice over, and the second-obvious reading is
wrong too.** It is not that freestanding C++ needs an operating system, and it is
not that Windows cannot cross-compile — sibling packages
(`std-freestanding-nolibc`, `std-freestanding-alloc-kal`,
`std-freestanding-alloc-libc`, `openkal-opensbi`) all cross-build from Windows
for the same target. Nor is it that this package "chose libc++ and should not
have":

* libc++'s headers are **host-independent text**. The same clang
  cross-compiling to `riscv64-none-elf` reads them identically on every host.
* What libc++ does not ship host-independently is `__config_site`, which exists
  once, under the payload's own host triple. **Measured: with the payload's own
  configuration and no synthesis, all 34 mandated headers fail on the first line
  of `__config`** — none of them reaches its own content. Synthesising that file
  is not a workaround for having picked libc++; it is the only way to use libc++
  for a target the payload was not configured for.

The Windows LLVM payload builds clang against the MSVC standard library for
Windows-hosted work and ships no libc++ at all — which also removes libc++ from
every cross-compilation that payload could otherwise serve. That is the whole of
the gap, and the fix belongs in the payload.

### Would the MSVC standard library do instead?

Not for this target, and the reason is not that Microsoft has not written a
freestanding mode. Its headers rest on the Windows C runtime — `<vcruntime.h>`,
the UCRT, `__declspec` — and none of that exists for `riscv64-none-elf`. The
missing piece is not a switch; it is the layer underneath.

⚠️ That paragraph is reasoning rather than measurement, so CI measures it: the
Windows job reports what the payload actually carries, instead of this file
asserting it.

### And libstdc++?

⭐ Measured on the host: `-D_GLIBCXX_HOSTED=0` alone compiles **29 of the 34**
mandated headers, with no configuration synthesis whatsoever. The five that fail
— `<system_error>` `<charconv>` `<string>` `<cmath>` `<random>` — are the C++26
additions to the freestanding set that GCC 16 has not implemented yet.

So a libstdc++ backend would be *simpler* than the libc++ one rather than a
parallel effort, and it is a plausible future direction. It is not a fix for the
Windows gap, though: mcpp's target row for `riscv64-none-elf` resolves llvm, and
no libstdc++ reaches that target in this ecosystem today.

