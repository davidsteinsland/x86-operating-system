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

### Global Descriptor Table