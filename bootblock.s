.text
.code16
#
#
# Helpful articles:
# http://www.independent-software.com/writing-your-own-bootloader-for-a-toy-operating-system-4/
#
# Creating the floppy:
# Use WinImage to create a 1.44 MB floppy
# (I tried using OSX Disk Utility, but I think it creates a bad floppy)
#
# Next, copy the floppy as empty_floppy.img and my_os.img
# Make the bootblock, "make"
# Mount my_os.img and copy stage2.bin as SECOND.BIN
# Run "make qemu"

# When the BIOS jumps to your code you can't rely on
# CS,DS,ES,SS,SP registers having valid or expected values.
#
# They should be set up appropriately when your bootloader starts.
# You can only be guaranteed that your bootloader will be loaded
# and run from physical address 0x00007c00 and
# that the boot drive number is loaded into the DL register.

# [ORG 0x7C00] is fine, but there is an assumption being made that
# the CS segment is set to 0x0000 when it reached our bootloader.
#
# We then set DS=CS.
# Conventional wisdom for a naive bootloader is that
# the BIOS jumps to 0x0000:0x7c00 (CS:IP).
# ORG should match the offset (in this case IP).
#
# The problem is that in reality the BIOS jumps to physical address 0x00007c00
# but it can do it with a variety of CS:IP pairs.
#
# .org = 0x0, the  DS == .org and CS = 0x7C0

#
# TODO
# - Use the floppy as a file system, containing
# kernel, processes, and so on.
#
# Suggested structure:
# sector 1:
# Volume boot record (BPB) and boot loader
# sector 2:
# stage 2 boot loader
#
# filesystem:
# kernel.SYS
# process1.SYS
#
.globl _start
_start:

.equ STAGE1_SEGMENT,          0x7C0
.equ DIRECTORY_TABLE_SEGMENT, 0x7E0   # 512 bytes after 0x7c0:0x0
.equ FAT_SEGMENT,             0x800   # 512 bytes after 0x800:0x0
.equ STAGE2_SEGMENT,          0x920   # 9 sectors after FAT_SEGMENT
.equ STACK_SEGMENT,           0x7000
.equ STACK_POINTER,           0xfffe

# jump past the BIOS parameter block;
# valid x86-bootable disks should start with
# a near jump followed by a NOP (opstring sequence 0xE9 0x?? 0x90)
jmp after_bpb
nop

.include "bpb.s"

second_stage_filename:   .asciz "SECOND  BIN"
root_dir_size:           .word 0
root_dir_offset:         .word 0
file_cluster:            .word 0

after_bpb:
	# Since we cannot guarantee that BIOS loads our boot loader
	# at CS:IP 0x7C0:0x0 or 0x0:0x7C00, we force it by doing a long
	# jump. After the jump, the CS will be pointing to 0x7C0.
	ljmp $STAGE1_SEGMENT,$real_start

.include "helpers.s"

real_start:
	m_setup_stack $STACK_SEGMENT, $STACK_POINTER
	m_setup_segments

	# save the drive number we booted from
	mov %dl, drive_number

	m_reset_disk drive_number disk_error
	m_find_file $DIRECTORY_TABLE_SEGMENT, second_stage_filename
	m_read_fat $FAT_SEGMENT

	# now all FAT sectors are loaded into memory.
	# next we load one and one root directory sector

	m_read_file $FAT_SEGMENT, $STAGE2_SEGMENT, file_cluster

	# stage2 has been located and loaded into memory,
	# so jump to it and end our 512 byte restriction!
	mov $STAGE2_SEGMENT, %ax
	mov %ax, %ds
	ljmp $STAGE2_SEGMENT,$0x0

#
# Jumped to when we have exhausted all FAT entries,
# and we did not find our file
disk_error_not_found:
	mov $str_disk_error_not_found, %si
	call print

#
# Jumped to when we encounter a disk error while reset, reading,
# searching for a file, and so on.
disk_error:
	mov $str_disk_error, %si
	# lea str_disk_error, %si
	call print

reboot:
	jmp reboot
#	lea str_reboot, %si
#	call print
#	m_wait_for_keypress
#	m_reboot

str_disk_error: .string "Disk error\r\n"
str_disk_error_not_found: .string "Stage 2 not found\r\n"
str_reboot: .string "Press key to reboot\r\n"

.=510
.word 0xaa55
