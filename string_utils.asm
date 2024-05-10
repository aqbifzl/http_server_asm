section .data

SYS_WRITE equ 1
STDOUT equ 1

ZERO_CHAR equ 48
INT_TO_STRING_MAX_BUFFER_INDEX equ 9

section .text
global print_prompt
global str_len
global number_to_string
print_prompt: ; (rdi string_address, rsi length) -> void
  push rdi
  push rsi
  mov rax, SYS_WRITE
  mov rdi, STDOUT
  mov rsi, [rsp+8] ; address of string
  mov rdx, [rsp] ; length
  syscall
  pop rsi
  pop rdi
  ret

str_len: ; (rdi string_address) -> rax length
  xor rax, rax

  loop_start:
  lea r9, [rdi+rax]
  mov bl, [r9]
  inc rax
  cmp bl, 0
  jnz loop_start

  ret

number_to_string: ; (rdi number, rsi buffer_address) -> rax length
  push rbp
  mov rbp, rsp
  sub rsp, 16

  mov qword [rbp-8], rdi ; save number
  mov qword [rbp-16], rsi ; save buffer address

  cmp rdi, 0
  je handle_zero ; if number is 0 return 0

  mov rax, 0 ; zero counter
  clean_loop:
  mov byte [rsi + rax], 0
  inc rax
  cmp rax, INT_TO_STRING_MAX_BUFFER_INDEX
  jne clean_loop

  ; calculations

  mov r14, qword [rbp-16] ; buffer address
  mov r15, INT_TO_STRING_MAX_BUFFER_INDEX ; set counter to the last index

  calc_loop_start:
  mov edi, dword [rbp-8] ; save number to edi
  mov eax, edi
  xor edx, edx ; zero upper half

  mov ebx, 10
  div ebx ; divide by 10
  ; result is stored in eax and remainder in edx

  mov r13d, eax ; save result of division to r13d

  mov r12, INT_TO_STRING_MAX_BUFFER_INDEX
  sub r12, r15 ; get the offset for the buffer address
  
  add dl, ZERO_CHAR ; add 0 character value to remainer
  mov byte [r14+r12], dl ; move char to the buffer

  mov dword [rbp-8], r13d ; save previous division result to perform number /= 10
  
  dec r15 ; decrement counter

  mov rdi, qword [rbp-8] ; save number
  cmp rdi, 0 ; if number is zero, it means it finished
  je break_loop
  jmp calc_loop_start
  
  break_loop:
  mov r12, INT_TO_STRING_MAX_BUFFER_INDEX
  sub r12, r15 ; get the offset for the buffer address  

  ; reverse the loop
  sub rsp, 10
  mov r9, 0 ; counter of non 0 values
  mov rax, INT_TO_STRING_MAX_BUFFER_INDEX+1 ; index counter
  ; TODO it should be done without this loop
  reverse_loop_start:
  dec rax ; dec index counter

  mov r8b, byte [r14+rax] ; get value

  cmp r8b, 0
  je reverse_loop_start
  ; copy value if non zero

  lea rcx, [rsp]
  add rcx, r9 ; get address of the next address to write
  inc r9 ; inc index counter

  mov byte [rcx], r8b

  cmp rax, 0
  je reverse_loop_break
  jmp reverse_loop_start

  reverse_loop_break:

  ; TODO this code is a mess, it should at least be done with rbx

  mov rcx, 10 ; copy the whole buffer
  lea rsi, [rsp] ; new value is in buffer pushed before
  mov rdi, qword [rbp-16] ; real buffer address
  cld
  
  rep movsb

  add rsp, 10
  mov rax, r12

  jmp end
  handle_zero:
  mov rsi, qword [rbp-16] ; buffer address
  mov byte [rsi], ZERO_CHAR
  mov rax, 1 ; len = 1

  end:
  add rsp, 16
  pop rbp
  ret
