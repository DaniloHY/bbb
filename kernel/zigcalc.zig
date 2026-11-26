
const ERANGE: i32 = -34;
const EDOM: i32 = -33;
const EINVAL: i32 = -22;

// Identificadores das operações
pub const OP_SOMA: u32 = 1;
pub const OP_SUB: u32 = 2;
pub const OP_MULT: u32 = 3;
pub const OP_DIV: u32 = 4;

// Executa a operação solicitada.
//
// Retorno:
//   0       = sucesso
//  -33      = divisão por zero
//  -34      = transbordamento
//  -22      = operação inválida
//
pub export fn zig_calcular(
    operacao: u32,
    a: i32,
    b: i32,
    resultado: *i32,
) callconv(.c) i32 {

    switch (operacao) {
        OP_SOMA => {
            const calculo = @addWithOverflow(a, b);

            if (calculo[1] != 0) {
                return ERANGE;
            }

            resultado.* = calculo[0];
        },

        OP_SUB => {
            const calculo = @subWithOverflow(a, b);

            if (calculo[1] != 0) {
                return ERANGE;
            }

            resultado.* = calculo[0];
        },

        OP_MULT => {
            const calculo = @mulWithOverflow(a, b);

            if (calculo[1] != 0) {
                return ERANGE;
            }

            resultado.* = calculo[0];
        },

        OP_DIV => {
            if (b == 0) {
                return EDOM;
            }

            // O menor i32 dividido por -1
            // não pode ser representado em i32.
            if (a == -2147483648 and b == -1) {
                return ERANGE;
            }

            resultado.* = @divTrunc(a, b);
        },

        else => {
            return EINVAL;
        },
    }

    return 0;
}
