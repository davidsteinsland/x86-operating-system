#
# Prints a string onto screen
#
# Example: Using mov
# mov $my_string, %si
# call print
#
# Example: Using lea
# lea my_string, %si
# call print
#
print:
	# Display parameter: white on black background
	mov $0x0007, %bx

	# 0x0e is the code for this specific operation of the interrupt 0x10
	mov $0x0e, %ah

	# Load DS:SI in AL and increment SI
load_character:
	lodsb

	or %al, %al           # if we have reached the end of the string, stop
	jz no_more_characters # not-eq to zero: jump to 1 (forward)

	# print BIOS interrupt
	int $0x10

	# next character
	jmp load_character
no_more_characters:
	ret
# End of print
