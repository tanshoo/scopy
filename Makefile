all:
	nasm -f elf64 -w+all -w+error -o scopy.o scopy.asm
	ld --fatal-warnings -o scopy scopy.o