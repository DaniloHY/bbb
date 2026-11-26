#ifndef ZIGCALC_H
#define ZIGCALC_H

#include <linux/types.h>

/* Identificadores das operacoes (devem coincidir com OP_* em zigcalc.zig) */
#define ZIGCALC_OP_SOMA 1
#define ZIGCALC_OP_SUB  2
#define ZIGCALC_OP_MULT 3
#define ZIGCALC_OP_DIV  4

/*
 * Função implementada em Zig.
 *
 * Retorna:
 *  0   = sucesso
 * -33  = divisão por zero
 * -34  = overflow
 * -22  = operação inválida
 */
extern s32 zig_calcular(
    u32 operacao,
    s32 a,
    s32 b,
    s32 *resultado
);

#endif
