#ifndef GDT_H
#define GDT_H

#include <stdint.h>

/*

7    6       5   4    3    2    1  0
+----+-------+---+----+----+----+----+
| Pr | Privl | 1 | Ex | DC | RW | Ac |
+----+-------+---+----+----+-----+---+
          Access byte

  Pr
    Present - normally set to "1", if set to "0" then
      selector cannot be used
  Privl
    Privilege level - a value of 0, 1, 2 or 3:
      0 - kernel, full access
      1 - drivers/kernel modules
      2 - drivers/kernel modules
      3 - user programs, least access
  Ex
    Executable - If set to "1", the memory contents are
      marked as executable code
  DC
    For code segments:
    Direction - A value of "1" indicates that the code can be executed
      from a lower privilege level
    For data segments:
    Conforming - A value of "1" indicates that the segment grows down,
      and "0" indicates that it grows upwards
  RW
    For code segments:
    Readable - If set to "1", the memory contents can be read
    For data segments:
    Writable - If set to "1", the memory contents can be written to
  Ac
    Accessed - CPU will set to "1" when the segment is accessed

---------------------------------------------------------------------

4    3    2   1   0
+----+----+---+---+
| Gr | Sz | 0 | 0 |
+----+----+---+---+
      Flags

  Gr
    Granularity - If set to "0", the descriptor's limit is
      specified in bytes. If "1", the limit in blocks of 4 kB pages
  Sz
    Size - If set to "0", the select defines 16-bit protected mode.
      "1" indicates 32-bit protected mode.
 */

/*
  uint32_t limit = ((entry->flags & 0xF) << 16) | entry->limit1;
  uint32_t base = (entry->base3 << 24) | (entry->base2 << 16) | entry->base1;

  limit is only 20 bits
 */
typedef struct {
  uint16_t limit1; // segment limit 15:00
  uint16_t base1; // base address 15:00
  uint8_t base2;  // base address 23:16
  uint8_t access_byte;
  uint8_t flags; // 0-3: limit 19:16, 4-7: flags
  uint8_t base3; // base 31:24
} __attribute__((packed)) gdt_t;

typedef struct {
  uint16_t size; /* size (in bytes) of the GDT, minus 1 */
  gdt_t* entries;
} __attribute__((packed)) gdtr_t;

#define MAX_ENTRIES 8192 /* sizeof(uint16_t) / sizeof(gdt_t) */

extern void get_gdt(gdtr_t*);
extern void set_gdt(gdtr_t*, uint16_t, uint16_t);

void gdt_create_entry(gdt_t*, uint32_t, uint32_t, uint8_t, uint8_t);

#endif
