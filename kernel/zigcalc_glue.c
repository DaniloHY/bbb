
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/fs.h>
#include <linux/cdev.h>
#include <linux/device.h>
#include <linux/uaccess.h>
#include <linux/errno.h>

#include "zigcalc_ioctl.h"
#include "zigcalc.h"

#define DEVICE_NAME "zigcalc"
#define CLASS_NAME  "zigcalc"

static dev_t zigcalc_dev;
static struct cdev zigcalc_cdev;
static struct class *zigcalc_class;
static struct device *zigcalc_device;

/*
 * Manipulador das requisicoes ioctl.
 */
static long zigcalc_ioctl(
    struct file *file,
    unsigned int cmd,
    unsigned long arg
) {
    struct zigcalc_request request;
    void __user *user_ptr = (void __user *)arg;

    u32 operacao;
    int erro;

    /*
     * Identifica a operacao solicitada.
     */
    switch (cmd) {
        case ZIGCALC_IOC_SOMA:
            operacao = ZIGCALC_OP_SOMA;
            break;

        case ZIGCALC_IOC_SUB:
            operacao = ZIGCALC_OP_SUB;
            break;

        case ZIGCALC_IOC_MULT:
            operacao = ZIGCALC_OP_MULT;
            break;

        case ZIGCALC_IOC_DIV:
            operacao = ZIGCALC_OP_DIV;
            break;

        default:
            pr_warn("zigcalc: comando ioctl desconhecido\n");
            return -ENOTTY;
    }

    /*
     * Copia os dados do espaco de usuario.
     */
    if (copy_from_user(&request, user_ptr, sizeof(request))) {
        pr_warn("zigcalc: falha ao copiar dados do usuario\n");
        return -EFAULT;
    }

    /*
     * Executa o calculo em Zig.
     */
    erro = zig_calcular(
        operacao,
        request.a,
        request.b,
        &request.resultado
    );

    if (erro != 0) {
        pr_warn("zigcalc: erro na operacao: %d\n", erro);
        return erro;
    }

    /*
     * Devolve o resultado ao usuario.
     */
    if (copy_to_user(user_ptr, &request, sizeof(request))) {
        pr_warn("zigcalc: falha ao devolver resultado\n");
        return -EFAULT;
    }

    pr_info(
        "zigcalc: operacao %u executada com sucesso\n",
        operacao
    );

    return 0;
}

/*
 * Operacoes disponibilizadas pelo dispositivo.
 */
static const struct file_operations zigcalc_fops = {
    .owner = THIS_MODULE,
    .unlocked_ioctl = zigcalc_ioctl,
};

/*
 * Inicializacao do modulo.
 */
static int __init zigcalc_init(void)
{
    int erro;

    pr_info("zigcalc: inicializando modulo\n");

    /*
     * Reserva um numero major/minor.
     */
    erro = alloc_chrdev_region(
        &zigcalc_dev,
        0,
        1,
        DEVICE_NAME
    );

    if (erro < 0) {
        pr_err("zigcalc: falha ao reservar dispositivo\n");
        return erro;
    }

    /*
     * Inicializa o dispositivo de caractere.
     */
    cdev_init(&zigcalc_cdev, &zigcalc_fops);
    zigcalc_cdev.owner = THIS_MODULE;

    erro = cdev_add(&zigcalc_cdev, zigcalc_dev, 1);

    if (erro < 0) {
        pr_err("zigcalc: falha ao registrar cdev\n");
        goto erro_cdev;
    }

    /*
     * Cria a classe do dispositivo.
     */
    zigcalc_class = class_create(CLASS_NAME);

    if (IS_ERR(zigcalc_class)) {
        erro = PTR_ERR(zigcalc_class);
        pr_err("zigcalc: falha ao criar classe\n");
        goto erro_class;
    }

    /*
     * Cria o dispositivo /dev/zigcalc.
     */
    zigcalc_device = device_create(
        zigcalc_class,
        NULL,
        zigcalc_dev,
        NULL,
        DEVICE_NAME
    );

    if (IS_ERR(zigcalc_device)) {
        erro = PTR_ERR(zigcalc_device);
        pr_err("zigcalc: falha ao criar dispositivo\n");
        goto erro_device;
    }

    pr_info("zigcalc: dispositivo /dev/zigcalc criado\n");

    return 0;

erro_device:
    class_destroy(zigcalc_class);

erro_class:
    cdev_del(&zigcalc_cdev);

erro_cdev:
    unregister_chrdev_region(zigcalc_dev, 1);

    return erro;
}

/*
 * Finalizacao do modulo.
 */
static void __exit zigcalc_exit(void)
{
    device_destroy(zigcalc_class, zigcalc_dev);
    class_destroy(zigcalc_class);

    cdev_del(&zigcalc_cdev);

    unregister_chrdev_region(zigcalc_dev, 1);

    pr_info("zigcalc: modulo removido\n");
}

module_init(zigcalc_init);
module_exit(zigcalc_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("zig-kernel-ioctl");
MODULE_DESCRIPTION("Calculadora com operacoes matematicas em Zig");
MODULE_VERSION("1.0");
