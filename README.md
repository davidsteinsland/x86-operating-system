IA-32 Operating System on a 1.44 MB floppy
==========================================

Boot block / boot loader

- Old concept, nothing has changed:
- 512 byte limitation
- 16 bit adressing
- FAT/Floppy

# Installation

- Use e.g. WinImage and create a 1.44 MB FAT12 floppy and name it "empty_floppy.img"
- Run `make` which will:
  - copy `empty_floppy.img` to `my_os.img`
  - compile and link `bootblock.bin`, `dist/SECOND.BIN` and `dist/KERNEL.BIN`
  - copy BPB from `empty_floppy.img` into `bootblock.bin`, and then copy `bootblock.bin` into first 512 bytes of `my_os.img`
- Next, you should mount `my_os.img` and copy the two files under `dist/` directly onto the image mount.
- Next, run `make qemu` as this will boot up a machine using `my_os.img` as floppy drive

# BIOS

* Checks last two bytes of the first 512 bytes of sector one, if they match `0x55`, `0xaa`
* Jumps to `0x7C0:0x0` or `0x0:0x7C00` (or any other `segment:offset` pair that gives the physical address of `0x7C00`. `CS:IP` registers may not neccessarily have the expected values; change them yourself using for example `ljmp`:

```assembly
.equ BOOT_SEGMENT, 0x7c0
start:
    ljmp $BOOT_SEGMENT, $real_start
real_start:
    # %cs is set properly
```

## Real mode: 16 bit addressing

## Boot Record

### Master boot record

### Volume boot record

### BIOS Parameter block

## Floppy - FAT12

### FAT Entries

Two FAT12 entries are stored into three bytes; if these bytes are `ab,cd,ef` then the entries are `dab` and `efc`.

Remember that the IA architecture is little endian: The least significant byte is stored first, so if we read a `word` like `0x[byte2][byte1]` the `byte1` is stored first on disk/memory.

So if we consider two FAT12 entries, we can construct them like:

```
0x[nibble1][byte1]
0x[byte2][nibble2]
```

Because of little endianness, `byte1` is stored first, then comes the `[nibble2][nibble1]` byte and finally `byte2`. Note that `nibble1` and `nibble2` formes a byte `0x[nibble2][nibble1]`

The first FAT entry is not used, and the first valid cluster/FAT index is `2`. Because a FAT entry is 12 bytes (one and a half byte), we get the offset by `cluster * 1.5` (or the more assembly friendly: `cluster + (cluster >> 1)`).

To read a FAT entry, we read three two bytes from the offset calculcated above:

```c
uint8_t* fat_table = ....
uint16_t index = cluster + (cluster >> 1);

/* read two bytes */
uint16_t fat_entry = ((uint16_t*)fat_table)[index];

/* if index is even, we have read "byte1" and "nibble2nibble1".
	this would be the hexa "0x[nibble2][nibble1][byte1]". we get the entry by
	masking out nibble2: */
if (index % 2 == 0) {
    uint16_t next_cluster = fat_entry & 0x0FFF;
} else {
	/* ... if odd, then we have read "nibble2nibble1" and "byte2",
		represented as "0x[byte2][nibble2][nibble1]". we get the entry
		by removing last four bits (nibble1) */
	uint16_t next_cluster = fat_entry >> 4;
```

## Protected mode

The Intel Manual Volume 3A mentions the requirements for entering protected mode:

### 9.8 Software Initialization for Protected-Mode Operation:

Before the processor can be switched to protected mode, the software initialization code must load a minimum number of protected mode data structures and code modules into memory to support reliable operation of the processor in protected mode. These data structures include the following:
* A IDT.
* A GDT.
* A TSS.
* (Optional) An LDT.
* If paging is to be used, at least one page directory and one page table.
* A code segment that contains the code to be executed when the processor switches to protected mode.
* One or more code modules that contain the necessary interrupt and exception handlers.
Software initialization code must also initialize the following system registers before the processor can be switched to protected mode:

* The GDTR.
* (Optional.) The IDTR. This register can also be initialized immediately after switching to protected mode, prior
to enabling interrupts.
* Control registers CR1 through CR4.
* (Pentium 4, Intel Xeon, and P6 family processors only.) The memory type range registers (MTRRs).
With these data structures, code modules, and system registers initialized, the processor can be switched to protected mode by loading control register CR0 with a value that sets the PE flag (bit 0).

### 9.9 Mode Switching

Protected mode is entered by executing a MOV CR0 instruction that sets the PE flag in the CR0 register. (In the same instruction, the PG flag in register CR0 can be set to enable paging.) Execution in protected mode begins with a CPL of 0.

Intel 64 and IA-32 processors have slightly different requirements for switching to protected mode. To insure upwards and downwards code compatibility with Intel 64 and IA-32 processors, we recommend that you follow these steps:

1. Disable interrupts. A CLI instruction disables maskable hardware interrupts. NMI interrupts can be disabled with external circuitry. (Software must guarantee that no exceptions or interrupts are generated during the mode switching operation.)
2. Execute the LGDT instruction to load the GDTR register with the base address of the GDT.
3. Execute a MOV CR0 instruction that sets the PE flag (and optionally the PG flag) in control register CR0.
4. Immediately following the MOV CR0 instruction, execute a far JMP or far CALL instruction. (This operation is typically a far jump or call to the next instruction in the instruction stream.)
5. The JMP or CALL instruction immediately after the MOV CR0 instruction changes the flow of execution and serializes the processor.
6. If paging is enabled, the code for the MOV CR0 instruction and the JMP or CALL instruction must come from a page that is identity mapped (that is, the linear address before the jump is the same as the physical address after paging and protected mode is enabled). The target instruction for the JMP or CALL instruction does not need to be identity mapped.
7. If a local descriptor table is going to be used, execute the LLDT instruction to load the segment selector for the LDT in the LDTR register.
8. Execute the LTR instruction to load the task register with a segment selector to the initial protected-mode task or to a writable area of memory that can be used to store TSS information on a task switch.
9. After entering protected mode, the segment registers continue to hold the contents they had in real-address mode. The JMP or CALL instruction in step 4 resets the CS register. Perform one of the following operations to update the contents of the remaining segment registers.
	* Reload segment registers DS, SS, ES, FS, and GS. If the ES, FS, and/or GS registers are not going to be used, load them with a null selector.
	* Perform a JMP or CALL instruction to a new task, which automatically resets the values of the segment registers and branches to a new code segment.
10. Execute the LIDT instruction to load the IDTR register with the address and limit of the protected-mode IDT.
11. Execute the STI instruction to enable maskable hardware interrupts and perform the necessary hardware operation to enable NMI interrupts.

Random failures can occur if other instructions exist between steps 3 and 4 above. Failures will be readily seen in some situations, such as when instructions that reference memory are inserted between steps 3 and 4 while in system management mode.

### Global Descriptor Table
