#!/bin/sh
# tests/test.sh - testes automatizados do zig-kernel-ioctl
#
# Executar como root, na VM do Alpine, a partir de qualquer diretorio:
#     sh tests/test.sh
#
# Pre-requisitos: modulo (kernel/zigcalc.ko) e cliente (./zigcalc) compilados
# (make). O script tenta rodar "make" sozinho se algo estiver faltando.
#
# Saidas (evidencias) em docs/evidencias/:
#     test-run.log      log completo desta execucao
#     modinfo.txt       saida de modinfo
#     lsmod.txt         saida de lsmod
#     strace.txt        saida do strace do cliente
#     dmesg-antes.txt   dmesg antes dos testes (copia de seguranca)
#     dmesg-depois.txt  dmesg gerado pelos testes
#
# Codigo de saida: 0 = todos os testes passaram; 1 = algum falhou.

ROOT=$(cd "$(dirname "$0")/.." && pwd)
EVID="$ROOT/docs/evidencias"
mkdir -p "$EVID"

# Reexecuta a si mesmo gravando tudo (tela + arquivo). O sh nao tem
# "set -o pipefail", entao o status final vai para um arquivo.
if [ -z "$ZIGCALC_TEST_INNER" ]; then
    rm -f "$EVID/.status"
    ZIGCALC_TEST_INNER=1 sh "$0" "$@" 2>&1 | tee "$EVID/test-run.log"
    [ "$(cat "$EVID/.status" 2>/dev/null)" = "0" ]
    exit $?
fi

KO="$ROOT/kernel/zigcalc.ko"
CLI="$ROOT/zigcalc"
DEV=/dev/zigcalc
WORKERS=${WORKERS:-8}      # clientes simultaneos
ITER=${ITER:-25}           # iteracoes por cliente (4 operacoes cada)

PASS=0
FAIL=0

ok()  { PASS=$((PASS + 1)); echo "[ OK ] $1"; }
bad() { FAIL=$((FAIL + 1)); echo "[FALHA] $1"; [ -n "$2" ] && echo "         $2"; }
secao() { echo; echo "=== $1 ==="; }
finish() {
    echo
    echo "=============================================="
    echo " RESULTADO: $PASS testes passaram, $FAIL falharam"
    echo "=============================================="
    [ "$FAIL" -eq 0 ] && echo 0 > "$EVID/.status" || echo 1 > "$EVID/.status"
    [ "$FAIL" -eq 0 ]
    exit $?
}

# check "descricao" esperado obtido
check() {
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "esperado: [$2]  obtido: [$3]"; fi
}

# expect "descricao" codigo_saida_esperado "saida esperada" argumentos...
expect() {
    desc=$1; erc=$2; eout=$3; shift 3
    out=$("$CLI" "$@" 2>&1); rc=$?
    if [ "$rc" = "$erc" ] && [ "$out" = "$eout" ]; then
        ok "$desc  ->  $out"
    else
        bad "$desc" "esperado: rc=$erc [$eout]  obtido: rc=$rc [$out]"
    fi
}

echo "zig-kernel-ioctl - testes   ($(date))"
echo "kernel: $(uname -r)    zig: $(zig version 2>/dev/null || echo 'nao encontrado')"

# ---------------------------------------------------------------- preparacao
secao "Preparacao"

if [ "$(id -u)" != "0" ]; then
    echo "ERRO: execute como root (insmod/rmmod exigem privilegios)."
    echo 1 > "$EVID/.status"; exit 1
fi

if [ ! -f "$KO" ] || [ ! -x "$CLI" ]; then
    echo "Artefatos ausentes; executando make..."
    (cd "$ROOT" && make) || { echo "ERRO: make falhou"; echo 1 > "$EVID/.status"; exit 1; }
fi
[ -f "$KO" ]  && ok "kernel/zigcalc.ko existe"  || bad "kernel/zigcalc.ko nao existe"
[ -x "$CLI" ] && ok "cliente ./zigcalc existe"  || bad "cliente ./zigcalc nao existe"
[ "$FAIL" -ne 0 ] && finish

# Garante estado limpo
if lsmod | grep -q '^zigcalc '; then
    echo "Modulo ja carregado; removendo antes de iniciar..."
    rmmod zigcalc || { bad "nao foi possivel remover modulo anterior"; finish; }
fi

dmesg > "$EVID/dmesg-antes.txt" 2>&1
dmesg -c > /dev/null 2>&1   # limpa o buffer: so veremos mensagens desta execucao

# ------------------------------------------------------------ carregamento
secao "Carregamento do modulo"

insmod "$KO"; rc=$?
check "insmod ./zigcalc.ko" 0 "$rc"
[ "$rc" -ne 0 ] && { dmesg | tail -n 20; finish; }

lsmod > "$EVID/lsmod.txt"
if lsmod | grep -q '^zigcalc '; then
    ok "lsmod lista o modulo: $(lsmod | grep '^zigcalc ')"
else
    bad "lsmod nao lista o modulo"
