const std = @import("std");
const builtin = @import("builtin");
const process = std.process;

var buf: [1024 * 1024 * 5]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buf);
const allocator = fba.allocator();

const Json = struct {
    allocator: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) Json {
        return .{ .allocator = alloc };
    }

    const ArrayList = std.ArrayList;

    fn Pair(comptime T1: type, comptime T2: type) type {
        return struct { first: T1, second: T2 };
    }

    pub const JsonType = union(enum) {
        JsonBool: bool,
        JsonInt: i64,
        JsonFloat: f64,
        JsonNull: void,
        JsonArray: ArrayList(JsonType),
        JsonString: ArrayList(u8),
        JsonObject: ArrayList(Pair(JsonType, JsonType)),

        pub fn deinit() void {}
        pub fn format(
            self: JsonType,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            const w: u64 = options.width orelse 0;
            const opt = std.fmt.FormatOptions{
                .width = w + 2,
            };
            const pad = struct {
                pub fn f(wr: anytype, ww: u64) !void {
                    for (0..ww) |i| {
                        _ = i;
                        try wr.print(" ", .{});
                    }
                }
            }.f;
            switch (self) {
                .JsonBool => |val| {
                    try pad(writer, w);
                    try writer.print("JBool({})", .{val});
                },
                .JsonFloat => |val| {
                    try pad(writer, w);
                    try writer.print("JFloat({})", .{val});
                },
                .JsonInt => |val| {
                    try pad(writer, w);
                    try writer.print("JInt({})", .{val});
                },
                .JsonNull => |val| {
                    try pad(writer, w);
                    try writer.print("JNull", .{});
                    _ = val;
                },
                .JsonArray => |val| {
                    try pad(writer, w);
                    try writer.print("JArray([\n", .{});
                    for (val.items, 0..) |j, i| {
                        try j.format(fmt, opt, writer);
                        if (i < val.items.len - 1) try writer.print(",", .{});
                        try writer.print("\n", .{});
                    }
                    try pad(writer, w);
                    try writer.print("])", .{});
                },
                .JsonObject => |val| {
                    const opt2 = std.fmt.FormatOptions{ .width = w + 4 };
                    try pad(writer, w);
                    try writer.print("JObject({{\n", .{});
                    for (val.items, 0..) |j, i| {
                        try j.first.format(fmt, opt, writer);
                        try writer.print(":\n", .{});
                        try j.second.format(fmt, opt2, writer);
                        if (i < val.items.len - 1) try writer.print(",", .{});
                        try writer.print("\n", .{});
                    }
                    try pad(writer, w);
                    try writer.print("}})", .{});
                },
                .JsonString => |val| {
                    try pad(writer, w);
                    try writer.print("JString({s:.2})", .{val.items});
                },
            }
            try writer.writeAll("");
        }
    };

    pub fn Result(comptime T: type) type {
        return struct {
            result: T,
            remain: [*:0]const u8 = "",
        };
    }

    fn Parser(comptime T: type) type {
        return fn (self: *Json, str: [*:0]const u8) ?Result(T);
    }
    fn Composer(comptime T1: type, comptime T2: type, comptime R: type) type {
        return fn (a: Parser(T1), b: Parser(T2)) Parser(R);
    }
    fn Or(comptime T: type) Composer(T, T, T) {
        return struct {
            pub fn f(comptime a: Parser(T), comptime b: Parser(T)) Parser(T) {
                return struct {
                    pub fn r(self: *Json, str: [*:0]const u8) ?Result(T) {
                        if (a(self, str)) |res| {
                            return res;
                        }
                        return b(self, str);
                    }
                }.r;
            }
        }.f;
    }

    fn left(comptime T1: type, comptime T2: type) Composer(T1, T2, T1) {
        return struct {
            pub fn f(comptime a: Parser(T1), comptime b: Parser(T2)) Parser(T1) {
                return struct {
                    pub fn r(self: *Json, str: [*:0]const u8) ?Result(T1) {
                        if (a(self, str)) |res1| {
                            if (b(self, res1.remain)) |res2| {
                                return Result(T1){ .result = res1.result, .remain = res2.remain };
                            }
                        }
                        return null;
                    }
                }.r;
            }
        }.f;
    }
    fn right(comptime T1: type, comptime T2: type) Composer(T1, T2, T2) {
        return struct {
            pub fn f(comptime a: Parser(T1), comptime b: Parser(T2)) Parser(T2) {
                return struct {
                    pub fn r(self: *Json, str: [*:0]const u8) ?Result(T2) {
                        if (a(self, str)) |res| {
                            return b(self, res.remain);
                        }
                        return null;
                    }
                }.r;
            }
        }.f;
    }

    pub fn JNullParser(self: *Json, str: [*:0]const u8) ?Result(JsonType) {
        _ = self;
        if (std.mem.eql(u8, str[0..4], "null")) {
            return Result(JsonType){ .result = JsonType{ .JsonNull = {} }, .remain = str + 4 };
        }
        return null;
    }

    const orj = Or(JsonType);

    fn JtrueParser(self: *Json, str: [*:0]const u8) ?Result(JsonType) {
        _ = self;
        if (std.mem.eql(u8, str[0..4], "true")) {
            return Result(JsonType){ .result = JsonType{ .JsonBool = true }, .remain = str + 4 };
        }
        return null;
    }
    fn JfalseParser(self: *Json, str: [*:0]const u8) ?Result(JsonType) {
        _ = self;
        if (std.mem.eql(u8, str[0..5], "false")) {
            return Result(JsonType){ .result = JsonType{ .JsonBool = false }, .remain = str + 5 };
        }
        return null;
    }

    pub const JboolParser = orj(JfalseParser, JtrueParser);

    fn posIntParser(self: *Json, str: [*:0]const u8) ?Result(i64) {
        _ = self;
        const isInt = struct {
            pub fn f(c: u8) bool {
                return c >= '0' and c <= '9';
            }
        }.f;
        var i: u32 = 0;
        var c = str[i];
        while (c != 0) {
            if (!isInt(c)) {
                break;
            }
            i += 1;
            c = str[i];
        }
        if (i == 0) return null;
        const num = std.fmt.parseInt(i64, str[0..i], 10) catch unreachable;
        return Result(i64){ .result = num, .remain = str + i };
    }

    fn negIntParser(self: *Json, str: [*:0]const u8) ?Result(i64) {
        const res = right(u8, i64)(genCharParser('-'), posIntParser)(self, str);
        if (res) |r| {
            return Result(i64){ .result = -r.result, .remain = r.remain };
        }
        return null;
    }
    fn posFloatParser(self: *Json, str: [*:0]const u8) ?Result(f64) {
        _ = self;
        const isFloat = struct {
            pub fn f(c: u8) bool {
                var i: u8 = 0;
                if (c == '.') {
                    i += 1;
                    return i <= 1;
                }
                return c >= '0' and c <= '9';
            }
        }.f;
        var i: u32 = 0;
        var c = str[0];
        while (c != 0) {
            if (!isFloat(c)) {
                break;
            }
            i += 1;
            c = str[i];
        }
        if (i == 0) return null;
        const num = std.fmt.parseFloat(f64, str[0..i]) catch unreachable;
        return Result(f64){ .result = num, .remain = str + i };
    }

    fn negFloatParser(self: *Json, str: [*:0]const u8) ?Result(f64) {
        const res = right(u8, f64)(genCharParser('-'), posFloatParser)(self, str);
        if (res) |r| {
            return Result(f64){ .result = -r.result, .remain = r.remain };
        }
        return null;
    }
    pub fn JFloatParser(self: *Json, str: [*:0]const u8) ?Result(JsonType) {
        const res = Or(f64)(negFloatParser, posFloatParser)(self, str);
        if (res) |r| {
            return Result(JsonType){ .result = JsonType{ .JsonFloat = r.result }, .remain = r.remain };
        }
        return null;
    }

    pub fn JIntParser(self: *Json, str: [*:0]const u8) ?Result(JsonType) {
        const res = Or(i64)(negIntParser, posIntParser)(self, str);
        if (res) |r| {
            return Result(JsonType){ .result = JsonType{ .JsonInt = r.result }, .remain = r.remain };
        }
        return null;
    }

    fn sepBy(comptime elT: type, comptime sepT: type) Composer(elT, sepT, ArrayList(elT)) {
        return struct {
            pub fn f(comptime elp: Parser(elT), comptime sepp: Parser(sepT)) Parser(ArrayList(elT)) {
                return struct {
                    pub fn r(self: *Json, str: [*:0]const u8) ?Result(ArrayList(elT)) {
                        const elp_space = genRightSpaceParser(elT)(elp);
                        var res = elp_space(self, str);
                        var s = str;
                        if (res) |_| {
                            var li = ArrayList(elT).init(self.allocator);
                            while (res) |re| {
                                li.append(re.result) catch unreachable;
                                s = re.remain;
                                res = right(sepT, elT)(genRightSpaceParser(sepT)(sepp), elp_space)(self, s);
                            }
                            return Result(ArrayList(elT)){ .result = li, .remain = s };
                        }
                        return null;
                    }
                }.r;
            }
        }.f;
    }

    fn emptiable(comptime T: type) fn (Parser(ArrayList(T))) Parser(ArrayList(T)) {
        return struct {
            pub fn f(comptime p: Parser(ArrayList(T))) Parser(ArrayList(T)) {
                return struct {
                    pub fn r(self: *Json, str: [*:0]const u8) ?Result(ArrayList(T)) {
                        if (p(self, str)) |res| {
                            return res;
                        }
                        return Result(ArrayList(T)){ .result = ArrayList(T).init(self.allocator), .remain = str };
                    }
                }.r;
            }
        }.f;
    }

    fn spaceParser(self: *Json, str: [*:0]const u8) ?Result(ArrayList(u8)) {
        const cp = genCharParser;
        const orc = Or(u8);
        const p = orc(orc(orc(cp(' '), cp('\r')), cp('\n')), cp('\t'));

        return emptiable(u8)(all(u8)(p))(self, str);
    }

    fn genRightSpaceParser(comptime T: type) fn (p: Parser(T)) Parser(T) {
        return struct {
            pub fn f(comptime p: Parser(T)) Parser(T) {
                return left(T, ArrayList(u8))(p, spaceParser);
            }
        }.f;
    }

    fn genLeftSpaceParser(comptime T: type) fn (p: Parser(T)) Parser(T) {
        return struct {
            pub fn f(comptime p: Parser(T)) Parser(T) {
                return right(ArrayList(u8), T)(spaceParser, p);
            }
        }.f;
    }

    pub fn JarrayParser(self: *Json, str: [*:0]const u8) ?Result(JsonType) {
        const sep = sepBy(JsonType, u8)(JsonParser, genCharParser(','));
        const left_brac = genRightSpaceParser(u8)(genCharParser('['));
        const right_brac = genRightSpaceParser(u8)(genCharParser(']'));
        const arr = right(u8, ArrayList(JsonType))(left_brac, left(ArrayList(JsonType), u8)(emptiable(JsonType)(sep), right_brac));
        const res = arr(self, str);
        if (res) |r| {
            return Result(JsonType){ .result = JsonType{ .JsonArray = r.result }, .remain = r.remain };
        }
        return null;
    }

    fn kvParser(comptime kp: Parser(JsonType), comptime sp: Parser(u8), comptime vp: Parser(JsonType)) Parser(Pair(JsonType, JsonType)) {
        return struct {
            pub fn f(self: *Json, str: [*:0]const u8) ?Result(Pair(JsonType, JsonType)) {
                const k_result = genRightSpaceParser(JsonType)(kp)(self, str);
                if (k_result) |kr| {
                    const s_result = genRightSpaceParser(u8)(sp)(self, kr.remain);
                    if (s_result) |sr| {
                        const v_result = genRightSpaceParser(JsonType)(vp)(self, sr.remain);
                        if (v_result) |vr| {
                            return Result(Pair(JsonType, JsonType)){ .result = Pair(JsonType, JsonType){ .first = kr.result, .second = vr.result }, .remain = vr.remain };
                        }
                    }
                }
                return null;
            }
        }.f;
    }

    pub fn JobjectParser(self: *Json, str: [*:0]const u8) ?Result(JsonType) {
        const JJ = Pair(JsonType, JsonType);
        const left_brac = genRightSpaceParser(u8)(genCharParser('{'));
        const right_brac = genRightSpaceParser(u8)(genCharParser('}'));
        const kvp = kvParser(JstringParser, genCharParser(':'), JsonParser);
        const sep = sepBy(Pair(JsonType, JsonType), u8)(kvp, genCharParser(','));
        const objp = right(u8, ArrayList(JJ))(left_brac, left(ArrayList(JJ), u8)(emptiable(JJ)(sep), right_brac));
        const res = objp(self, str);
        if (res) |r| {
            return Result(JsonType){ .result = JsonType{ .JsonObject = r.result }, .remain = r.remain };
        }
        return null;
    }

    fn genCharParser(comptime char: u8) Parser(u8) {
        return struct {
            const c = char;
            pub fn f(self: *Json, str: [*:0]const u8) ?Result(u8) {
                _ = self;
                if (str[0] == 0) return null;
                if (str[0] == c) return Result(u8){ .result = c, .remain = str + 1 };
                return null;
            }
        }.f;
    }

    fn all(comptime T: type) fn (comptime p: Parser(T)) Parser(ArrayList(T)) {
        return struct {
            pub fn f(comptime p: Parser(T)) Parser(ArrayList(T)) {
                return struct {
                    pub fn r(self: *Json, str: [*:0]const u8) ?Result(ArrayList(T)) {
                        var li = ArrayList(T).init(self.allocator);
                        var res = p(self, str);
                        var s = str;
                        if (res == null) return null;
                        while (res) |re| {
                            li.append(re.result) catch unreachable;
                            s = re.remain;
                            res = p(self, s);
                        }
                        return Result(ArrayList(T)){ .result = li, .remain = s };
                    }
                }.r;
            }
        }.f;
    }

    fn stringParser(self: *Json, str: [*:0]const u8) ?Result(ArrayList(u8)) {
        const cp = struct {
            pub fn f(self2: *Json, str2: [*:0]const u8) ?Result(u8) {
                _ = self2;
                if (str2[0] == 0) return null;
                if (str2[0] == '"') return null;
                return Result(u8){ .result = str2[0], .remain = str2 + 1 };
            }
        }.f;
        return all(u8)(cp)(self, str);
    }

    pub fn JstringParser(self: *Json, str: [*:0]const u8) ?Result(JsonType) {
        const strp = left(ArrayList(u8), u8)(right(u8, ArrayList(u8))(genCharParser('"'), stringParser), genCharParser('"'));
        const res = strp(self, str);
        if (res) |r| {
            return Result(JsonType){ .result = JsonType{ .JsonString = r.result }, .remain = r.remain };
        }
        return null;
    }

    pub const JsonParser = genLeftSpaceParser(JsonType)(orj(orj(orj(orj(orj(JboolParser, orj(JFloatParser, JIntParser)), JarrayParser), JstringParser), JobjectParser), JNullParser));
};
// export fn JsonWrapper(str: [*:0]const u8) callconv(.C) ?*Result(JsonType) {
//     _ = str;
//     return null;
// }

