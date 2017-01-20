.text
.code16

#
# when loading the kernel, we need to place it somewhere
# it doesn't overwrite the FAT, directory table or stage2. when the kernel is loaded,
# and the FAT and directory is no longer needed, we can move the kernel.
#
.equ STAGE1_SEGMENT,          0x7C0
.equ DIRECTORY_TABLE_SEGMENT, 0x7E0   # 512 bytes after 0x7c0:0x0
.equ FAT_SEGMENT,             0x800   # 512 bytes after 0x800:0x0
.equ STAGE2_SEGMENT,          0x920   # 9 sectors after FAT_SEGMENT
.equ KERNEL_SEGMENT,          0x10000 # safely put right after the first megabyte
.equ KERNEL_TEMPORARY_SEGMENT,0xA00   # 7 sectors after STAGE2_SEGMENT
									  # this should reserve more than enough space for the stage2
.equ STACK_SEGMENT,           0x7000
.equ STACK_POINTER,           0xfffe

.equ GDT, 0
.equ LDT, 1

.equ NULL_SEGMENT, 0x0
.equ CODE_SEGMENT, 0x8
.equ DATA_SEGMENT, 0x10

# Make sure the first 61 bytes of stage2 is identical to the
# boot block, because we are going to be needing the values in the BPB later,
# when we are loading the kernel.
#
# as an alternative, instead of copying the BPB into stage2, we could reference
# the BPB values using an ES:DI syntax:
#
# es = 0x7C0
# di = 3 bytes (the "jmp + nop") + offset in the BPB
.globl _start
_start:
	jmp real_start

.include "bpb.s"

kernel_filename:   .asciz "KERNEL  BIN"
root_dir_size:     .word 0
root_dir_offset:   .word 0
file_cluster:      .word 0

.include "helpers.s"

# #define SEGMENT_SELECTOR(index, ti, rpl) (((index) << 3) | ((ti) << 2) | (rpl))
#
# seg = SEGMENT_SELECTOR(1, GDT, 0) // index 1, gdt, privilege level 0

#
# Enable A20
# Enter protected mode
# Set up Global Descriptor Table
# Set up Interrupt Descriptor Table
#
real_start:
	call clear_screen

	mov $str_copy_bpb, %si
	call print

	# duplicate/copy the BPB
	push %ds
	push %es

	# point data segment to stage1 boot sector
	xor %ax, %ax
	mov $STAGE1_SEGMENT, %ax
	mov %ax, %ds

	# copy DS:SI to ES:SI
	# skip first three bytes (jmp + nop)
	mov $3, %si

	# Set es:di to point to BPB
	mov $STAGE2_SEGMENT,%ax
	mov %ax, %es
	lea oem, %di

	# copy 34 bytes (everything between 'oem' and 'drive_number', including oem and drive_number)
	mov $reserved - oem, %cx
	rep movsb

	pop %es
	pop %ds

	# load the kernel
	mov $str_locating_kernel, %si
	call print
	m_find_file $DIRECTORY_TABLE_SEGMENT, kernel_filename

	mov $str_loading_kernel, %si
	call print
	m_read_file $FAT_SEGMENT, $KERNEL_TEMPORARY_SEGMENT, file_cluster

	# bx is now the end offset of the kernel, so that our kernel now spans
	# from KERNEL_TEMPORARY_SEGMENT:0x0 up to KERNEL_TEMPORARY_SEGMENT:%bx
	# preserve it
	push %bx

	call make_cursor_invisible
	call set_a20

	# Setup GDT
	cli
	lgdt gdtr

	# Set the PE flag (bit 0) in control register CR0.  This
	# enables the protected mode.
	smsw  %ax
	orw  $1,%ax
	lmsw  %ax

	# dont enable interrupts just yet...
	# sti

	# restore pushed %bx, i.e. the kernel size,
	# so we can use it after jumping to 32 bit
	pop %bx

	# GDT has no effect until we reload the CS register
	# offset: 0920:0000003d   jmpf 0x0008:9242
	ljmp $CODE_SEGMENT, $reload_segments + (STAGE2_SEGMENT << 4)

