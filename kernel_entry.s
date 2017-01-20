# This file is for the Kernel entry, as the stage2 bootloader will jump
# to the first byte in the kernel location (because we dont link the kernel with stage2,
# stage2 does not know about any symbols like "kernel_main")
.text
.globl _start
_start:
	call kernel_main
	# We should *never* end up here,
	# but if we do, we'll limbo forever in the void!
1:
	hlt
	jmp 1b
