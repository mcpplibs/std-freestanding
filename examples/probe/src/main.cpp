import mcpplibs.riscv_virt_rt;
import mcpplibs.std.freestanding;

// Deliberately exercises the facilities whose availability was the open
// question — not `<type_traits>`, which was never in doubt.
struct Task { int prio; const char* name; };

extern "C" int main() {
    std::array<Task, 4> t{{ {3,"c"}, {1,"a"}, {4,"d"}, {2,"b"} }};
    // A projection keeps this entirely header-resident. The scalar std::sort
    // is an extern template whose body lives in the compiled libc++, which is
    // exactly the boundary this package does not cross.
    std::ranges::sort(t, {}, &Task::prio);
    for (const auto& x : t) board::print(x.name);
    board::print("\n");

    std::optional<int> o = 41;
    std::atomic<int> a{0};
    a.fetch_add(o.value() + 1);
    board::printf("atomic %d\n", a.load());

    std::span<Task> s{t};
    std::string_view sv{"span+string_view"};
    board::printf("%.*s / %d\n", (int)sv.size(), sv.data(), (int)s.size());
    return 0;
}
