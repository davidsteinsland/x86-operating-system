# Assembly functions for our kernel
.text

# uint32_t get_gdt(gdtr_t*)
# Returns the address of the GDTR structure
# Inline assembly alternative:
#
#    gdtr_t gdt;
#    asm("sgdtl %0" : "=m"(gdt));
#
.globl get_gdt
get_gdt:
	push %ebp
	mov %esp, %ebp

	# preserve %eax, although not neccessary
	push %eax
	mov 8(%ebp), %eax

	sgdt (%eax)

	# restore %eax, although not neccessary
	pop %eax

	mov %ebp, %esp
	pop %ebp

	ret

# void set_gdt(gdtr_t*, uint16_t cs_selector, uint16_t ds_selector)
.globl set_gdt
set_gdt:
	push %ebp
	mov %esp, %ebp

	# preserve %eax, although not neccessary
	push %eax
	mov 8(%ebp), %eax

	lgdt (%eax)

	mov 16(%ebp), %eax
	mov %eax, %ds
	mov %eax, %es
	mov %eax, %fs
	mov %eax, %gs
	mov %eax, %ss

	pop %eax

	mov %ebp, %esp
	pop %ebp

	# reload %cs register by doing a far return
	push 16(%ebp)
	push $gdt_is_set
	retf

gdt_is_set:
	ret

.globl get_eax
get_eax:
	ret

.globl get_ebx
get_ebx:
	mov %ebx, %eax
	ret

.globl get_ecx
get_ecx:
	mov %ecx, %eax
	ret

.globl get_edx
get_edx:
	mov %edx, %eax
	ret