# we have activated protected mode, and that is in effect after
# the long jump above. this means that from now on, all executed
# code must be 32 bit compatible!
.code32
kernel_size: .word 0

reload_segments:
	xor %ax, %ax
	mov $DATA_SEGMENT, %ax

	mov %ax, %ds
	mov %ax, %es
	mov %ax, %fs
	mov %ax, %gs

	# move %bx to kernel_size before we alter the stack segment
	mov %bx, kernel_size
	mov %ax, %ss

	# TODO: we should MOST likely fix the stack pointer or stack segment,
	# because we have now changed data segment from STAGE2_SEGMENT to 0x0 (the DATA_SEGMENT
	# 	descriptor points to the GDT data segment entry which maps to 0x0000000 as base addr)

segments_reloaded:
	# move kernel to KERNEL_SEGMENT, as we have access to > 1 MB now
	# xor %ebx, %ebx
	# movw kernel_size, %bx

	# copy %ds:%si to %es:%di
	xor %esi, %esi
	mov $(KERNEL_TEMPORARY_SEGMENT << 4), %si
	xor %edi, %edi
	mov $(KERNEL_SEGMENT << 4), %edi
	# copy the amount of bytes given by "kernel_size" (a multiple of 512)
	xor %ecx, %ecx
	mov kernel_size, %cx
	rep movsb

	# do a long jump to reload code segment to the GDT selector,
	# as we are now switching from real mode to protected mode
	# We use segment selector 0x8 to select index 1, which maps to
	# memory location 0x00000000.

	xchgw %bx, %bx
	ljmp $CODE_SEGMENT, $(KERNEL_SEGMENT << 4)

.code16
forever:
	jmp forever

#
# Jumped to when we have exhausted all FAT entries,
# and we did not find our file
disk_error_not_found:
	mov $str_disk_error_not_found, %si
	call print
	# ! FALLTHRU !

#
# Jumped to when we encounter a disk error while reset, reading,
# searching for a file, and so on.
disk_error:
	mov $str_disk_error, %si
	# lea str_disk_error, %si
	call print
	# ! FALLTHRU !

reboot:
	jmp reboot
#	lea str_reboot, %si
#	call print
#	m_wait_for_keypress
#	m_reboot

make_cursor_invisible:
	movb    $1,%ah      # cursor type
	movw    $0x0100,%cx # no cursor
	int     $0x10       # BIOS call
	ret

set_a20:
  pushw  %bp
  movw  %sp,%bp
  pushw  %ax

  # write output port
set_a20_loop1:
  in  $0x64,%al
  test  $2,%al
  loopnz  set_a20_loop1
  movb  $0xd1,%al
  out  %al,$0x64

  # enable A20 address line
set_a20_loop2:
  in  $0x64,%al
  test  $2,%al
  loopnz  set_a20_loop2
  movb  $0xdf,%al
  out  %al,$0x60

set_a20_loop3:
  in  $0x64,%al
  test  $2,%al
  loopnz  set_a20_loop3

  popw  %ax
  movw  %bp,%sp
  popw  %bp
  retw

