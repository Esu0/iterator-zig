const std = @import("std");
const testing = std.testing;

pub fn main() !void {
    std.debug.print("\n", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) testing.expect(false) catch @panic("TEST FAIL");
    }
    var map = std.AutoHashMap(u32, u64).init(allocator);
    defer map.deinit();

    try map.put(3, 5);
    try map.put(4, 8);
    try map.put(9, 0);
    try map.put(7, 2);
    try map.put(8, 2);

    const Functions = struct {
        fn double(x: u32) u32 {
            return x * 2;
        }

        fn to_u64(x: u32) u64 {
            return x;
        }

        fn is_even(x: *const u32) bool {
            return (x.* % 2) == 0;
        }

        fn is_odd(x: *const u32) bool {
            return (x.* % 2) == 1;
        }

        fn add(x: u64, y: u64) u64 {
            return x + y;
        }
    };
    var iterator = into_iterator(map.keyIterator())
        .copied()
        .filter(Functions.is_odd)
        .map(Functions.double).enumerate();

    while (iterator.next()) |item| {
        std.debug.print("index: {}, value: {}\n", .{ item.index, item.item });
        try testing.expect(@TypeOf(item.index) == usize);
    }

    const sum = into_iterator(map.valueIterator())
        .copied()
        .fold(@as(u64, 0), Functions.add);
    std.debug.print("sum: {}\n", .{ sum });
}

/// InnerTとTに関係性は必要ない
fn IteratorType(comptime T: type, comptime InnerT: type, comptime next_fn: fn (*InnerT) ?T) type {
    return struct {
        const Self = @This();
        pub const Item = T;
        inner: InnerT,

        pub fn next(self: *Self) ?T {
            return next_fn(&self.inner);
        }

        pub fn init(inner: InnerT) Self {
            return Self{ .inner = inner };
        }

        pub fn map(self: Self, comptime f: anytype) Map(
            Self,
            T,
            FnCheck(@TypeOf(f), 1, [_]type{T}),
            f,
        ) {
            return Map(Self, T, FnCheck(@TypeOf(f), 1, [_]type{T}), f).init(self);
        }

        pub fn copied(self: Self) Copied(Self, T) {
            return Copied(Self, T).init(self);
        }

        pub fn filter(self: Self, comptime f: fn (*const T) bool) Filter(Self, T, f) {
            return Filter(Self, T, f).init(self);
        }

        pub fn enumerate(self: Self) Enumerate(Self, T) {
            return Enumerate(Self, T).init(EnumerateInner(Self, T).init(self));
        }

        pub fn fold(
            self: Self,
            initial: anytype,
            comptime f: fn (@TypeOf(initial), T) @TypeOf(initial)
        ) @TypeOf(initial) {
            var result = initial;
            var iterator = self;
            while (iterator.next()) |item| {
                result = f(result, item);
            }
            return result;
        }

        // TODO implement take
        pub fn take(self: Self, count: usize) Take(Self, T) {
            _ = self;
            _ = count;
            @compileError("Take not implemented");
        }

        // TODO implement take_while
        pub fn take_while(self: Self, comptime f: fn (*const T) bool) TakeWhile(Self, T, f) {
            _ = self;
            @compileError("TakeWhile not implemented");
        }

        //TODO implement skip
        //TODO implement skip_while
        //TODO implement chain
        //TODO implement zip
        //TODO implement inspect
        //TODO implement for_each
        //TODO implement find
        //TODO implement count
        //TODO implement collect
    };
}

pub fn Iterator(comptime InnerT: type) type {
    if (!@hasDecl(InnerT, "next")) {
        @compileError(@typeName(InnerT) ++ "はメソッドnextを持っていません");
    }
    const T = comptime switch (@typeInfo(@TypeOf(InnerT.next))) {
        .Fn => |fn_info| if (fn_info.params.len == 1 and fn_info.params[0].type == *InnerT)
            if (fn_info.return_type) |return_type|
                switch (@typeInfo(return_type)) {
                    .Optional => |optional| optional.child,
                    else => @compileError(@typeName(InnerT) ++ "のメソッドnextの定義が異なります"),
                }
            else
                @compileError(@typeName(InnerT) ++ "のメソッドnextの定義が異なります")
        else
            @compileError(@typeName(InnerT) ++ "のメソッドnextの定義が異なります"),
        else => unreachable,
    };
    const next_fn: fn (*InnerT) ?T = InnerT.next;
    return IteratorType(T, InnerT, next_fn);
}

