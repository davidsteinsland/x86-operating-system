#
# Macros used by both bootblock.s and stage2.s
#

#
# Sets up the stack.
#
# ss: Stack segment
# sp: Stack pointer
.macro m_setup_stack ss, sp
	# disable interrupts, as we dont want to get interrupted
	# while the stack is being initialised (interrupts uses the stack)
	cli
	# setup the stack
	movw \ss, %ax
	movw %ax, %ss
	movw \sp, %sp
	sti
.endm

#
# Setup data segment
# Since we cannot guarantee that BIOS loads our boot loader
# at CS:IP 0x7C0:0x0 or 0x0:0x7C00, we should execute a long jump
# so the code segment will be a value we control.
#
# Given that STAGE1_SEGMENT equals 0x7C0 and $real_start
# is the label at where we want to jump, we jump by:
# ljmp $STAGE1_SEGMENT,$real_start
#
# This will cause the code segment to be updated with
# the proper value of 0x7C0
#
# This macro assumes that the code segment is good,
# and that the data segment and the es register should
# have the same value
.macro m_setup_segments
	mov %cs, %ax # CS = 0x7c0, because of our long jump
	# xor %ax, %ax
	mov %ax, %ds # DS = CS = 0x7c0
	mov %ax, %es # ES = CS = 0x7c0
.endm

#
# Waits for a keypress
.macro m_wait_for_keypress
	xor %ax, %ax # subfuction 0
	int $0x16    # call bios to wait for key
.endm

#
# Reboots the machine
.macro m_reboot
	# machine language to jump to FFFF:0000 (reboot)
	.byte 0xEA
	.word 0x0000
	.word 0xFFFF
.endm

#
# Functions
#

.include "functions.s"

#
# Reads one sector with logical address (LBA) AX into data
# buffer at ES:BX. This function uses interrupt 13h, subfunction ah=2.
# Modifies: %cx, %bx, %dx, %ax, %cx
#
# Symbols used:
# - physical_sectors_per_track
# - heads_per_cylinder
# - drive_number
# - disk_error
read_sector:
	# Set try count = 0
	xor %cx, %cx

read_sector_loop:
	push %ax # Store logical block
	push %cx # Store try number
	push %bx # Store data buffer offset

#
# Sector   = (LBA mod SectorsPerTrack) + 1
# Cylinder = (LBA / SectorsPerTrack) / NumHeads
# Head     = (LBA / SectorsPerTrack) mod NumHeads
#

	# Get sectors per track
	mov physical_sectors_per_track, %bx
	xor %dx, %dx
	# Divide (dx:ax/bx to ax,dx)
	# Quotient (ax) =  LBA / SectorsPerTrack
	# Remainder (dx) = LBA mod SectorsPerTrack
	div %bx
	# Add 1 to remainder, since sector
	inc %dx
	# Store result in cl for int 13h call.
	mov %dl, %cl

	# Get number of heads
	mov heads_per_cylinder, %bx
	xor %dx, %dx
	# Divide (dx:ax/bx to ax,dx)
	# Quotient (ax) = Cylinder
	# Remainder (dx) = head
	div %bx
	# ch = cylinder
	mov %al, %ch
	# dh = head number
	xchg %dh, %dl

#
# BIOS call "INT 0x13 Function 0x2" to read sectors from disk into memory
#	Call with
#			%ah = 0x2
#			%al = number of sectors
#			%ch = cylinder
#			%cl = sector (bits 6-7 are high bits of "cylinder")
#			%dh = head
#			%dl = drive (0x80 for hard disk, 0x0 for floppy disk)
#			%es:%bx = segment:offset of buffer
#	Return:
#			%al = 0x0 on success; err code on failure
#
	mov $2, %ah            # function 2
	mov $1, %al            # read 1 sector
	mov drive_number, %dl  # drive number
	pop %bx                # Restore data buffer offset.
	int $0x13

	cmpb $0, %ah      # check if read was successful
	jne disk_error_try_again

	# On success, return to caller.
	pop %cx # Discard try number
	pop %ax # Get logical block from stack

	ret

str_disk_error_trying_again: .string "Error, but trying again\r\n"

disk_error_try_again:
	# Get try number
	pop %cx
	# Next try
	inc %cx
	# Stop at 4 tries
	cmp $4, %cx
	je disk_error

	push %bx
	mov $str_disk_error_trying_again, %si
	call print
	pop %bx

	# Reset the disk system:
	xor %ax, %ax
	int $0x13

	# Get logical block from stack and retry.
	pop %ax
	jmp read_sector_loop

#
# Disk Macros
#

# Copies the BIOS Parameter Block from memory to another
# memory location (stage2 copies BPB from bootblock)
.macro m_copy_bpb

.endm

#
# Resets the disk drive given by first argument
#
# drive_no: The driver number
# disk_error_label: The label at which to jump to, on error
.macro m_reset_disk drive_no, disk_error_label
	mov \drive_no, %dl # drive to reset
	xor %ax, %ax           # function 0
	int $0x13              # call interrupt 0x13
	jc \disk_error_label   # in case of reset error, jump to given label
.endm