clear_screen:
	#
	# Screen segment: 0xb800
	# text attribute: (bg << 4) | (fg & 0x0F)
	#
	# black: 0x0
	# red: 0x04
	# blue: 0x01
	# green: 0x02
	# white: 0x0F
	#
	# char c = 'P';
	# uint16_t data = text_attribute << 8 | c;
	# screen[row * SCREEN_COLS + col] = data;
	#
	# SCREEN_ADDR 0xb800
	# SCREEN_COLS 80
	# SCREEN_ROWS 25
	#
	# memory address = section:disp(base, index, scale)
	# where:
    #  - base and index are the optional 32-bit base and index registers,
    #  - disp is the optional displacement,
    #  - and scale, taking the values 1, 2, 4, and 8.
    #
    #  0xb800:0x0 = first cell
    #  0xb800:0x2 = second cell
    #  0xb800:0x4 = third cell
    #
    # %ax,0xb8000(%edx,%edx,1)
    #
    # mov WORD [es:bx], ax
    movw $0xb800, %bx # base
    movw %bx, %es
    xor %bx, %bx      # offset
    xor %cx, %cx      # index

    movb $0x0F, %ah
    movb $' ', %al

    # movw %ax, %es:(%bx) === mov %ax, %es:(%bx, 2)
    #
    # Indirect addressing is severely limited in real mode.
    # Given the format disp(base, index, scale):
    #
    # ... you can only use SI, DI, BX and BP as the base,
    # ... and when using an index, the index can only be BX or BP
    # ... and then the base must be SI or DI.
    #
    # This also explains why BX and BP are called 'base register' and 'base pointer'.

    # the screen contains 25 * 80 = 2000 cells
    # 0x7CF = 1999 = 24 * 80 + 79 = the maxiumum byte
    movw $0x7CF, %cx
fill_whole_screen:
    movw %ax, %es:(%ebx,%ecx,2)
    loop fill_whole_screen
screen_is_filled:
	# fill 0th byte also
	movw %ax, %es:(%ebx,%ecx,2)

    # memory = 0xb800 << 4 | %bx
    # movw %ax, %es:(%bx)
    #movw %ax, %es:2(%bx)
    #movw %ax, %es:(%bx, 2)

    ret

.equ SCREEN_SEGMENT, 0xb800
.equ SCREEN_COLS, 80
.equ SCREEN_ROWS, 25

#
# Prints a string onto screen
#
# Example: Using mov
# mov $my_string, %si  # text
# mov $1, %ch          # row
# mov $0, %cl          # col
# call print_col_row
print_col_row:
	# preserve all registers we modify
	push %bx
	push %es
	push %ax
	push %cx

	movw $SCREEN_SEGMENT, %bx
	movw %bx, %es     # base

	# the offset is given as:
	# 2 * (row * 80 + col)
	xor %ax, %ax
	# Unsigned multiply (AX = AL * r/m8)
	mov $SCREEN_COLS, %al
	mul %ch # row * 80
	xor %ch, %ch
	add %cx, %ax     # (row * 80) + col
	# Multiply r/m8 by 2, 1 time
	sal %ax
	mov %ax, %bx      # base
	xor %cx, %cx      # index

	# Text attribute: white on black background
	xor %ax, %ax
	mov $0x0F, %ah

	# Load DS:SI in AL and increment SI
_load_character:
	lodsb

	or %al, %al           # if we have reached the end of the string, stop
	jz _no_more_characters # that is, test for the null byte at the end of the string

	# TODO: if %al is '\n', increase row and continue next iteration
	#       if %al is '\t', write four spaces up to nearest multiple of 4

	# Write the current character + text attribute onto memory location
	movw %ax, %es:(%ebx,%ecx,2)
	inc %cx

	# next character
	jmp _load_character
_no_more_characters:

	pop %cx
	pop %ax
	pop %es
	pop %bx

	ret
# End of print

# privl is two bits, because it needs to represent two and three
# .macro create_gdt_access pr, privl, ex, dc, rw, ac
#	.byte (\pr << 6 | \privl << 5 | \ex << 3 | \dc << 2 | \rw << 1 | \ac)
# .endm

.macro create_gdt_entry base, limit, access, flags
	.word \limit & 0xFFFF      # bits 0-15 of limit
	.word \base & 0xFFFF       # bits 0-15 of base
	.byte (\base >> 16) & 0xFF # bits 16-23 of base
	.byte \access
	.byte (\flags << 4) | ((\limit >> 16) & 0xF)
	.byte \base >> 24          # bits 24-31 of base
.endm

.equ GDT_ENTRY_SIZE, 8
.equ GDT_ENTRIES, 3
.equ GDT_SIZE, GDT_ENTRY_SIZE * GDT_ENTRIES - 1
.equ GDT_ADDRESS, gdt + (STAGE2_SEGMENT << 4)