var jp = Json.init(allocator);
pub fn main() !void {
    const args = try process.argsAlloc(allocator);
    if (args.len == 1) {
        std.debug.print("no input file\n", .{});
        return;
    }
    const file = std.fs.cwd().openFile(args[1], .{}) catch {
        std.debug.print("file {s} does not exit\n", .{args[1]});
        unreachable;
    };

    defer file.close();
    var buff: [1024 * 1024 * 10:0]u8 = undefined;
    var ptr: [*:0]const u8 = &buff;

    const bytes = try file.readAll(&buff);

    std.debug.print("bytes read {}\n", .{bytes});
    const start_t = std.time.milliTimestamp();
    const r1 = jp.JsonParser(ptr);
    const end_t = std.time.milliTimestamp();

    if (r1) |r| {
        std.debug.print("\n{s}\n", .{r.result});
    } else {
        std.debug.print("null\n", .{});
    }
    std.debug.print("time taken to parse: {}ms\n", .{end_t - start_t});
}

// test "Space Parser" {
//     const r1 = jp.spaceParser("aaa");
//     if (r1) |r| {
//         std.debug.print("\nresult: [{s}]\nremain:[{s}]\n", .{ r.result.items, r.remain });
//     } else {
//         std.debug.print("null\n", .{});
//     }
//     const r2 = (genRightSpaceParser(JsonType)(JboolParser))("true");
//     if (r2) |r| {
//         std.debug.print("\nresult: [{s}]\nremain:[{s}]\n", .{ r.result, r.remain });
//     } else {
//         std.debug.print("null\n", .{});
//     }
// }

