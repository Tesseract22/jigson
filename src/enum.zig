const std = @import("std");

test "enum" {
    const u = union(enum) {
        a: i32,
        b: u32,
        c: bool,
    };
    std.debug.print("\n", .{});
    inline for (std.meta.fields(u)) |f| {
        std.debug.print("field of u: {s}\n", .{f.name});
    }
    std.debug.print("tag as string: {s}\n", .{@tagName(u.a)});
}
