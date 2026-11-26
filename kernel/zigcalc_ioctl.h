#ifndef ZIGCALC_IOCTL_H
#define ZIGCALC_IOCTL_H

#include <linux/types.h>
#include <linux/ioctl.h>

struct zigcalc_request {
    __s32 a;
    __s32 b;
    __s32 resultado;
};

#define ZIGCALC_IOC_MAGIC 'Z'

#define ZIGCALC_IOC_SOMA \
    _IOWR(ZIGCALC_IOC_MAGIC, 1, struct zigcalc_request)

#define ZIGCALC_IOC_SUB \
    _IOWR(ZIGCALC_IOC_MAGIC, 2, struct zigcalc_request)

#define ZIGCALC_IOC_MULT \
    _IOWR(ZIGCALC_IOC_MAGIC, 3, struct zigcalc_request)

#define ZIGCALC_IOC_DIV \
    _IOWR(ZIGCALC_IOC_MAGIC, 4, struct zigcalc_request)

#endif
