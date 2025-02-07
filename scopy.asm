global _start

SYS_READ equ 0
SYS_WRITE equ 1
SYS_OPEN equ 2
SYS_CLOSE equ 3
SYS_EXIT equ 60

O_RDONLY equ 0
O_WRONLY equ 1
O_CREAT equ 0q100
O_EXCL equ 0q200

write_buf_size equ 16384 ; buffer size is equal to block size
read_buf_size equ 16384

section .bss
    align 4, resb 1
    write_buffer: resb write_buf_size;  buffer size is 16kB

    align 4, resb 1
    read_buffer: resb read_buf_size
    
section .data
    ; file descriptors
    align 4
    in_file: dq -1 ; if < 0, then file is not open
    
    align 4
    out_file: dq -1

    align 4
    return_code: dd 1


section .text

; aligns labels to speed up execution time
; albl == aligned_label
%macro albl 1
    align 2
    %1
%endmacro

; helps reduce .text section size when used instead of mov
; for constants below 2^8
; push/pop takes 3 bytes, while mov takes >= 5
; equal to mov %1, %2
; lmov == lighter_mov
; doesn't affect any flags
%macro lmov 2
    push %2
    pop %1
%endmacro

; check if sys_open syscall for file %1 was successful
; if not, then close files and return
%macro sys_open_check 1
    test rax, rax ; if rax < 0, sys_open failed
    js _prep_fail

    mov qword [%1], rax ; saves %1 file descriptor
%endmacro

_prep_fail:
    jmp _start.close_files

_start:
    ; **** checks number of arguments & prepares files before read/write loop ****

    ;check number of arguments
    cmp qword [rsp], 3
    jne _prep_fail


    ;open in_file in read-only mode
    lmov rax, SYS_OPEN
    mov rdi, qword [rsp+16]
    xor rsi, rsi ; rsi == O_RDONLY
    syscall

    ; check if in_file was successfully opened
    sys_open_check in_file


    ;create file out_file in write-only mode
    lmov rax, SYS_OPEN
    mov rdi, qword [rsp+24]
    mov rsi, 0q301 ; O_CREAT | O_EXCL | O_WRONLY
    mov rdx, 0q644 ; -rw-r--r-- permissions
    syscall

    ; check if out_file was successfully created
    sys_open_check out_file


    ; **** register meanings inside of read_loop (called functions 
    ; included) unless specified otherwise **************************

    ;rcx - read_buffer iterator (NON relative iterator)
    ;rcx = read_buffer (address) + relative position in read_buffer
    ;r10 = read_buffer (address) + number of read bytes = 
    ; (address of the last byte of read buffer after sys_read)

    xor r9, r9  ; write_buffer iterator (relative iterator)
    
    xor r8, r8  ; non-s character counter (later on referred to as just counter), 
                ; 17th bit is set if there are any non-s characters
                ; if there were none so far, r8 == 0
    ; ***************************************************************
 

    %macro add_counter_to_buffer 0
        ; add least-significant byte of the non-s counter to buffer
        call .add_byte_to_buffer
        ; add most-significant byte of the non-s counter to buffer
        call .add_byte_to_buffer
    %endmacro

    albl .read_loop: 
        mov r10, read_buffer

        xor rax, rax ; rax = SYS_READ
        mov rdi, qword [in_file]
        mov rsi, r10 ; rsi = read_buffer
        mov rdx, read_buf_size
        syscall
        
        ; check if the read was successful
        test rax, rax
        jz .nothing_more_to_read ; eof
        js .close_files ; read fail
        
        mov rcx, r10 ; rcx = read_buffer
        add r10, rax ; r10 = read_buffer + number of read bytes

            albl .write_loop: ; do(...) while (rcx < r10)
                cmp byte [rcx], 's'
                je .is_s
                cmp byte [rcx], 'S'
                je .is_s
        
                ; not s
                inc r8d
                bts r8d, 16 ; sets 17th bit 
                jmp .write_loop_end

                albl .is_s:
                    ; add the counter (if it's not equal 0) to buffer    
                    test r8d, r8d
                    jz .add_s
                        add_counter_to_buffer

                    albl .add_s: ; adds s/S to buffer
                        mov r8b, byte [rcx]
                        call .add_byte_to_buffer
                        xor r8, r8 ; clears the counter
                        
            albl .write_loop_end:    
                inc rcx
                cmp rcx, r10
                jl .write_loop

    jmp .read_loop


    albl .nothing_more_to_read:
        test r8d, r8d ; check if counter is non-empty
        jz .empty_counter ; counter is empty
            add_counter_to_buffer
        albl .empty_counter:

            ; check if there is anything left in the buffer
            test r9, r9
            jz .empty_buffer
                call .write_to_file
            albl .empty_buffer:
                mov qword [return_code], 0 ; everything was correct so far
                jmp .close_files


;;;;;;;;;;;;;; FUNCTIONS ;;;;;;;;;;;;;;;;

    ; writes the buffer to the out_file
    ; buffer cannot be empty

    %macro WRITE_FUN 0
    albl .write_to_file:    

        push rcx ; saves rcx to keep it from being clobbered
        push r8 ; in write_to_file, r8 will be used as "already written bytes" counter
        xor r8, r8    

        albl .write_syscall:
            lmov rax, SYS_WRITE
            mov rdi, qword [out_file]
            mov rsi, write_buffer
            add rsi, r8
            mov rdx, r9
            syscall

        ; check if the write was successful
        test rax, rax 
        js .close_files ; if rax < 0, sys_write failed

        add r8, rax ; move forward in the buffer
        sub r9, rax ; r9 = how many characters left
        jnz .write_syscall

        pop r8
        pop rcx
        xor r9, r9 ; clear write_buffer iterator
    %endmacro 

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    ; adds r8b byte to buffer, checks for possible buffer overflow
    ; and shifts in next one
    albl .add_byte_to_buffer:
        mov byte [write_buffer + r9], r8b
        inc r9
        cmp r9, write_buf_size
        jl .buffer_not_full
            WRITE_FUN
        albl .buffer_not_full:
            shr r8d, 8 ; move next byte to r8b
            ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; **** close files and return ****

; closes %1 file
%macro close 1
    ; pass arguments needed by close_file_fun and call it
    lea r8, qword [%1] ; r8 keeps address of %1 file id
    call .close_file_fun
%endmacro

    albl .close_files:
        lea r9, [return_code]
        close out_file
        close in_file

        mov rdi, qword [r9] ; = mov rdi, qword [return_code]
        lmov rax, SYS_EXIT
        syscall

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    ; attempts to close a file
    ; before calling, address of file descriptor must be passed to r8

    albl .close_file_fun:
        ; check if file is open (file descriptor >= 0)
        cmp qword [r8], 0
        jl .close_failed

            lmov rax, SYS_CLOSE
            mov rdi, qword [r8]
            syscall
        ; check if sys_close was successful
        test rax, rax
        jnz .close_failed
            ; successful sys_close:
            mov qword [r8], -1 ; file descriptor set to < 0
            ; return code doesn't change
            ret
        albl .close_failed:
            ; file status doesn't change
            mov byte [r9], 1 ; updated return code: [return_code] = 1
            ret