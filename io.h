#ifndef IO_H
#define IO_H

#include <stdint.h>

/* read from the I/O port */
uint8_t inportb (uint16_t port);

/* write to I/O port */
void outportb (uint16_t port, uint8_t data);

#endif