test "String Parser" {
    const r1 = jp.JstringParser("\"this is correct\"");
    if (r1) |r| {
        std.debug.print("\nresult: [{s}]\nremain:[{s}]\n", .{ r.result, r.remain });
    } else {
        std.debug.print("null\n", .{});
    }

    const r2 = jp.JstringParser("\"this is wrong");
    if (r2) |r| {
        std.debug.print("\nresult: [{s}]\nremain:[{s}]\n", .{ r.result, r.remain });
    } else {
        std.debug.print("null\n", .{});
    }
}

test "Object Parser" {
    const r1 = jp.JobjectParser("{112:true}");
    if (r1) |r| {
        std.debug.print("\nresult: [{s}]\nremain:[{s}]\n", .{ r.result, r.remain });
    } else {
        std.debug.print("null\n", .{});
    }

    const r2 = jp.JobjectParser("{112: true, \n\"key\": [false], \n\"obj\": {}}");
    if (r2) |r| {
        std.debug.print("\nresult: [{s}]\nremain:[{s}]\n", .{ r.result, r.remain });
    } else {
        std.debug.print("null\n", .{});
    }
}

test "Array Parser" {
    const r1 = jp.spaceParser("[   11    ,  22,true,[]]");
    if (r1) |r| {
        std.debug.print("\nresult: [{s}]\nremain:[{s}]\n", .{ r.result.items, r.remain });
    } else {
        std.debug.print("null\n", .{});
    }
}

test "Float Parser" {
    const r1 = jp.JsonParser("-1111223.5");
    if (r1) |r| {
        std.debug.print("\nresult: [{s}]\nremain:[{s}]\n", .{ r.result, r.remain });
    } else {
        std.debug.print("null\n", .{});
    }
}
