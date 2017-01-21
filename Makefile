CC=gcc
AS=as
LD=ld
OBJCOPY=objcopy

CCOPTS=-Os -O0 -m32 -march=i386 -ffreestanding -Wall -Werror -I.
LDOPTS=-static -nostdlib --nmagic -melf_i386

BASE_FLOPPY=empty_floppy.img
IMAGE=my_os.img

.PHONY: all clean qemu bochs disassemble

all:
	docker run --rm -v $(shell pwd):/usr/src -w /usr/src gcc:4.9 make $(IMAGE)

	cp stage2.bin dist/SECOND.BIN
	cp kernel.bin dist/KERNEL.BIN

disassemble:
	gobjdump -b binary -m i386 -D $(IMAGE)

$(IMAGE): bootblock.bin stage2.bin kernel.bin
	cp $(BASE_FLOPPY) $(IMAGE)

	# copy bootblock.bin, that is 512 bytes, into the first sector of the real floppy "my_os.img"
	# 1. create empty_floppy.img using OSX or similar
	# 2. copy empty_floppy.img to my_os.img
	# 3. compile bootblock, copy BPB from floppy into bootblock, then copy
	#    bootblock into my_os.img
	# 4. Go to #2 whenever a "new" floppy base image is needed
	# empty_floppy.img should never be modified.
	dd if=bootblock.bin of=$(IMAGE) bs=512 count=1 conv=notrunc

bootblock.bin: bootblock.out
	$(OBJCOPY) -O binary -j .text -j .data -j .rodata -j .bss $< $@

	# Copy 51 bytes (starting from 11th byte) from empty_floppy.img
	# into bootblock.bin, effectively replacing the BIOS Parameter Block
	# in bootblock.bin with the one from empty_floppy.img (which is a "real" floppy)
	dd if=$(BASE_FLOPPY) of=$@ bs=1 skip=11 seek=11 count=51 conv=notrunc

%.bin: %.out
	# strips off any headers and leaves us with a flat binary
	#$(OBJCOPY) -O binary -j .text $< $@
	#$(OBJCOPY) -O binary $< $@
	$(OBJCOPY) -O binary -j .text -j .data -j .rodata -j .bss $< $@
	#cp $< $@

bootblock.out: bootblock.o
	$(LD) -melf_i386 -Ttext 0x0 -o $@ $<
stage2.out: stage2.o
	$(LD) -melf_i386 -Ttext 0x0 -o $@ $<
kernel.out: kernel_entry.o kernel.o kernel_helpers.o gdt.o idt.o screen.o memory.o string.o io.o
	$(LD) -melf_i386 -Tkernel.ld -o $@ $^

bochs:
	~/bin/bochs/bin/bochs -f .bochsrc

qemu:
	qemu-system-i386 -fda $(IMAGE) -boot a -monitor stdio

# Assemble object files
%.o: %.s
	$(AS) --32 -o $@ $<
%.o: %.c
	$(CC) $(CCOPTS) -c -o $@ $<

%.s:%.c
	$(CC) $(CCOPTS) -S $<

clean:
	-$(RM) *.o
	-$(RM) *.out
	-$(RM) bootblock.bin
	-$(RM) bootblock.bin
	-$(RM) stage2.bin
	-$(RM) kernel.bin
	# -$(RM) my_os.img
