const Json = @import("json.zig");
const std = @import("std");

export fn jp_parser_create(ctx: *anyopaque, alloc: ?*const fn (ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8, resize: ?*const fn (ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool, free: ?*const fn (ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void) callconv(.C) ?*Json {
    var alloc_p = alloc;
    var resize_p = resize;
    var free_p = free;

    if (alloc == null or resize == null or free == null) {
        var callocator = std.heap.c_allocator;
        alloc_p = callocator.vtable.alloc;
        resize_p = callocator.vtable.resize;
        free_p = callocator.vtable.free;
    }
    var jallocator = std.mem.Allocator{ .ptr = ctx, .vtable = &.{ .alloc = alloc_p.?, .resize = resize_p.?, .free = free_p.? } };
    const j = jallocator.create(Json) catch {
        return null;
    };
    const vtable = jallocator.create(std.mem.Allocator.VTable) catch {
        return null;
    };
    vtable.* = .{ .alloc = alloc_p.?, .resize = resize_p.?, .free = free_p.? };
    jallocator.vtable = vtable;
    j.* = Json.init(jallocator);
    return j;
}

export fn jp_parser_destroy(j: ?*Json) callconv(.C) void {
    if (j) |payload| {
        var jallocator = payload.allocator;

        var vtable_ptr = jallocator.vtable;
        jallocator.vtable = &.{ .alloc = vtable_ptr.alloc, .resize = vtable_ptr.resize, .free = vtable_ptr.free };
        jallocator.destroy(vtable_ptr);
        jallocator.destroy(payload);
    }
}
export fn jp_parser_parse(j: ?*Json, str: ?[*:0]const u8) callconv(.C) ?*anyopaque {
    if (str) |s| {
        if (j) |p| {
            const res = Json.JsonParser(p, s);
            if (res) |r| {
                const dup: *Json.Result(Json.JsonType) = p.allocator.create(Json.Result(Json.JsonType)) catch return null;

                dup.remain = r.remain;
                dup.result = r.result;
                return dup;
            }
        }
    }

    return null;
}

const c_json_type = enum(c_int) {
    JsonBool = 0,
    JsonInt = 1,
    JsonFloat = 2,
    JsonNull = 3,
    JsonArray = 4,
    JsonString = 5,
    JsonObject = 6,
};

// fn find_type(str: []const u8) c_int {
//     var i: i32 = 0;
//     return for (std.meta.fields(Json.JsonType)) |f| {
//         if (std.mem.eql(u8, f.name, str)) {
//             break i;
//         }
//         i += 1;
//     } else false;
// }

const json_res = Json.Result(Json.JsonType);

export fn jp_json_get_type(res: ?*json_res) callconv(.C) c_int {
    if (res) |r| {
        switch (r.result) {
            .JsonBool => |_| return @intFromEnum(c_json_type.JsonBool),
            .JsonInt => |_| return @intFromEnum(c_json_type.JsonInt),
            .JsonFloat => |_| return @intFromEnum(c_json_type.JsonFloat),
            .JsonNull => |_| return @intFromEnum(c_json_type.JsonNull),
            .JsonArray => |_| return @intFromEnum(c_json_type.JsonArray),
            .JsonString => |_| return @intFromEnum(c_json_type.JsonString),
            .JsonObject => |_| return @intFromEnum(c_json_type.JsonObject),
        }
    }
    return -1;

    // switch (res.?.result) {
    //     .JsonBool => |_| return find_type(@tagName(.JsonBool)),
    //     .JsonInt => |_| return find_type(@tagName(.JsonInt)),
    //     .JsonFloat => |_| return find_type(@tagName(.JsonFloat)),
    //     .JsonNull => |_| return find_type(@tagName(.JsonNull)),
    //     .JsonArray => |_| return find_type(@tagName(.JsonArray)),
    //     .JsonString => |_| return find_type(@tagName(.JsonString)),
    //     .JsonObject => |_| return find_type(@tagName(.JsonObject)),
    // }
}

export fn jp_json_debug(res: ?*json_res) callconv(.C) void {
    if (res) |r| {
        std.debug.print("{}\n", .{r});
    }
}

export fn jp_json_get_data(res: ?*json_res) callconv(.C) ?*anyopaque {
    if (res) |*r| {
        switch (r.*.result) {
            // .JsonBool => |b| return @constCast(@ptrCast(&b)),
            // .JsonInt => |i| return @constCast(@ptrCast(&i)),
            // .JsonFloat => |f| {
            //     std.debug.print("addr of f: {*}, val: {} {}\n", .{ &f, f, (&f).* });
            //     return @constCast(@ptrCast(&f));
            // },
            .JsonNull => |_| return null,
            .JsonArray => |arr| return @constCast(@ptrCast(arr.items)),
            .JsonString => |str| return @constCast(@ptrCast(str.items)),
            .JsonObject => |arr| return @constCast(@ptrCast(arr.items)),
            else => return &(r.*.result),
        }
    }
    return null;
}
export fn jp_json_arr_get(res: ?*json_res, i: c_uint) callconv(.C) ?*Json.JsonType {
    if (res) |r| {
        switch (r.result) {
            .JsonArray => |arr| return &arr.items[i],
            else => return null,
        }
    }
    return null;
}

export fn jp_json_arr_len(res: ?*json_res) callconv(.C) c_ulong {
    if (res) |r| {
        switch (r.result) {
            .JsonArray => |arr| return arr.items.len,
            .JsonObject => |arr| return arr.items.len,
            .JsonString => |arr| return @intCast(arr.items.len),
            else => return 0,
        }
    }
    return 0;
}

export fn jp_json_destroy(j: ?*Json, res: ?*json_res) callconv(.C) void {
    res.?.deinit();
    j.?.allocator.destroy(res.?);
}
const expect = std.testing.expect;
test "create" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var gpa_allocator = gpa.allocator();
    defer {
        const status = gpa.deinit();
        expect(status != .leak) catch @panic("memort leak");
    }
    const j1 = jp_parser_create(gpa_allocator.ptr, gpa_allocator.vtable.alloc, gpa_allocator.vtable.resize, gpa_allocator.vtable.free);
    defer jp_parser_destroy(j1);
    try expect(j1 != null);
    // defer gpa_allocator.destroy(j1.?);
    var r1 = j1.?.JsonParser("[5, 2, null, true, [\"aa\", {}]]");
    if (r1) |*r| {
        std.debug.print("\nresult: |{s}|\nremain: |{s}|\n", .{ r.result, r.remain });
        r.deinit();
    } else {
        std.debug.print("null\n", .{});
    }

    const j2 = jp_parser_create(undefined, null, null, null);
    defer jp_parser_destroy(j2);
    try expect(j2 != null);
    // defer gpa_allocator.destroy(j1.?);
    var r2 = j2.?.JsonParser("[5, 2, null, true, [\"aa\", {}]]");
    if (r2) |*r| {
        std.debug.print("\nresult: |{s}|\nremain: |{s}|\n", .{ r.result, r.remain });
        r.deinit();
    } else {
        std.debug.print("null\n", .{});
    }
}