fn FnCheck(comptime F: type, comptime param_len: comptime_int, comptime params: [param_len]type) type {
    switch (@typeInfo(F)) {
        .Fn => |fn_info| if (fn_info.params.len == params.len) {
            for (params, fn_info.params) |param, fn_param| {
                if (param != fn_param.type) {
                    @compileError("引数の型が異なります");
                }
            }
            return fn_info.return_type.?;
        } else @compileError("引数の数が異なります"),
        else => @compileError("関数型ではありません"),
    }
}

fn Map(comptime I: type, comptime ItemTOld: type, comptime ItemTNew: type, comptime f: fn (ItemTOld) ItemTNew) type {
    const Tmp = struct {
        fn next(self: *I) ?ItemTNew {
            const next_item: ?ItemTOld = self.next();
            if (next_item) |item| {
                return f(item);
            } else {
                return null;
            }
        }
    };
    return IteratorType(ItemTNew, I, Tmp.next);
}

fn Copied(comptime I: type, comptime ItemT: type) type {
    const ItemTNew = switch (@typeInfo(ItemT)) {
        .Pointer => |pointer_info| pointer_info.child,
        else => @compileError("Itemはポインタ型である必要があります"),
    };
    const Tmp = struct {
        fn next(self: *I) ?ItemTNew {
            const next_item: ?ItemT = self.next();
            if (next_item) |item| {
                return item.*;
            } else return null;
        }
    };
    return IteratorType(ItemTNew, I, Tmp.next);
}

fn Filter(comptime I: type, comptime ItemT: type, comptime f: fn (*const ItemT) bool) type {
    const Tmp = struct {
        fn next(self: *I) ?ItemT {
            return while (self.next()) |item| {
                if (f(&item)) {
                    return item;
                }
            } else return null;
        }
    };
    return IteratorType(ItemT, I, Tmp.next);
}

fn EnumerateInner(comptime I: type, comptime ItemT: type) type {
    return struct {
        const Self = @This();
        const Item = struct {
            index: usize,
            item: ItemT,
        };
        inner: I,
        index: usize,
        fn next(self: *Self) ?Item {
            const next_item: ?ItemT = self.inner.next();
            if (next_item) |item| {
                defer self.index += 1;
                return Item{
                    .index = self.index,
                    .item = item,
                };
            } else {
                return null;
            }
        }

        fn init(inner: I) Self {
            return Self{
                .inner = inner,
                .index = 0,
            };
        }
    };
}

fn Enumerate(comptime I: type, comptime ItemT: type) type {
    const InnerT = EnumerateInner(I, ItemT);
    return IteratorType(InnerT.Item, InnerT, InnerT.next);
}


// TODO implement take
fn Take(comptime I: type, comptime ItemT: type) type {
    _ = I;
    _ = ItemT;
    @compileError("Take not implemented");
}

// TODO implement take_while
fn TakeWhile(comptime I: type, comptime ItemT: type, comptime f: fn (*const ItemT) bool) type {
    _ = I;
    _ = f;
    @compileError("TakeWhile not implemented");
}
/// # Requirements
/// * `inner`の型が`next`メソッドを持っており、そのメソッドの引数が自身の型のポインタで、戻り値が`Optional`であること
pub fn into_iterator(inner: anytype) Iterator(@TypeOf(inner)) {
    return Iterator(@TypeOf(inner)).init(inner);
}

test "anytype function" {
    const Functions = struct {
        fn call(comptime f: fn (anytype) i32, arg: anytype) i32 {
            return f(arg);
        }
    };

    _ = Functions;
}
