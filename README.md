# zig-kernel-ioctl

Módulo carregável do kernel Linux (LKM) cujas operações matemáticas são
implementadas em **Zig 0.16.0**, exposto em `/dev/zigcalc` e acessado por um
cliente em Zig através da chamada de sistema **já existente** `ioctl(2)`
(nenhuma syscall nova é criada).

- Disciplina: Sistemas Operacionais
- Ambiente: Alpine Linux em VirtualBox (kernel `-virt`, x86_64)
- Linguagem: Zig **0.16.0** (+ camada mínima em C para as interfaces do kernel)

```
 espaço de usuário                           espaço de kernel
┌────────────────────┐   open/ioctl/close   ┌───────────────────────────────┐
│ ./zigcalc soma 1 2 │ ───────────────────▶ │ zigcalc_glue.c (C)            │
│  (client/main.zig) │   SYSCALL            │   .unlocked_ioctl             │
└────────────────────┘                      │   copy_from_user/copy_to_user │
                                            │            │                  │
                                            │            ▼                  │
                                            │ zigcalc.zig (Zig)             │
                                            │   zig_calcular()  +,-,*,/     │
                                            └───────────────────────────────┘
```

## Estrutura

```
zig-kernel-ioctl/
├── README.md
├── Makefile                  # make / module / client / hosttest / test / clean
├── kernel/
│   ├── zigcalc.zig           # operações em Zig (exportadas com ABI C)
│   ├── zigcalc_test.zig      # testes unitários do código Zig (fora do kernel)
│   ├── zigcalc_glue.c        # cdev + unlocked_ioctl + copy_*_user (camada C mínima)
│   ├── zigcalc.h             # protótipo de zig_calcular() para o C
│   ├── zigcalc_ioctl.h       # comandos _IOWR e struct compartilhada
│   └── Kbuild                # integra o .o do Zig ao zigcalc.ko
├── client/main.zig           # cliente em Zig 0.16.0
├── tests/test.sh             # testes automatizados (roda como root)
└── docs/
    ├── relatorio.pdf         # relatório técnico
    └── evidencias/           # logs gerados por tests/test.sh
```

## 1. Preparar o ambiente (Alpine, como root)

> **Antes de tudo: tire um snapshot da VM.** Código em espaço de kernel pode
> derrubar o sistema. Use somente a VM da atividade.

```sh
apk update
apk add build-base make kmod strace git
uname -r                      # ex.: 6.18.63-0-virt
apk add linux-virt-dev        # a variante precisa ser a do kernel em execução
                              # (se uname -r terminar em -lts: linux-lts-dev)
```

Os headers precisam corresponder **exatamente** ao kernel em execução:

```sh
ls -d /lib/modules/$(uname -r)/build      # deve existir
```

Instale o Zig **0.16.0** (binário estático, serve para Alpine/musl) baixando o
tarball `x86_64-linux` em <https://ziglang.org/download/> e colocando-o no PATH:

```sh
tar -xf zig-x86_64-linux-0.16.0.tar.xz
mv zig-x86_64-linux-0.16.0 /opt/zig
ln -s /opt/zig/zig /usr/local/bin/zig
zig version                   # DEVE imprimir exatamente: 0.16.0
```

Confira tudo de uma vez:

```sh
make check
```

## 2. Compilar o módulo

```sh
make module
```

Isso executa `make -C /lib/modules/$(uname -r)/build M=$PWD/kernel modules`.
O `kernel/Kbuild` roda `zig build-obj` para gerar `zigcalc_math.o` e o Kbuild
o **linka junto** com `zigcalc_glue.o`, produzindo `kernel/zigcalc.ko`.
Ao final, o `make` mostra os símbolos do objeto Zig (não deve haver `U`) e a
contagem de instruções SSE/AVX (deve ser `0`; o kernel não salva estado de
ponto flutuante/SIMD).

## 3. Compilar o cliente

```sh
make client                   # gera ./zigcalc
```

Testes unitários das funções Zig, sem carregar nada no kernel:

```sh
make hosttest                 # zig test kernel/zigcalc_test.zig
```

## 4. Carregar o módulo

```sh
insmod kernel/zigcalc.ko      # ou: make load
lsmod | grep zigcalc
modinfo kernel/zigcalc.ko
ls -l /dev/zigcalc
dmesg | tail -n 30
```

Uso:

```sh
./zigcalc soma 10 20          # Resultado: 30
./zigcalc sub  50 15          # Resultado: 35
./zigcalc mult 7 8            # Resultado: 56
./zigcalc div  100 4          # Resultado: 25
./zigcalc div  10 0           # Erro: divisão por zero
```

Se `/dev/zigcalc` não aparecer sozinho (mdev/devtmpfs), crie manualmente a
partir do `major:minor` exposto no sysfs:

```sh
cat /sys/class/zigcalc/zigcalc/dev          # ex.: 249:0
mknod /dev/zigcalc c 249 0 && chmod 666 /dev/zigcalc
```

## 5. Executar os testes

```sh
make test                     # ou: sh tests/test.sh
```

O script carrega o módulo, executa todas as operações, os casos de erro
(EDOM, ERANGE, ENOTTY, EFAULT), o `strace`, 8 clientes simultâneos, confere o
`dmesg`, descarrega o módulo e verifica que os recursos foram liberados.
As evidências ficam em `docs/evidencias/`. Parâmetros opcionais:
`WORKERS=16 ITER=50 sh tests/test.sh`.

## 6. Descarregar o módulo

```sh
rmmod zigcalc                 # ou: make unload
```

## Contrato de erros

| Situação                    | Código retornado pelo módulo | Mensagem do cliente                   |
|-----------------------------|------------------------------|---------------------------------------|
| Comando desconhecido        | `-ENOTTY` (-25)              | `Erro: comando ioctl desconhecido`    |
| Ponteiro de usuário inválido| `-EFAULT` (-14)              | `Erro: ponteiro de usuário inválido`  |
| Divisão por zero            | `-EDOM` (-33)                | `Erro: divisão por zero`              |
| Transbordamento aritmético  | `-ERANGE` (-34)              | `Erro: transbordamento aritmético`    |

Comandos de diagnóstico do cliente (usados em `tests/test.sh`):
`./zigcalc ioctl-invalido` (provoca ENOTTY) e `./zigcalc ponteiro-invalido`
(envia ponteiro NULL, provoca EFAULT).

## Problemas comuns

| Sintoma | Causa provável / solução |
|---|---|
| `make: *** /lib/modules/.../build: No such file` | Faltam os headers: `apk add linux-virt-dev` (variante igual à de `uname -r`). |
| `insmod: Invalid module format` | Módulo compilado para outro kernel. Compare `modinfo -F vermagic kernel/zigcalc.ko` com `uname -r`; recompile (`make clean && make module`). |
| `Unknown symbol` / `disagrees about version of symbol` | Headers de versão diferente da do kernel em execução. |
| `zig: command not found` / versão ≠ 0.16.0 | Instale o Zig 0.16.0 e coloque no PATH (`zig version`). |
| `Erro: /dev/zigcalc não existe` | Módulo não carregado ou nó não criado (ver seção 4). |
| `Erro: permissão negada` | Execute como root ou `chmod 666 /dev/zigcalc`. |
| Avisos do `objtool` durante o build | Esperados com objeto não-C; só são problema se o `.ko` não for gerado. |
