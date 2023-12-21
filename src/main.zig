const std = @import("std");
const testing = std.testing;

fn IteratorType(comptime T: type, comptime InnerT: type, comptime next_fn: fn(*InnerT)?T) type {
    return struct {
        const Self = @This();
        const Item = T;
        inner: InnerT,

        fn next(self: *Self) ?T {
            return next_fn(&self.inner);
        }
    };
}

fn Iterator(comptime InnerT: type) type {
    if (!@hasDecl(InnerT, "next")) {
        @compileError(@typeName(InnerT) ++ "はメソッドnextを持っていません");
    }
    const T = comptime switch (@typeInfo(InnerT.next)) {
        .Fn => |fn_info| if (fn_info.params.len == 1 and fn_info.params[0] == *InnerT)
            switch (@typeInfo(fn_info.return_type)) {
                .Optional => |optional| optional.child,
                else => @compileError(@typeName(InnerT) ++ "のメソッドnextの定義が異なります"),
            }
        else @compileError(@typeName(InnerT) ++ "のメソッドnextの定義が異なります"),
        else => unreachable,
    };
    const next_fn: fn(*InnerT)?T = InnerT.next;
    return IteratorType(T, InnerT, next_fn);
}