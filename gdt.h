#ifndef GDT_H
#define GDT_H

#include <stdint.h>

/*
  uint32_t limit = ((entry->flags & 0xF) << 16) | entry->limit1;
  uint32_t base = (entry->base3 << 24) | (entry->base2 << 16) | entry->base1;

  limit is only 20 bits
 */
typedef struct {
  uint16_t limit1; // limit 0:15
  uint16_t base1; // base 15:00
  uint8_t base2;  // base 23:16
  uint8_t access_byte;
  uint8_t flags; // 0-3: limit 16:19, 4-7: flags
  uint8_t base3; // base 31:24
} __attribute__((packed)) gdt_t;

typedef struct {
  uint16_t size; /* size (in bytes) of the GDT, minus 1 */
  gdt_t* entries;
} __attribute__((packed)) gdtr_t;

#define MAX_ENTRIES 8192 /* sizeof(uint16_t) / sizeof(gdt_t) */

extern void get_gdt(gdtr_t*);
extern void set_gdt(gdtr_t*, uint16_t, uint16_t);

#endif
