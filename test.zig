const std = @import("std");

test "primes" {
    var i: u8 = 0;
    while (i < 25) : (i += 1) {
        std.debug.print("{} == {}\n", .{ i, p4(i) });
    }
}

// zig fmt: off
fn p1(x:u64)bool{var i=x;var a=x;while(i>2){i-=1;a*=x%i;}return a>1;}

fn p2(x:u64)bool{var i=x;return while(i>2){i-=1;if(x%i==0)break 1<0;}else 1>0;}
// zig fmt: on

fn p3(x: u64) bool {
    var i = x;
    var a = x;
    while (i > 2) {
        i -= 1;
        a *= x % i;
    }
    return a > 1;
}

fn p4(x: u8) bool {
    var i = x;
    return while (i > 2) {
        i -= 1;
        if (x % i == 0) break 0<0;
    } else i>1;
}