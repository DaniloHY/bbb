// Cliente do modulo zigcalc (Zig 0.16.0).
//
// Este programa NAO calcula nada. Ele apenas:
//   1. interpreta a linha de comando;
//   2. abre /dev/zigcalc;
//   3. envia a requisicao com ioctl(2);
//   4. mostra o resultado (ou o erro) devolvido pelo kernel;
//   5. fecha o descritor.
//
// Todas as contas sao feitas por zig_calcular(), dentro do modulo.
//
// As chamadas de sistema sao feitas diretamente via std.os.linux (sem libc),
// para que o strace mostre exatamente: openat -> ioctl -> close.

const std = @import("std");
const linux = std.os.linux;

// ---------------------------------------------------------------------------
// Interface com o modulo (espelha kernel/zigcalc_ioctl.h)
// ---------------------------------------------------------------------------

/// struct zigcalc_request { __s32 a; __s32 b; __s32 resultado; };
/// "extern struct" garante layout identico ao de C (12 bytes, sem padding).
const Request = extern struct {
    a: i32,
    b: i32,
    resultado: i32,
};

comptime {
    if (@sizeOf(Request) != 12) @compileError("Request deve ter 12 bytes, como struct zigcalc_request");
}

const DEVICE_PATH = "/dev/zigcalc";

/// _IOWR(type, nr, struct zigcalc_request) do Linux (layout generico/x86_64):
///   bits 31..30 = direcao (3 = leitura|escrita)
///   bits 29..16 = tamanho da struct
///   bits 15..8  = "magic number" do driver
///   bits  7..0  = numero do comando
fn iowr(comptime nr: u8) u32 {
    const dir: u32 = 3; // _IOC_READ | _IOC_WRITE
    return (dir << 30) | (@as(u32, @sizeOf(Request)) << 16) | (@as(u32, 'Z') << 8) | nr;
}

const IOC_SOMA: u32 = iowr(1); // 0xC00C5A01
const IOC_SUB: u32 = iowr(2); //  0xC00C5A02
const IOC_MULT: u32 = iowr(3); // 0xC00C5A03
const IOC_DIV: u32 = iowr(4); //  0xC00C5A04
/// Comando que o modulo NAO conhece: usado para provocar -ENOTTY.
const IOC_INEXISTENTE: u32 = iowr(99);

// errno do Linux usados pelo contrato do modulo
const EFAULT = 14;
const EACCES = 13;
const ENOENT = 2;
const ENOTTY = 25;
const EDOM = 33;
const ERANGE = 34;

// ---------------------------------------------------------------------------
// Utilitarios
// ---------------------------------------------------------------------------

/// As syscalls em std.os.linux devolvem usize; erros vem como -errno
/// (valores entre -4095 e -1). Esta funcao devolve o errno (0 = sem erro).
fn errnoDe(r: usize) i32 {
    const s: isize = @bitCast(r);
    if (s < 0 and s > -4096) return @intCast(-s);
    return 0;
}

fn escrever(io: std.Io, arquivo: std.Io.File, comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const texto = std.fmt.bufPrint(&buf, fmt, args) catch return;
    arquivo.writeStreamingAll(io, texto) catch {};
}

fn uso(io: std.Io) noreturn {
    escrever(io, std.Io.File.stderr(),
        \\Uso: zigcalc <operacao> <a> <b>
        \\
        \\Operacoes:
        \\  soma   <a> <b>    a + b
        \\  sub    <a> <b>    a - b
        \\  mult   <a> <b>    a * b
        \\  div    <a> <b>    a / b  (quociente inteiro)
        \\
        \\Comandos de diagnostico (para os testes):
        \\  ioctl-invalido    envia um comando ioctl desconhecido (espera ENOTTY)
        \\  ponteiro-invalido envia um ponteiro NULL como argumento (espera EFAULT)
        \\
        \\Os operandos sao inteiros de 32 bits com sinal.
        \\
    , .{});
    std.process.exit(2);
}

