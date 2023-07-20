const std = @import("std");
const builtin = @import("builtin");
const process = std.process;

var buffer: [10000]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buffer);
const allocator = fba.allocator();
const ArrayList = std.ArrayList;

pub fn Pair(comptime T1: type, comptime T2: type) type {
    return struct {first: T1, second: T2};
}
const JsonType = union(enum) {
    JsonBool: bool,
    JsonNumber: i64,
    JsonNull: void,
    JsonArray: ArrayList(JsonType),
    JsonString: ArrayList(u8),
    JsonObject: ArrayList(Pair(JsonType, JsonType)),
    pub fn format(
        self: JsonType,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self) {
            .JsonBool => |val| try writer.print("JBool({})", .{val}),
            .JsonNumber => |val| try writer.print("JNumber({})", .{val}),
            .JsonNull => |val| {
                try writer.print("JNull", .{});
                _ = val;
            },
            .JsonArray => |val| {
                try writer.print("JArray([", .{});
                for (val.items, 0..) |j, i| {
                    try j.format(fmt, options, writer);
                    if (i < val.items.len - 1) try writer.print(", ", .{});
                }
                try writer.print("])", .{});
            },
            .JsonObject => |val| {
                try writer.print("JObject({{", .{});
                for (val.items, 0..) |j, i| {
                    try j.first.format(fmt, options, writer);
                    try writer.print(": ", .{});
                    try j.second.format(fmt, options, writer);
                    if (i < val.items.len - 1) try writer.print(", ", .{});
                }
                try writer.print("}})", .{});
            },
            .JsonString => |val| try writer.print("JString({s})", .{val.items}),
        }
        try writer.writeAll("");
    }

};

fn Result(comptime T: type) type {
    return struct {
        result: T,
        remain: []const u8 = "",
    };
}



fn Parser(comptime T: type) type {
    return fn (str: []const u8) ?Result(T);
}
fn Composer(comptime T1: type, comptime T2: type, comptime R: type) type {
    return fn (a: Parser(T1), b: Parser(T2)) Parser(R);
}
fn Or(comptime T1: type, comptime T2: type, comptime R: type) Composer(T1, T2, R) {
    return struct {
        pub fn f(comptime a: Parser(T1), comptime b: Parser(T2)) Parser(R) {
            return struct {
                pub fn r(str: []const u8) ?Result(R) {
                    if (a(str)) |res| {
                        return res;
                    }
                    return b(str);
                }
            }.r;
        }
    }.f;
}