gdtr:
	.word GDT_SIZE    # size of gdt in bytes minus 1
	.long GDT_ADDRESS # linear address of gdt

.align 8

# 15                 3    2     0
# +------------------+----+-----+
# |     Index        | TI | RPL | TI = Table Indicator: 0 = GDT, 1 = LDT; RPL: Request Privilege level
# +------------------+----+-----+
# | 0000000000000    |  0 | 00  | = 0x0   index 0, GDT, priv. level 0
# +------------------+----+-----+
# | 0000000000000    |  0 | 01  | = 0x1   index 0, GDT, priv. level 1
# +------------------+----+-----+
# | 0000000000000    |  0 | 10  | = 0x2   index 0, GDT, priv. level 2
# +------------------+----+-----+
# | 0000000000000    |  0 | 11  | = 0x3   index 0, GDT, priv. level 3
# +------------------+----+-----+
# | 0000000000000    |  1 | 00  | = 0x4   index 0, LDT, priv. level 0
# +------------------+----+-----+
# | 0000000000000    |  1 | 01  | = 0x5   index 0, LDT, priv. level 1
# +------------------+----+-----+
# | 0000000000000    |  1 | 10  | = 0x6   index 0, LDT, priv. level 2
# +------------------+----+-----+
# | 0000000000000    |  1 | 11  | = 0x7   index 0, LDT, priv. level 3
# +------------------+----+-----+
# | 0000000000001    |  0 | 00  | = 0x8   index 1, GDT; priv. level 0
# +------------------+----+-----+
# | 0000000000001    |  0 | 00  | = 0x9   index 1, GDT; priv. level 1
# +------------------+----+-----+
# | 0000000000001    |  0 | 00  | = 0xA   index 1, GDT; priv. level 2
# +------------------+----+-----+
# | 0000000000001    |  0 | 00  | = 0xB   index 1, GDT; priv. level 3
# +------------------+----+-----+
# | 0000000000001    |  0 | 00  | = 0xC   index 1, LDT; priv. level 0
# +------------------+----+-----+
# | 0000000000001    |  0 | 00  | = 0xD   index 1, LDT; priv. level 1
# +------------------+----+-----+
# | 0000000000001    |  0 | 00  | = 0xE   index 1, LDT; priv. level 2
# +------------------+----+-----+
# | 0000000000001    |  0 | 00  | = 0xF   index 1, LDT; priv. level 3
# +------------------+----+-----+
#
# The null descriptor is not used, so first valid segment selector is 0x8,
# which would select index 1, GDT and privilege level of 0.

gdt:
	# NULL descriptor
	.long 0
	.long 0

# Code segment entry (all 4 GB is mapped)
	create_gdt_entry 0x0, 0xffffffff, 0x9a, 0xc
	# 0x9a = 10011010:
	# Present = 1
	# Privilege level = 0 (privilege level 0 is for kernel code)
	# Executable = 1 (this is a code segment)
	# Direction = 0
	# Readable = 1
	#
	# 0xcf = 1100 (flags) 1111 (limit):
	# Granularity = 1 (for 4KB pages)
	# Size = 1 (32-bit style)

# Data segment entry (all 4 GB is mapped)
	create_gdt_entry 0x0, 0xffffffff, 0x92, 0xc
	# 0x92 = 10010010:
	# Present = 1
	# Privilege level = 0 (privilege level 0 is for kernel code)
	# Executable = 0 (this is a data segment)
	# Conforming = 0
	# Writable = 1

str_disk_error: .string "Disk error\r\n"
str_disk_error_not_found: .string "KERNEL.BIN not found\r\n"
str_reboot: .string "Press key to reboot\r\n"

str_copy_bpb: .string "Copying BPB\r\n"
str_locating_kernel: .string "Locating KERNEL.BIN on floppy\r\n"
str_loading_kernel: .string "Loading kernel\r\n"

# just to fill up some sectors
.=2048
