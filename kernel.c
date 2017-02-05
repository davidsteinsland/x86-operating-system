#include <stdint.h>
#include <gdt.h>
#include <screen.h>
#include <io.h>

/* defined in kernel_helpers.s */
extern uint32_t get_eax(void);
extern uint32_t get_ebx(void);
extern uint32_t get_ecx(void);
extern uint32_t get_edx(void);
extern uint32_t get_esi(void);
extern uint32_t get_edi(void);

#define BOOT_ADDR 0x7c00

/* outputs a character to the debug console, if "port_e9_hack: enabled=1" is set in config */
#define BOCHS_PRINT_CHAR(c) outportb(0xe9, c)
/* stops simulation and breaks into the debug console */
#define BOCHS_BREAK() outportw(0x8A00,0x8A00); outportw(0x8A00,0x08AE0);

typedef struct {
  /* jmp short + nop + oem */
  uint8_t jmp; /* jmp instruction */
  uint8_t jmp_target; /* target of jmp instruction */
  uint8_t nop; /* the nop instruction */

  uint8_t oem[8]; /* oem name, 8 bytes */

  /* BPB 2.0 */
  uint16_t bytes_per_logical_sector;
  uint8_t logical_sectors_per_cluster;
  uint16_t reserved_logical_sectors;
  uint8_t number_of_fats;
  uint16_t root_directory_entries;
  uint16_t total_logical_sectors;
  uint8_t media_descriptor;
  uint16_t logical_sectors_per_fat;
  /* End BPB 2.0 */

  /* BPB 3.31 */
  uint16_t physical_sectors_per_track;
  uint16_t heads_per_cylinder;
  uint32_t hidden_sectors_count;
  uint32_t total_logical_sectors_including_hidden;
  /* End BPB 3.31 */

  /* EBPB - Extended BIOS Parameter Block */
  uint8_t drive_number;
  uint8_t reserved;

  uint8_t extended_boot_signature; /* should be 0x29 */
  uint8_t volume_id[4];
  uint8_t partition_volume_label[11];
  uint8_t filesystem_type[8];
} __attribute__((packed)) bpb_t;

void read_bpb() {
  bpb_t* bpb = (bpb_t*)BOOT_ADDR;

  printstr("OEM: <");
  printstrl((char*)&bpb->oem, 8);
  printstr(">\n");

  printstr("Bytes per logical sector: ");
  printw(bpb->bytes_per_logical_sector);
  printstr("\n");

  printstr("Logical sectors per cluster: ");
  printb(bpb->logical_sectors_per_cluster);
  printstr("\n");

  printstr("Reserved logical sectors: ");
  printw(bpb->reserved_logical_sectors);
  printstr("\n");

  printstr("Number of FATs: ");
  printb(bpb->number_of_fats);
  printstr("\n");

  printstr("Root directory entries: ");
  printw(bpb->root_directory_entries);
  printstr("\n");

  printstr("Total logical sectors: ");
  printw(bpb->total_logical_sectors);
  printstr("\n");

  printstr("Media descriptor: 0x");
  printhw(bpb->media_descriptor);
  printstr("\n");

  printstr("Logical sectors per FAT: ");
  printw(bpb->logical_sectors_per_fat);
  printstr("\n");

  printstr("Physical sectors per track: ");
  printw(bpb->physical_sectors_per_track);
  printstr("\n");

  printstr("Heads per cylinder: ");
  printw(bpb->heads_per_cylinder);
  printstr("\n");

  printstr("Hidden sectors count: ");
  printl(bpb->hidden_sectors_count);
  printstr("\n");

  printstr("Total logical sectors including hidden: ");
  printl(bpb->total_logical_sectors_including_hidden);
  printstr("\n");

  printstr("Drive number: ");
  printb(bpb->drive_number);
  printstr("\n");

  printstr("Boot signature number: 0x");
  printhb(bpb->extended_boot_signature);
  printstr("\n");

  printstr("Volume label: <");
  printstrl((char*)&bpb->partition_volume_label, 11);
  printstr(">\n");

  printstr("Filesystem type: <");
  printstrl((char*)&bpb->filesystem_type, 8);
  printstr(">\n");
}

void dump_registers() {
  printstr("EAX: ");
  uint32_t eax = get_eax();
  printhl(eax);

  printstr(" EBX: ");
  uint32_t ebx = get_ebx();
  printhl(ebx);

  printstr(" ECX: ");
  uint32_t ecx = get_ecx();
  printhl(ecx);

  printstr(" EDX: ");
  uint32_t edx = get_edx();
  printhl(edx);
  printstr("\n");

  printstr("ESI: ");
  uint32_t esi = get_esi();
  printhl(esi);

  printstr(" EDI: ");
  uint32_t edi = get_edi();
  printhl(edi);

  printstr("\n");
}

void read_gdt() {
  gdtr_t gdtr;
  get_gdt(&gdtr);

  printstr("Size of GDT: ");
  printw(gdtr.size + 1);
  printstr(" bytes\n");

  uint16_t i, entries = (gdtr.size + 1)/sizeof(gdt_t);

  /* entry 0 is useless -- null descriptor */
  for (i = 1; i < entries; i++) {
    printstr("Entry: ");
    printw(i);
    printstr(": ");

    gdt_t* entry = &gdtr.entries[i];
    uint32_t limit = ((entry->flags & 0xF) << 16) | entry->limit1;
    uint32_t base = (entry->base3 << 24) | (entry->base2 << 16) | entry->base1;

    printstr("Base: 0x");
    printhl(base);

    printstr(" Limit: 0x");
    printhl(limit);

    printstr(" Acc: 0x");
    printhb(entry->access_byte);

    printstr(" Flags: 0x");
    printhb(entry->flags >> 4);

    printstr("\n");
  }
}

void init_gdt() {
  gdt_t entries[3];
  entries[1].limit1 = 0xffff;
  entries[1].base1 = 0x0000;
  entries[1].base2 = 0x00;
  entries[1].access_byte = 0x9a;
  entries[1].flags = 0xcf;
  entries[1].base3 = 0x00;

  entries[2].limit1 = 0xffff;
  entries[2].base1 = 0x0000;
  entries[2].base2 = 0x00;
  entries[2].access_byte = 0x92;
  entries[2].flags = 0xcf;
  entries[2].base3 = 0x00;

  gdtr_t gdtr = {
    .size = 23,
    .entries = &entries[0]
  };

  gdt_create_entry(&entries[1], 0x00000000, 0x000fffff, 0x92, 0xcf);
  gdt_create_entry(&entries[2], 0x00000000, 0x000fffff, 0x92, 0xcf);

  set_gdt(&gdtr, 0x08, 0x10);
}

void kernel_main()
{
  clear_screen();

  /* magic breakpoint for bochs */
  __asm__ __volatile__("xchg %bx, %bx");

  read_gdt();

  /*char s[] = "Welcome to DavidOS!";
  uint8_t i;
  for (i = 0; i < 19; i++) {
    screen_print(s[i], row, col++);
  }
  row++;
  col = 0;*/

  // printstr("Welcome to David OS.\n");

  /*static char* s2 = "Welcome to David OS!\n";
  printstr(s2);*/

  read_bpb();
  dump_registers();

  uint32_t u, v, w;
  for (w = 0; w < 5; w++) {
    for (u = 0; u < 10; u++) {
      for (v = 0; v < 0xFFFFFF; v++) {
        /* NOP */
      }
    }
    printstr("Delay ");
    printk(w);
    printstr("\n");
  }

  while(1);
}