fn left(comptime T1: type, comptime T2: type) Composer(T1, T2, T1) {
    return struct {
        pub fn f(comptime a: Parser(T1), comptime b: Parser(T2)) Parser(T1) {
            return struct {
                pub fn r(str: []const u8) ?Result(T1) {
                    if (a(str)) |res1| {
                        if (b(res1.remain)) |res2| {
                            return Result(T1) { .result = res1.result, .remain = res2.remain };
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
                pub fn r(str: []const u8) ?Result(T2) {
                    if (a(str)) |res| {
                        return b(res.remain);
                    }
                    return null;
                }
            }.r;
        }

    }.f;

}


pub fn nullParser(str: []const u8) ?Result(JsonType) {
    if (str.len < 4) return null;
    if (std.mem.eql(u8, str[0..4], "null")) {
        return Result(JsonType) { .result = JsonType{ .JsonNull = {} }, .remain = str[4..] };
    }
    return null;
}

const orj = Or(JsonType, JsonType, JsonType);

pub fn JtrueParser(str: []const u8) ?Result(JsonType) {
    if (str.len < 4) return null;
    if (std.mem.eql(u8, str[0..4], "true")) {
        return Result(JsonType) { .result = JsonType { .JsonBool = true}, .remain = str[4..] };
    }
    return null;
}
pub fn JfalseParser(str: []const u8) ?Result(JsonType) {
    if (str.len < 5) return null;
    if (std.mem.eql(u8, str[0..5], "false")) {
        return Result(JsonType) { .result = JsonType { .JsonBool = false }, .remain = str[5..] };
    }
    return null;
}

const JboolParser = orj(JfalseParser, JtrueParser);


fn positiveParser(str: []const u8) ?Result(i64) {
    const isNumber = struct {
        pub fn f(c: u8) bool {
            return c >= '0' and c <= '9';
        }
    }.f;
    var i: u32 = 0;
    for (str) |c| {
        if (!isNumber(c)) {
            break;
        }
        i += 1;
    }
    if (i == 0) return null;
    const num = std.fmt.parseInt(i64, str[0..i], 10) catch unreachable;
    return Result(i64) { .result = num, .remain = str[i..] };
}

fn negativeParser(str: []const u8) ?Result(i64) {
    const res = right(u8, i64)(genCharParser('-'), positiveParser)(str);
    if (res) |r| {
        return Result(i64){ .result = -r.result, .remain = r.remain };
    }
    return null;
}

fn JnumberParser(str: []const u8) ?Result(JsonType) {
    const res = Or(i64, i64, i64)(negativeParser, positiveParser)(str);
    if (res) |r| {
        return Result(JsonType) {.result= JsonType {.JsonNumber = r.result}, .remain = r.remain};
    }
    return null;
}

fn sepBy(comptime elT: type, comptime sepT: type) Composer(elT, sepT, ArrayList(elT)) {
    return struct {
        pub fn f(comptime elp: Parser(elT), comptime sepp: Parser(sepT)) Parser(ArrayList(elT)) {
            return struct {
                pub fn r(str: []const u8) ?Result(ArrayList(elT)) {
                    const elp_space = genRightSpaceParser(elT)(elp);
                    var res = elp_space(str);
                    var s = str;
                    if (res) |_| {
                        var li = ArrayList(elT).init(allocator);
                        while (res) |re| {
                            li.append(re.result) catch unreachable;
                            s = re.remain;
                            res = right(sepT, elT)(genRightSpaceParser(sepT)(sepp), elp_space)(s);
                        }
                        return Result(ArrayList(elT)) {.result = li, .remain = s};
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
                pub fn r(str: []const u8) ?Result(ArrayList(T)) {
                    if (p(str)) |res| {
                        return res;
                    }
                    return Result(ArrayList(T)) {.result = ArrayList(T).init(allocator), .remain = str};
                }
            }.r;
        }
    }.f;
}

fn spaceParser(str: []const u8) ?Result(ArrayList(u8)) {
    const cp = genCharParser;
    const orc = Or(u8, u8, u8);
    const p = orc(orc(orc(cp(' '), cp('\r')), cp('\n')), cp('\t'));

    return emptiable(u8)(all(u8)(p))(str);
}

fn genRightSpaceParser(comptime T: type) fn (p: Parser(T)) Parser(T) {
    return struct {
        pub fn f(comptime p: Parser(T)) Parser(T) {
            return left(T, ArrayList(u8))(p, spaceParser);
        }
    }.f;
}

fn JarrayParser(str: []const u8) ?Result(JsonType) {
    const sep = sepBy(JsonType, u8)(JsonParser,genCharParser(','));
    const left_brac = genRightSpaceParser(u8)(genCharParser('['));
    const right_brac = genRightSpaceParser(u8)(genCharParser(']'));
    const arr = right(u8, ArrayList(JsonType))(left_brac, left(ArrayList(JsonType), u8)(emptiable(JsonType)(sep), right_brac));
    const res = arr(str);
    if (res) |r| {
        return Result(JsonType) {.result = JsonType {.JsonArray = r.result}, .remain = r.remain};
    }
    return null;
}

fn kvParser(comptime kp: Parser(JsonType), comptime sp: Parser(u8), comptime vp: Parser(JsonType)) Parser(Pair(JsonType, JsonType)) {
    return struct {
        pub fn f(str: []const u8) ?Result(Pair(JsonType, JsonType)) {
            const k_result = genRightSpaceParser(JsonType)(kp)(str);
            if (k_result) |kr| {
                const s_result = genRightSpaceParser(u8)(sp)(kr.remain);
                if (s_result) |sr| {
                    const v_result = genRightSpaceParser(JsonType)(vp)(sr.remain);
                    if (v_result) |vr| {
                        return Result(Pair(JsonType, JsonType)) {
                            .result = Pair(JsonType, JsonType) {.first = kr.result, .second = vr.result}, 
                            .remain = vr.remain};
                    }
                }
            }
            return null;
        }
    }.f;
}

fn JobjectParser(str: []const u8) ?Result(JsonType) {
    const JJ = Pair(JsonType, JsonType);
    const left_brac = genRightSpaceParser(u8)(genCharParser('{'));
    const right_brac = genRightSpaceParser(u8)(genCharParser('}'));
    const kvp = kvParser(JsonParser, genCharParser(':'), JsonParser);
    const sep = sepBy(Pair(JsonType, JsonType), u8)(kvp , genCharParser(','));
    const objp = right(u8, ArrayList(JJ))(left_brac, left(ArrayList(JJ), u8)(emptiable(JJ)(sep), right_brac));
    const res = objp(str);
    if (res) |r| {
        return Result(JsonType) {.result = JsonType {.JsonObject = r.result}, .remain = r.remain};
    }
    return null;


}



fn genCharParser(comptime char: u8) Parser(u8) {
    return struct {
        const c = char;
        pub fn f(str: []const u8) ?Result(u8) {
            if (str.len == 0) return null;
            if (str[0] == c) return Result(u8) { .result = c, .remain = str[1..] };
            return null;
        }
    }.f;
}

fn all(comptime T: type) fn (comptime p: Parser(T))  Parser(ArrayList(T)) {
    return struct {
        pub fn f(comptime p: Parser(T)) Parser(ArrayList(T)) {
            return struct {
                pub fn r(str: []const u8) ?Result(ArrayList(T)) {
                    var li = ArrayList(T).init(allocator);
                    var res = p(str);
                    var s = str;
                    if (res == null) return null;
                    while (res) |re| {
                        li.append(re.result) catch unreachable;
                        s = re.remain;
                        res = p(s);
                    }
                    return Result(ArrayList(T)) {.result = li, .remain = s};
                }
            }.r;
        }
    }.f;
}

fn stringParser(str: []const u8) ?Result(ArrayList(u8)) {
    const cp = struct {
        pub fn f(str2: []const u8) ?Result(u8) {
            if (str2.len == 0) return null;
            if (str2[0] == '"') return null;
            return Result(u8) {.result = str2[0], .remain = str2[1..]};
        }
    }.f;
    return all(u8)(cp)(str);
}

fn JstringParser(str: []const u8) ?Result(JsonType) {
    const strp = left(ArrayList(u8), u8)(right(u8, ArrayList(u8))(genCharParser('"'), stringParser), genCharParser('"'));
    const res = strp(str);
    if (res) |r| {
        return Result(JsonType) {.result = JsonType {.JsonString = r.result}, .remain = r.remain};
    }
    return null;
}

// fn genSpanParser(comptime T: type, ps: ArrayList(Parser(T))) Parser(ArrayList(T)) {
//     return struct {
//         pub fn f(str: []const u8) ?Result(ArrayList(T)) {
//             var li = ArrayList(T).init(allocator);
//             var s = str;
//             for (ps, 0..) |item, i| {
//                 _ = i;
//                 const res = item(s);
//                 if (res) |r| {
//                     s = r.remain;
//                     li.append(r.result);
//                 } else {
//                     break;
//                 }
//             }
//             if (li.len == 0) {
//                 return null;
//             }
//             return Result(ArrayList(T)) { .result = li, .remain = s};
     
//         }
//     }.f;
// }

// fn genStringParser(comptime str: []const u8) Parser([]const u8) {
//     var ps = ArrayList(u8).init(allocator);
//     ps.appendSlice(str) catch unreachable;
//     return genSpanParser(u8, ps);
// }

const JsonParser = orj(orj(orj(orj(JboolParser, JnumberParser), JarrayParser), JstringParser), JobjectParser);

pub fn main() !void {
    const args = try process.argsAlloc(allocator);
    _ = args;
    // std.debug.print("Hello World\n", .{});


    const res = JsonParser("[   11    ,  22,true,[]]");
    if (res) |r| {
        std.debug.print("{}\n{s}\n", .{ r.result, r.remain });
    } else {
        std.debug.print("null\n", .{});
    }


}


test "Space Parser" {
    const r1 = spaceParser("aaa");
    if (r1) |r| {
        std.debug.print("\nresult: [{s}]\nremain:[{s}]\n", .{ r.result.items, r.remain });
    } else {
        std.debug.print("null\n", .{});
    }
    const r2 = (genRightSpaceParser(JsonType)(JboolParser))("true");
    if (r2) |r| {
        std.debug.print("\nresult: [{s}]\nremain:[{s}]\n", .{ r.result, r.remain });
    } else {
        std.debug.print("null\n", .{});
    }
    
}

test "String Parser" {
    const r1 = JstringParser("\"this is correct\"");
    if (r1) |r| {
        std.debug.print("\nresult: [{s}]\nremain:[{s}]\n", .{ r.result, r.remain });
    } else {
        std.debug.print("null\n", .{});
    }

    const r2 = JstringParser("\"this is wrong");
    if (r2) |r| {
        std.debug.print("\nresult: [{s}]\nremain:[{s}]\n", .{ r.result, r.remain });
    } else {
        std.debug.print("null\n", .{});
    }

    
}

test "Object Parser" {
    const r1 = JobjectParser("{112:true}");
    if (r1) |r| {
        std.debug.print("\nresult: [{s}]\nremain:[{s}]\n", .{ r.result, r.remain });
    } else {
        std.debug.print("null\n", .{});
    }

    const r2 = JobjectParser("{112: true, \n\"key\": [false], \n\"obj\": {}}");
    if (r2) |r| {
        std.debug.print("\nresult: [{s}]\nremain:[{s}]\n", .{ r.result, r.remain });
    } else {
        std.debug.print("null\n", .{});
    }



    
}
