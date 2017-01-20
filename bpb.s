# This file represents the BIOS Parameter Block
# and should be the 58 next bytes right after the 3 byte jmp instruction that's
# in the beginning of the boot sector.
#
# Although this file contains meaningful values, it is essentially
# discarded as we keep whatever is on the actual floppy instead.
#
# The values are kept for "pedagogical reasons" and as a way of
# having meaningful symbol names to use in bootblock.s and stage2.s

# OEM name
oem:                                    .ascii "MSWIN4.1"

#
# Memory layout
# 0x7C00 - first sector of FAT12 disk
# 0x7E00 - (512 bytes after 0x7c00) second stage boot loader (or we could overwrite 7c00?)
# 0x8000 - (512 bytes after 0x7e00) where our kernel will be loaded
#
# Floppy type: 0xF0:
# 3.5-inch (90 mm) Double Sided, 80 tracks per side, 18 or 36 sectors per track (1440 KB, known as “1.44 MB”; or 2880 KB, known as “2.88 MB”).
# 512 bytes per sector * 18 sectors per track * 80 tracks per side * 2 sides = 1440 KB
#
# Copy BPB from floppy to bootblock:
# Set block size to 1 byte so we can skip first 11 bytes (jump instruction + OEM ID)
# Length of BPB is 51 bytes (BPB 2.0 + BPB 3.31 + EBPB)
#
# Place the BPB within the bootblock
# $ dd if=empty_floppy.img of=bootblock.bin bs=1 skip=11 seek=11 count=51 conv=notrunc
# Copy bootblock back into floppy
# $ cp empty_floppy.img bootblock.img
# $ dd if=bootblock.bin of=bootblock.img bs=512 count=1 conv=notrunc

# BIOS parameter block
# ======================================================================
# DOS 2.0 BPB
bytes_per_logical_sector:               .word 512            # in powers of two; most common value is 512
logical_sectors_per_cluster:            .byte 1              # Allowed values are 1, 2, 4, 8, 16, 32, 64, and 128.
reserved_logical_sectors:               .word 1              # The number of logical sectors before the first FAT (at least one)
                                                             # we choose the number two, because second stage is in sector 2
number_of_fats:                         .byte 2              # Number of File Allocation Tables. Almost always 2;
root_directory_entries:                 .word 224            # Maximum number of FAT12 root directory entries.
total_logical_sectors:                  .word 2880           # Total logical sectors
media_descriptor:                       .byte 0xF0           #
logical_sectors_per_fat:                .word 9              # Logical sectors per File Allocation Table for FAT12.
# DOS 3.31 BPB                                               -
physical_sectors_per_track:             .word 18             # Physical sectors per track for disks with INT 13h CHS geometry, e.g., 18 for a “1.44 MB” (1440 KB) floppy.
heads_per_cylinder:                     .word 2              # Number of heads for disks with INT 13h CHS geometry,[9] e.g., 2 for a double sided floppy
hidden_sectors_count:                   .word 0              # Count of hidden sectors preceding the partition that contains this FAT volume.
										.word 0              # This field should always be zero on media that are not partitioned
total_logical_sectors_including_hidden: .word 0              # Total logical sectors (only set if total_logical_sectors is 0)
										.word 0              #
# Extended BIOS parameter block                              -
drive_number:                           .byte 0              # Physical drive number (0x00 for (first) removable media, 0x80 for (first) fixed disk as per INT 13h).
reserved:                               .byte 0              #
boot_signature:                         .byte 0x29           #
volume_id:                              .ascii "FLOP"        #
volume_label:                           .ascii "DOS FLOPPY " # ad
filesystem_type:                        .ascii "FAT12   "
# ======================================================================