fi

modinfo "$KO" > "$EVID/modinfo.txt" 2>&1
if grep -q '^license:.*GPL' "$EVID/modinfo.txt" && grep -q '^description:' "$EVID/modinfo.txt"; then
    ok "modinfo responde com license e description"
else
    bad "modinfo incompleto (ver docs/evidencias/modinfo.txt)"
fi

# O /dev/zigcalc e criado por device_create() + mdev/devtmpfs; aguarda um pouco.
i=0
while [ ! -e "$DEV" ] && [ $i -lt 30 ]; do sleep 0.1 2>/dev/null || sleep 1; i=$((i + 1)); done
if [ ! -e "$DEV" ] && [ -r /sys/class/zigcalc/zigcalc/dev ]; then
    # Plano B: cria o no manualmente a partir de major:minor expostos no sysfs.
    MM=$(cat /sys/class/zigcalc/zigcalc/dev)
    echo "AVISO: /dev/zigcalc nao foi criado automaticamente; criando com mknod ($MM)"
    mknod "$DEV" c "${MM%%:*}" "${MM##*:}" && chmod 666 "$DEV"
fi
if [ -c "$DEV" ]; then
    ok "dispositivo de caractere disponivel: $(ls -l "$DEV")"
else
    bad "/dev/zigcalc nao existe como dispositivo de caractere"
    finish
fi
grep zigcalc /proc/devices | sed 's/^/         \/proc\/devices: /'

# ------------------------------------------------------------ operacoes
secao "Operacoes aritmeticas (executadas no kernel)"
expect "soma 10 20"            0 "Resultado: 30"   soma 10 20
expect "sub 50 15"             0 "Resultado: 35"   sub 50 15
expect "mult 7 8"              0 "Resultado: 56"   mult 7 8
expect "div 100 4"             0 "Resultado: 25"   div 100 4
expect "soma com negativos"    0 "Resultado: -2"   soma -5 3
expect "sub resultando negativo" 0 "Resultado: -10" sub 5 15
expect "mult com negativo"     0 "Resultado: -56"  mult -7 8
expect "div trunca p/ zero (7/2)"   0 "Resultado: 3"  div 7 2
expect "div trunca p/ zero (-7/2)"  0 "Resultado: -3" div -7 2
expect "limite superior sem overflow" 0 "Resultado: 2147483647" soma 2147483646 1
expect "limite inferior sem overflow" 0 "Resultado: -2147483648" sub -2147483647 1
expect "INT_MIN / 1"           0 "Resultado: -2147483648" div -2147483648 1

secao "Tratamento de erros (contrato: EDOM, ERANGE, ENOTTY, EFAULT)"
expect "divisao por zero (EDOM)"        1 "Erro: divisão por zero" div 10 0
expect "0 / 0 (EDOM)"                   1 "Erro: divisão por zero" div 0 0
expect "soma com overflow (ERANGE)"     1 "Erro: transbordamento aritmético" soma 2147483647 1
expect "soma com underflow (ERANGE)"    1 "Erro: transbordamento aritmético" soma -2147483648 -1
expect "sub com overflow (ERANGE)"      1 "Erro: transbordamento aritmético" sub -2147483648 1
expect "mult com overflow (ERANGE)"     1 "Erro: transbordamento aritmético" mult 65536 65536
expect "INT_MIN / -1 (ERANGE)"          1 "Erro: transbordamento aritmético" div -2147483648 -1
expect "comando desconhecido (ENOTTY)"  1 "Erro: comando ioctl desconhecido (ENOTTY)" ioctl-invalido
expect "ponteiro invalido (EFAULT)"     1 "Erro: ponteiro de usuário inválido (EFAULT)" ponteiro-invalido

secao "Validacao no cliente (entradas invalidas)"
out=$("$CLI" soma abc 1 2>&1); rc=$?
check "operando nao numerico -> codigo 2" 2 "$rc"
out=$("$CLI" soma 2147483648 1 2>&1); rc=$?
check "operando fora de 32 bits -> codigo 2" 2 "$rc"
out=$("$CLI" 2>&1); rc=$?
check "sem argumentos -> uso (codigo 2)" 2 "$rc"
out=$("$CLI" potencia 2 3 2>&1); rc=$?
check "operacao inexistente -> codigo 2" 2 "$rc"

# ------------------------------------------------------------------ strace
secao "Investigacao com strace"
if command -v strace > /dev/null 2>&1; then
    strace -e trace=openat,ioctl,close -o "$EVID/strace.txt" "$CLI" soma 10 20 > /dev/null 2>&1
    if grep -q 'openat(.*"/dev/zigcalc"' "$EVID/strace.txt"; then ok "strace mostra openat de /dev/zigcalc"; else bad "strace sem openat de /dev/zigcalc"; fi
    if grep -q 'ioctl(' "$EVID/strace.txt"; then ok "strace mostra a chamada ioctl"; else bad "strace sem ioctl"; fi
    if grep -q 'close(' "$EVID/strace.txt"; then ok "strace mostra close do descritor"; else bad "strace sem close"; fi
    if grep -qi 'zig_soma\|zig_calcular' "$EVID/strace.txt"; then
        bad "strace nao deveria mostrar funcoes Zig (so syscalls)"
    else
        ok "nenhuma 'syscall zig_*' aparece: a funcao Zig e alcancada via ioctl"
    fi
    sed 's/^/         strace: /' "$EVID/strace.txt"
