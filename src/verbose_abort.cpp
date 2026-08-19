// The ONE symbol this package cannot take from a header.
//
// Under -fno-exceptions every `__throw_*` in libc++ funnels here, so without a
// definition the link fails on `std::__1::__libcpp_verbose_abort` with no hint
// about which facility pulled it in. Measured: it is the ONLY symbol missing
// from an otherwise header-only link of array/span/ranges/optional/atomic/
// string_view.
//
// ⚠️ It must be declared through libc++'s OWN header, not written out by hand
// in `namespace std`. The real symbol lives in the ABI inline namespace
// (`std::__1::`), so a hand-rolled `namespace std { ... }` definition compiles,
// links nothing, and leaves the original undefined-symbol error untouched —
// measured, and the error looks identical before and after.
#include <__verbose_abort>

_LIBCPP_BEGIN_NAMESPACE_STD

// Halts rather than returning: the contract is "the program has already gone
// wrong", and returning would carry on into the state libc++ just declared
// impossible. A board that wants a message overrides this with its own
// definition — the reason it is a weak-by-convention seam rather than inline.
[[noreturn]] void __libcpp_verbose_abort(const char*, ...) _NOEXCEPT {
    for (;;) {
#if defined(__riscv)
        __asm__ volatile("wfi");
#endif
    }
}

_LIBCPP_END_NAMESPACE_STD
