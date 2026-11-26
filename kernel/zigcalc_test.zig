// Testes unitarios das funcoes Zig, executados FORA do kernel:
//
//     zig test kernel/zigcalc_test.zig        (ou: make hosttest)
//
// Eles importam exatamente o mesmo arquivo que e compilado para dentro do
// zigcalc.ko, entao testam a logica real do modulo.

const std = @import("std");
const testing = std.testing;
const calc = @import("zigcalc.zig");

const MAX: i32 = std.math.maxInt(i32);
const MIN: i32 = std.math.minInt(i32);

const OK: i32 = 0;
const EDOM: i32 = -33;
const ERANGE: i32 = -34;
const EINVAL: i32 = -22;

const SENTINELA: i32 = 0x5a5a5a5a;

fn exec(op: u32, a: i32, b: i32, resultado: *i32) i32 {
    return calc.zig_calcular(op, a, b, resultado);
}

test "soma" {
    var r: i32 = SENTINELA;
    try testing.expectEqual(OK, exec(calc.OP_SOMA, 10, 20, &r));
    try testing.expectEqual(@as(i32, 30), r);
    try testing.expectEqual(OK, exec(calc.OP_SOMA, -5, 3, &r));
    try testing.expectEqual(@as(i32, -2), r);
    try testing.expectEqual(OK, exec(calc.OP_SOMA, MAX - 1, 1, &r));
    try testing.expectEqual(MAX, r);
}

test "soma com transbordamento" {
    var r: i32 = SENTINELA;
    try testing.expectEqual(ERANGE, exec(calc.OP_SOMA, MAX, 1, &r));
    try testing.expectEqual(ERANGE, exec(calc.OP_SOMA, MIN, -1, &r));
    try testing.expectEqual(SENTINELA, r); // resultado nao deve ser alterado em erro
}

test "subtracao" {
    var r: i32 = SENTINELA;
    try testing.expectEqual(OK, exec(calc.OP_SUB, 50, 15, &r));
    try testing.expectEqual(@as(i32, 35), r);
    try testing.expectEqual(OK, exec(calc.OP_SUB, 0, MAX, &r));
    try testing.expectEqual(-MAX, r);
}

test "subtracao com transbordamento" {
    var r: i32 = SENTINELA;
    try testing.expectEqual(ERANGE, exec(calc.OP_SUB, MIN, 1, &r));
    try testing.expectEqual(ERANGE, exec(calc.OP_SUB, MAX, -1, &r));
    try testing.expectEqual(ERANGE, exec(calc.OP_SUB, 0, MIN, &r));
    try testing.expectEqual(SENTINELA, r);
}

test "multiplicacao" {
    var r: i32 = SENTINELA;
    try testing.expectEqual(OK, exec(calc.OP_MULT, 7, 8, &r));
    try testing.expectEqual(@as(i32, 56), r);
    try testing.expectEqual(OK, exec(calc.OP_MULT, -7, 8, &r));
    try testing.expectEqual(@as(i32, -56), r);
    try testing.expectEqual(OK, exec(calc.OP_MULT, 0, MAX, &r));
    try testing.expectEqual(@as(i32, 0), r);
}

test "multiplicacao com transbordamento" {
    var r: i32 = SENTINELA;
    try testing.expectEqual(ERANGE, exec(calc.OP_MULT, MAX, 2, &r));
    try testing.expectEqual(ERANGE, exec(calc.OP_MULT, 65536, 65536, &r));
    try testing.expectEqual(ERANGE, exec(calc.OP_MULT, MIN, -1, &r));
    try testing.expectEqual(SENTINELA, r);
}

test "divisao" {
    var r: i32 = SENTINELA;
    try testing.expectEqual(OK, exec(calc.OP_DIV, 100, 4, &r));
    try testing.expectEqual(@as(i32, 25), r);
    // quociente inteiro, truncado em direcao a zero
    try testing.expectEqual(OK, exec(calc.OP_DIV, 7, 2, &r));
    try testing.expectEqual(@as(i32, 3), r);
    try testing.expectEqual(OK, exec(calc.OP_DIV, -7, 2, &r));
    try testing.expectEqual(@as(i32, -3), r);
    try testing.expectEqual(OK, exec(calc.OP_DIV, MIN, 1, &r));
    try testing.expectEqual(MIN, r);
}

test "divisao por zero" {
    var r: i32 = SENTINELA;
    try testing.expectEqual(EDOM, exec(calc.OP_DIV, 10, 0, &r));
    try testing.expectEqual(EDOM, exec(calc.OP_DIV, 0, 0, &r));
    try testing.expectEqual(SENTINELA, r);
}

test "divisao com transbordamento (INT_MIN / -1)" {
    var r: i32 = SENTINELA;
    try testing.expectEqual(ERANGE, exec(calc.OP_DIV, MIN, -1, &r));
    try testing.expectEqual(SENTINELA, r);
}

test "operacao invalida" {
    var r: i32 = SENTINELA;
    try testing.expectEqual(EINVAL, exec(0, 1, 2, &r));
    try testing.expectEqual(EINVAL, exec(5, 1, 2, &r));
    try testing.expectEqual(EINVAL, exec(0xffffffff, 1, 2, &r));
    try testing.expectEqual(SENTINELA, r);
}