else
    bad "strace nao instalado (apk add strace)"
fi

# -------------------------------------------------------------- concorrencia
secao "Execucao simultanea de clientes ($WORKERS clientes x $ITER iteracoes x 4 operacoes)"
TMP=$(mktemp -d)
worker() {
    k=$1; i=1
    while [ "$i" -le "$ITER" ]; do
        p=$((k * i))
        [ "$("$CLI" soma "$k" "$i" 2>&1)" = "Resultado: $((k + i))" ] || echo "soma $k $i" >> "$TMP/w$k.fail"
        [ "$("$CLI" sub  "$i" "$k" 2>&1)" = "Resultado: $((i - k))" ] || echo "sub $i $k"  >> "$TMP/w$k.fail"
        [ "$("$CLI" mult "$k" "$i" 2>&1)" = "Resultado: $p" ]         || echo "mult $k $i" >> "$TMP/w$k.fail"
        [ "$("$CLI" div  "$p" "$k" 2>&1)" = "Resultado: $i" ]         || echo "div $p $k"  >> "$TMP/w$k.fail"
        i=$((i + 1))
    done
}
k=1
while [ "$k" -le "$WORKERS" ]; do worker "$k" & k=$((k + 1)); done
wait
FALHAS=$(cat "$TMP"/w*.fail 2>/dev/null | wc -l)
check "todos os resultados corretos sob concorrencia ($((WORKERS * ITER * 4)) chamadas)" 0 "$FALHAS"
[ "$FALHAS" -ne 0 ] && head -n 10 "$TMP"/w*.fail
rm -rf "$TMP"

# --------------------------------------------------------------------- dmesg
secao "Verificacao do log do kernel (dmesg)"
dmesg > "$EVID/dmesg-depois.txt" 2>&1
grep -q 'zigcalc: inicializando modulo' "$EVID/dmesg-depois.txt" && ok "log de inicializacao presente" || bad "faltou log de inicializacao"
grep -q 'zigcalc: dispositivo /dev/zigcalc criado' "$EVID/dmesg-depois.txt" && ok "log de criacao do dispositivo presente" || bad "faltou log de criacao do dispositivo"
grep -q 'zigcalc: comando ioctl desconhecido' "$EVID/dmesg-depois.txt" && ok "ENOTTY registrado no log" || bad "ENOTTY nao registrado"
grep -q 'zigcalc: falha ao copiar dados do usuario' "$EVID/dmesg-depois.txt" && ok "EFAULT registrado no log" || bad "EFAULT nao registrado"
PROBLEMAS=$(grep -ciE 'BUG:|Oops|Call Trace|general protection|kernel panic|WARNING:|segfault|unable to handle' "$EVID/dmesg-depois.txt")
check "dmesg sem BUG/Oops/Call Trace/WARNING" 0 "$PROBLEMAS"
echo "--- dmesg | tail -n 30"
dmesg | tail -n 30

# ------------------------------------------------------------- descarregamento
secao "Descarregamento do modulo e liberacao de recursos"
rmmod zigcalc; rc=$?
check "rmmod zigcalc" 0 "$rc"
lsmod | grep -q '^zigcalc ' && bad "modulo ainda aparece no lsmod" || ok "modulo removido do lsmod"

i=0
while [ -e "$DEV" ] && [ $i -lt 30 ]; do sleep 0.1 2>/dev/null || sleep 1; i=$((i + 1)); done
[ -e "$DEV" ] && bad "/dev/zigcalc continua existindo apos rmmod" || ok "/dev/zigcalc removido"
[ -d /sys/class/zigcalc ] && bad "classe /sys/class/zigcalc nao foi destruida" || ok "classe do dispositivo destruida (device_destroy/class_destroy)"
grep -q zigcalc /proc/devices && bad "major ainda registrado em /proc/devices" || ok "major liberado (unregister_chrdev_region)"
dmesg | grep -q 'zigcalc: modulo removido' && ok "log de remocao presente" || bad "faltou log de remocao"

# Ciclo extra: se algum recurso vazou, o segundo insmod falharia.
insmod "$KO" && rmmod zigcalc && ok "segundo ciclo insmod/rmmod sem vazamento de recursos" || bad "segundo ciclo insmod/rmmod falhou"

PROBLEMAS=$(dmesg | grep -ciE 'BUG:|Oops|Call Trace|general protection|kernel panic|WARNING:|unable to handle')
check "dmesg final sem falhas" 0 "$PROBLEMAS"
dmesg >> "$EVID/dmesg-depois.txt" 2>&1

finish