#
# Searches for a file in the root directory table
#
# Symbols used but defined elsewhere:
#
# ... that is used for reading:
# - root_directory_entries (defined in BPB)
# - bytes_per_logical_sector (defined in BPB)
# - number_of_fats (defined in BPB)
# - reserved_logical_sectors (defined in BPB)
# - logical_sectors_per_fat (defined in BPB)
# - hidden_sectors_count (defined in BPB)
#
# ... and the following symbols are used for writing:
# - root_dir_size (must be defined to be a word)
# - root_dir_offset (must be defined to be a word)
# - file_cluster (must be defined to be a word)
#
# ... and the following symbols are used for jumping:
# - disk_error_not_found, jumped to when file not found in root directory
#
# The size (in sectors) of the root directory table is given by:
# size = (FAT_ENTRY_SIZE * root_directory_entries) / bytes_per_logical_sector
#      where FAT_ENTRY_SIZE is defined to be 32
#
# The offset (in sectors) of the root directory table is given by:
# offset = number_of_fats * logical_sectors_per_fat + hidden_sectors_count + reserved_logical_sectors
#
# Arguments:
# directory_table_segment: The segment at where to load the directory table into
# filename: Pointer to a memory location that contains a null-byte terminated string
#
.macro m_find_file directory_table_segment, filename
	# DX:AX = AX * r/m16
	mov $32, %ax
	xor %dx, %dx
	mov root_directory_entries, %cx

	# multiply "root_directory_entries" with the %ax register
	# higher part of result stored in: 	DX
	# lower part of result stored in: 	AX
	mul %cx

	# Divide (dx:ax,sectsize) to (ax,dx)
	# dividend 				DX:AX
	# remainder stored in: 	DX
	# quotient stored in: 	AX
	mov bytes_per_logical_sector, %cx
	# DX:AX by r/m16, with result stored in AX = Quotient, DX = Remainder.
	div %cx
	mov %ax, %cx
	mov %ax, root_dir_size

	mov \directory_table_segment, %ax
	mov %ax, %es

	# AX = AL * r/m8
	xor %ax, %ax
	mov number_of_fats, %al
	mov logical_sectors_per_fat, %bx
	mul %bx
	add hidden_sectors_count, %ax
	add reserved_logical_sectors, %ax
	mov %ax, root_dir_offset

	# LBA = %ax
	# segment = %es = \directory_table_segment
	# offset = %bx = 0
	# number of sectors = cx
	read_next_root_dir:
		push %cx
		push %ax
		# offset = 0
		xor %bx, %bx
		call read_sector

	check_root_dir_entry:
		# Directory entries filenames are 11 bytes.
		mov $11, %cx
		# es:di = Directory entry address
		# es = $DIRECTORY_TABLE_SEGMENT
		mov %bx, %di
		# ds = should already be set up
		# ds:si = Address of filename we are looking for.
		lea \filename, %si
		# Repeat while not zero (until the count register (CX) or the zero flag (ZF) matches a tested condition):
		# Compares byte at address DS:SI with byte at address ES:DI and sets the status flags accordingly
		repz cmpsb
		je file_found_in_entry

		# Move to next entry. Entries are 32 bytes.
		add $32, %bx
		# Have we moved out of the sector yet?
		cmp bytes_per_logical_sector, %bx
		# If not, try next directory entry.
		jne check_root_dir_entry

		pop %ax
		pop %cx
		inc %ax

		loopnz read_next_root_dir
		jmp disk_error_not_found

	file_found_in_entry:
	    # The directory entry stores the first cluster number of the file
	    # at byte 26 (0x1a). BX is still pointing to the address of the start
	    # of the directory entry, so we will go from there.
	    # Read cluster number from memory:
	    # es + bx + 26
	    # section:disp(base, index, scale) ===> section:[base + index*scale + disp]  (intel)
	    # 0x07E0:0x96 + 26
	    mov %es:26(%bx), %ax
	    mov %ax, file_cluster
.endm

#
# Loads the FAT into memory
#
# The size (in sectors) of the FAT is given by:
# size = logical_sectors_per_fat
#
# The offset (in sectors) of the FAT is given by:
# offset = hidden_sectors_count + reserved_logical_sectors
#
.macro m_read_fat fat_segment
	mov \fat_segment, %ax
	mov %ax, %es
	# LBA = fat_offset = reserved_logical_sectors + hidden_sectors_count
	mov reserved_logical_sectors, %ax
	add hidden_sectors_count, %ax

	mov logical_sectors_per_fat, %cx
	xor %bx, %bx

	read_next_fat_sector:
		push %cx
		push %ax
		call read_sector
		pop %ax
		pop %cx
		inc %ax
		add bytes_per_logical_sector, %bx
		loopnz read_next_fat_sector
.endm

#
# Reads a file from the disk into memory
#
# Arguments:
# segment: Segment at which to place the file
# cluster: First cluster of the file
#
# The offset (in sectors) of the file is given by:
# offset = ((cluster - 2) * logical_sectors_per_cluster) + root_dir_size + root_dir_offset
#        where root_dir_size is the size in sectors of the root directory and
#        root_dir_offset is the offset in bytes of the root directory
#
.macro m_read_file fat_segment, segment, cluster
	mov \segment, %ax
	mov %ax, %es
	xor %bx, %bx
	mov \cluster, %cx

	read_file_next_sector:
		mov %cx, %ax
		add root_dir_size, %ax
		add root_dir_offset, %ax
		sub $2, %ax

		push %cx
		call read_sector
		pop %cx
		add bytes_per_logical_sector, %bx

		# Make DS:SI point to FAT table
		push %ds
		mov \fat_segment, %dx
		mov %dx, %ds

		# Make SI point to the current FAT entry
		# (offset is entry value * 1.5 bytes)
		mov %cx, %si
		mov %cx, %dx
		shr %dx
		add %dx, %si

		# Read the FAT entry from memory
		mov %ds:(%si), %dx
		# See which way to shift, see if current cluster if odd
		test $1, %cx
		jnz read_next_cluster_odd
		and $0xfff, %dx
		jmp read_next_file_cluster_done

	read_next_cluster_odd:
		shr $4, %dx

	read_next_file_cluster_done:
		pop %ds
		mov %dx, %cx

		cmp $0xff8, %cx # if 0xff8, then we have reached end-of-file
		jl read_file_next_sector
.endm
