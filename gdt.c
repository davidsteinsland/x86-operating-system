#include <gdt.h>

/*static uint16_t current_entry = 0;
static gdt_t entries[MAX_ENTRIES];
static gdtr_t gdtr = {
  .size = MAX_ENTRIES * sizeof(gdt_t) - 1,
  .first = &entries[0]
}*/

void gdt_create_entry(gdt_t* entry, uint32_t base, uint32_t limit, uint8_t access, uint8_t flags)
{
  entry->limit1 = limit & 0xFFFF;
  entry->base1 = base & 0xFFFF;
  entry->base2 = (base >> 16) & 0xFF;
  entry->access_byte = access;
  entry->flags = (flags << 4) | ((limit >> 16) & 0xF);
  entry->base3 = (base >> 24) & 0xFF;
}
