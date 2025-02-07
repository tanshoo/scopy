# Scopy

This x86-64 Linux program, implemented in Assembly, reads an input file byte by byte and writes data to an output file. For each byte matching the ASCII code for the letter `s` or `S`, the program writes that byte directly to the output file. For any run of bytes that contain no `s` or `S`, the program writes the length (mod 65536) of that run as a 16-bit little-endian integer.

All file operations and system calls check for errors before proceeding. If an error occurs at any point, the program closes all files and exits with return code 1.

An additional goal was also to minimize the `.text` section - this implementation is only 379 bytes.

This project was created as part of the 2022/23 Computer Architecture and Operating Systems course at University of Warsaw.

## Usage
```sh
./scopy in_file out_file
```
- `in_file` - path to the input file
- `out_file` - path to the output file (it must *not* exist, as it will be created by the program)

## Compilation
```sh
nasm -f elf64 -w+all -w+error -o scopy.o scopy.asm
ld --fatal-warnings -o scopy scopy.o
```
or just:
```
make
```

## Example
```sh
# Delete my.out (or choose a different out_file) if it already exists
./scopy example1.in my.out
diff example1.out my.out # no differences
```
The input/output files can be viewed using `hexdump -C`.