fn mensagemDeErro(errno: i32) []const u8 {
    return switch (errno) {
        EDOM => "divisão por zero",
        ERANGE => "transbordamento aritmético",
        ENOTTY => "comando ioctl desconhecido (ENOTTY)",
        EFAULT => "ponteiro de usuário inválido (EFAULT)",
        ENOENT => "/dev/zigcalc não existe (o módulo está carregado? use: insmod kernel/zigcalc.ko)",
        EACCES => "permissão negada em /dev/zigcalc (execute como root)",
        else => "falha na chamada ioctl",
    };
}

fn falhar(io: std.Io, errno: i32) noreturn {
    escrever(io, std.Io.File.stderr(), "Erro: {s}\n", .{mensagemDeErro(errno)});
    std.process.exit(1);
}

fn lerOperando(io: std.Io, texto: []const u8) i32 {
    return std.fmt.parseInt(i32, texto, 10) catch {
        escrever(io, std.Io.File.stderr(), "Erro: operando inválido '{s}' (esperado inteiro de 32 bits com sinal)\n", .{texto});
        std.process.exit(2);
    };
}

// ---------------------------------------------------------------------------
// Programa principal
// ---------------------------------------------------------------------------

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2) uso(io);

    const nome = args[1];

    // --- escolhe o comando ioctl e prepara a requisicao ---------------------
    var cmd: u32 = undefined;
    var usar_ponteiro_nulo = false;
    var req: Request = .{ .a = 0, .b = 0, .resultado = 0 };

    if (std.mem.eql(u8, nome, "ioctl-invalido")) {
        cmd = IOC_INEXISTENTE;
    } else if (std.mem.eql(u8, nome, "ponteiro-invalido")) {
        cmd = IOC_SOMA;
        usar_ponteiro_nulo = true;
    } else {
        if (std.mem.eql(u8, nome, "soma")) {
            cmd = IOC_SOMA;
        } else if (std.mem.eql(u8, nome, "sub")) {
            cmd = IOC_SUB;
        } else if (std.mem.eql(u8, nome, "mult")) {
            cmd = IOC_MULT;
        } else if (std.mem.eql(u8, nome, "div")) {
            cmd = IOC_DIV;
        } else {
            escrever(io, std.Io.File.stderr(), "Erro: operação desconhecida '{s}'\n\n", .{nome});
            uso(io);
        }
        if (args.len != 4) uso(io);
        req.a = lerOperando(io, args[2]);
        req.b = lerOperando(io, args[3]);
    }

    // --- 1. abre o dispositivo ---------------------------------------------
    // openat(AT_FDCWD = -100, "/dev/zigcalc", O_RDWR | O_CLOEXEC)
    const O_RDWR: u32 = 0o2;
    const O_CLOEXEC: u32 = 0o2000000;
    const flags: linux.O = @bitCast(O_RDWR | O_CLOEXEC);

    const r_open = linux.openat(-100, DEVICE_PATH, flags, 0);
    const e_open = errnoDe(r_open);
    if (e_open != 0) falhar(io, e_open);
    const fd: i32 = @intCast(r_open);

    // --- 2. envia a requisicao ao modulo -----------------------------------
    // ioctl(fd, cmd, &req): o kernel localiza o driver a partir do fd e chama
    // zigcalc_ioctl() (campo .unlocked_ioctl de struct file_operations).
    const arg: usize = if (usar_ponteiro_nulo) 0 else @intFromPtr(&req);
    const r_ioctl = linux.ioctl(fd, cmd, arg);
    const e_ioctl = errnoDe(r_ioctl);

    // --- 3. fecha o descritor (sempre, mesmo em caso de erro) ---------------
    _ = linux.close(fd);

    if (e_ioctl != 0) falhar(io, e_ioctl);

    // --- 4. mostra o resultado calculado pelo kernel ------------------------
    escrever(io, std.Io.File.stdout(), "Resultado: {d}\n", .{req.resultado});
}
