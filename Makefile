# Makefile raiz do projeto zig-kernel-ioctl
#
#   make            compila modulo (kernel/zigcalc.ko) e cliente (./zigcalc)
#   make module     so o modulo
#   make client     so o cliente
#   make hosttest   testes unitarios das funcoes Zig (fora do kernel)
#   make check      verifica ambiente (kernel, headers, zig 0.16.0)
#   make load       insmod  (root)
#   make unload     rmmod   (root)
#   make test       executa tests/test.sh (root)
#   make clean

ZIG  ?= zig
KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build
ZIG_REQUIRED := 0.16.0

.PHONY: all module client hosttest check load unload test clean

all: module client

check:
	@echo "kernel em execucao : $(KVER)"
	@echo "headers (KDIR)     : $(KDIR)"
	@test -d "$(KDIR)" || { echo "ERRO: $(KDIR) nao existe. Instale: apk add linux-virt-dev (ou linux-lts-dev)"; exit 1; }
	@echo "zig                : $$($(ZIG) version)"
	@test "$$($(ZIG) version)" = "$(ZIG_REQUIRED)" || { echo "ERRO: e necessario Zig $(ZIG_REQUIRED)"; exit 1; }
	@echo "ambiente OK"

module:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/kernel ZIG=$(ZIG) modules
	@echo "== simbolos do objeto Zig (nao pode haver 'U' = indefinidos):"
	@nm kernel/zigcalc_math.o
	@echo "== instrucoes SSE/AVX no objeto Zig (deve ser 0):"
	@objdump -d kernel/zigcalc_math.o | grep -ciE 'xmm|ymm' || true

client: zigcalc

zigcalc: client/main.zig
	$(ZIG) build-exe client/main.zig -O ReleaseSafe --name zigcalc -femit-bin=zigcalc

hosttest:
	$(ZIG) test kernel/zigcalc_test.zig

load: kernel/zigcalc.ko
	insmod kernel/zigcalc.ko

unload:
	rmmod zigcalc

test: all
	sh tests/test.sh

clean:
	-$(MAKE) -C $(KDIR) M=$(CURDIR)/kernel clean
	rm -rf zigcalc zigcalc.o .zig-cache kernel/.zig-cache
