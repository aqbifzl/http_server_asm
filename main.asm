section .data

SYS_EXIT equ 60
SYS_SOCKET equ 41
SYS_SETSOCKOPT equ 54
SYS_BIND equ 49
SYS_LISTEN equ 50
SYS_CLOSE equ 3
SYS_WRITE equ 1
SYS_ACCEPT equ 43
SYS_POLL equ 7

EXIT_STATUS equ 0
SERVER_PORT equ 20500 ; 5200 = htons(5200) = 20500

MAX_CLIENTS equ 10
POLLFD_SIZE equ 8

POLLIN equ	1		;/* There is data to read.  */
POLLPRI equ	2		;/* There is urgent data to read.  */

POLLFDS_TOTAL_SIZE equ MAX_CLIENTS * POLLFD_SIZE

response_template db "HTTP/1.1 200 OK",0x0D,0x0A,"Host: 127.0.0.1",0x0D,0x0A,"Connection: close",0x0D,0x0A,"Content-Length: ", 0
starting_info db "starting server...", 0x0A, 0
response_msg db "this is a test response", 0

CRLFCRLF db 0x0D,0x0A,0x0D,0x0A

section .text
global _start
extern print_prompt ; (rdi string_address, rsi length) -> void
extern str_len ; (rdi string_address) -> rax length
extern number_to_string: ; (rdi number, rsi buffer_address) -> rax length

create_tcp_socket: ; (void) -> rax socket_fd
  mov rax, SYS_SOCKET
  mov rdi, 2 ; domain = 2 = internet protocol family
  mov rsi, 1 ; type = 1 = sock stream aka TCP
  mov rdx, 0 ; protocol = 0
  syscall
  ret

set_socket_opt: ; (rdi socket) -> void
  mov rdx, 1
  push rdx

  mov rax, SYS_SETSOCKOPT
  ; mov rdi, rdi ; socket is already in rdi
  mov rsi, 1 ; SOL_SOCKET level
  mov rdx, 2 ; SO_REUSEADDR	= 2
  lea r10, [rsp] ; value = 1
  mov r8, 8
  syscall
  pop rdx
  ret

bind: ; (rdi socket_fd) -> void
  ; sockaddr (16 bytes in total)
  ; sin_family (2)
  ; sin_port (2)
  ; sin_addr (4)
  ; [padding] - (rest)

  mov word [rsp-16], 2 ; sin_family = AF_INET = 2
  mov word [rsp-14], SERVER_PORT ; sin_port
  mov dword [rsp-12], 0 ; sin_adr = htonl(INADDR_ANY) = 0

  lea rdx, [rsp-16]
  
  mov rax, SYS_BIND
  ; mov rdi, rdi ; socket_fd is already set
  mov rsi, rdx ; struct address
  mov rdx, 16 ; sockaddr is 16 bytes
  syscall
  ret

listen: ; (rdi socket_fd) -> void
  mov rax, SYS_LISTEN
  ; mov rdi, rdi ; socket_fd is already set
  mov rsi, 5 ; max queue length
  syscall
  ret

close_connection: ; (rdi socket_fd) -> void
  mov rax, SYS_CLOSE
  ; mov rdi, rdi ; socket_fd is already set
  syscall
  ret

handle_client_and_close: ; (rdi connection_fd) -> void
  push rbp
  mov rbp, rsp
  sub rsp, 1024 ; buffer for http response
  sub rsp, 8 ; for connection fd
  sub rsp, 8 ; for message length
  sub rsp, 8 ; for http res length

  mov [rbp-1032], rdi ; connection fd

  lea rdi, [response_msg]
  call str_len
  mov [rbp-1040], rax ; save message length
  dec qword [rbp-1040] ; ignore null terminator 
  
  ; TODO load response from file
  lea rdi, [response_msg] ; message address
  mov rsi, [rbp-1040] ; message length
  lea rdx, [rbp-1024] ; http response buffer
  mov rcx, 1024 ; buffer length

  call create_http_response_with_msg
  mov [rbp-1048], rax ; move http res length to stack

  mov rax, SYS_WRITE
  mov rdi, [rbp-1032] ; connection fd
  lea rsi, [rbp-1024] ; res buffer address
  mov rdx, qword [rbp-1048] ; http response real size
  syscall

  mov rdi, [rbp-1032] ; close connection fd
  call close_connection

  add rsp, 1024 
  add rsp, 8 
  add rsp, 8 
  add rsp, 8 
  pop rbp
  ret

; int fd;			/* File descriptor to poll.  */
; short int events;		/* Types of events poller cares about.  */
; short int revents;		/* Types of events that actually occurred.  */

get_pollfd_by_index: ; (rdi pollfds_address, rsi index) -> rax pollfd_address
  lea rax, [rdi+rsi*POLLFD_SIZE]
  ret

get_pollfd_revents: ; (rdi pollfds_address, rsi index) -> rax revents_address
  call get_pollfd_by_index
  add rax, 6
  ret

get_pollfd_events: ; (rdi pollfds_address, rsi index) -> rax events_address
  call get_pollfd_by_index
  add rax, 4
  ret

get_pollfd_fd: ; (rdi address of pollfds, rsi index) -> rax fd_address
  call get_pollfd_by_index
  ret

; TODO poll is bad, use epoll
handle_clients_with_poll: ; (rdi server_fd) -> never
  push rbp
  mov rbp, rsp
  sub rsp, POLLFDS_TOTAL_SIZE
  sub rsp, 48
  ; rbp-POLLFDS_TOTAL_SIZE-8 - server fd
  ; rbp-POLLFDS_TOTAL_SIZE-16 - client counter
  ; rbp-POLLFDS_TOTAL_SIZE-32 - unused buffer for client sockaddr
  ; rbp-POLLFDS_TOTAL_SIZE-40 - buffer for current pollfd address
  ; rbp-POLLFDS_TOTAL_SIZE-48 - buffer for loop index for data handling loop

  mov [rbp-POLLFDS_TOTAL_SIZE-8], rdi ; save server fd
  mov qword [rbp-POLLFDS_TOTAL_SIZE-16], 0 ; client counter

  mov rcx, POLLFDS_TOTAL_SIZE ; how many times to repeat
  mov rax, 0 ; zero it
  lea rdi, [rbp-POLLFDS_TOTAL_SIZE] ; buffer address
  rep stosb

  lea rdi, [rbp-POLLFDS_TOTAL_SIZE] ; pollfds address
  mov rsi, 0 ; server has index = 0
  call get_pollfd_fd

  mov r8, qword [rbp-POLLFDS_TOTAL_SIZE-8] ; move server fd
  mov qword [rax], r8

  call get_pollfd_events
  mov bx, POLLIN
  or bx, POLLPRI ; set POLLIN | POLLPRI
  mov word [rax], bx

  main_loop:

  mov rax, SYS_POLL
  lea rdi, [rbp-POLLFDS_TOTAL_SIZE] ; set pollfds address
  mov rsi, MAX_CLIENTS ; set pollfds size
  mov rdx, 0 ; timeout = 0
  syscall

  cmp rax, 0 
  jg handle_poll_event ; check for poll events 
  jmp main_loop

  handle_poll_event:

  handle_new_connection:

  mov rax, qword [rbp-POLLFDS_TOTAL_SIZE-8] ; server fd
  and word [rax], POLLIN ; check for POLLIN event
  cmp word [rax], 0
  je handle_requests ; jump to request handling if it's 0 there's no new connection

  ; handle new connection

  mov rcx, 16
  push rcx

  mov rax, SYS_ACCEPT
  mov rdi, qword [rbp-POLLFDS_TOTAL_SIZE-8] ; server fd
  lea rsi, [rbp-POLLFDS_TOTAL_SIZE-32] ; client data buffer, it's unused
  lea rdx, [rsp] ; size of this struct = 16
  syscall

  pop rcx

  mov r15, rax ; connection fd

  ; TODO handle return value

  ; find unused fd in pollfds
  
  mov r14, 1 ; first index, skip server
  unused_fd_loop_start:
   
  lea rdi, [rbp-POLLFDS_TOTAL_SIZE] ; pollfds address
  mov rsi, r14 ; index
  call get_pollfd_fd
  
  cmp qword [rax], 0
  jne skip_assignment ; if fd is set it's not unused
  
  mov qword [rax], r15 ; connection fd

  lea rdi, [rbp-POLLFDS_TOTAL_SIZE] ; mov pollfds address
  mov rsi, r14 ; set current index
  call get_pollfd_events

  mov bx, POLLIN
  or bx, POLLPRI
  mov word [rax], bx ; set events to POLLIN | POLLPRI 

  inc qword [rbp-POLLFDS_TOTAL_SIZE-16] ; inc client counter
  jmp handle_requests ; after assigning jump to data handling

  skip_assignment:

  inc r14
  cmp r14, MAX_CLIENTS ; if next iteration is MAX_CLIENTS which is invalid index, you should break
  je handle_requests
  jmp unused_fd_loop_start

  handle_requests:


  mov qword [rbp-POLLFDS_TOTAL_SIZE-48], 1 ; index counter
  mov qword [rbp-POLLFDS_TOTAL_SIZE-40], 0 ; zero buffer holding current pollfd's address
  clients_to_handle_loop_start:

  lea rdi, [rbp-POLLFDS_TOTAL_SIZE] ; set pollfds address
  mov rsi, qword [rbp-POLLFDS_TOTAL_SIZE-48] ; set index
  call get_pollfd_fd
  mov qword [rbp-POLLFDS_TOTAL_SIZE-40], rax ; save current pollfd

  mov rax, qword [rbp-POLLFDS_TOTAL_SIZE-40] ; get address of pollfd
  mov edi, dword [rax]

  cmp edi, 0
  jle end_of_iteration ; skip not used fds

  mov rax, qword [rbp-POLLFDS_TOTAL_SIZE-40] ; get address of pollfd
  mov di, word [rax+6] ; get revents property

  and di, POLLIN ; check for pending POLLIN events from fd
  cmp di, 0
  je end_of_iteration ; skip if there's no event

  mov rax, qword [rbp-POLLFDS_TOTAL_SIZE-40] ; get address of pollfd
  mov ebx, dword [rax] ; get fd property

  xor rdi, rdi ; zero rdi
  mov edi, ebx ; move fd value after
  call handle_client_and_close

  mov rbx, qword [rbp-POLLFDS_TOTAL_SIZE-40] ; get address of pollfd

  mov rcx, POLLFD_SIZE
  mov rax, 0 ; zero it
  mov rdi, rbx ; address of pollfd
  rep stosb

  end_of_iteration:
  inc qword [rbp-POLLFDS_TOTAL_SIZE-48] ; inc counter

  cmp qword [rbp-POLLFDS_TOTAL_SIZE-48], MAX_CLIENTS ; break if the next iteration index is MAX_CLIENTS
  je main_loop ; jump to start if all clients are iterated

  jmp clients_to_handle_loop_start

  jmp main_loop
   
  ; this place is unreachable
  sub rsp, 48
  sub rsp, POLLFDS_TOTAL_SIZE
  pop rbp
  ret

create_http_response_with_msg: ; (rdi msg_address, rsi msg_length, rdx http_res_buffer_address, rcx res_buffer_length) -> rax http_response_length
  push rbp
  mov rbp, rsp
  sub rsp, 50
  mov [rbp-8], rdi ; msg address
  mov [rbp-16], rsi ; msg length
  mov [rbp-24], rdx ; buffer address
  mov [rbp-32], rcx ; buffer size
  mov qword [rbp-40], 0 ; http response size counter
  
  ; append 200 OK response template
  lea rdi, [response_template]
  call str_len ; template length
  mov r12, rax ; save template length
  sub r12, 1 ; ignore null terminator
   
  mov rcx, r12
  lea rsi, [response_template] 
  mov rdi, qword [rbp-24] ; buffer address

  rep movsb
  add [rbp-40], r12 ; inc total response size
  add qword [rbp-24], r12 ; move buffer address 

  ; append length header property
  mov rdi, qword [rbp-16] ; msg size
  lea rsi, [rbp-50]
  call number_to_string
  mov r15, rax ; length of the number

  mov rcx, r15 ; length of the number
  lea rsi, qword [rbp-50]
  mov rdi, qword [rbp-24] ; buffer address
  cld
  rep movsb

  add qword [rbp-40], r15 ; inc total response size
  add qword [rbp-24], r15 ; move buffer address 

  ; append CRLF CRLF
  mov r15, 4 ; double CRLF length
  mov rcx, r15 ; double CRLF length
  lea rsi, [CRLFCRLF] ; 
  mov rdi, qword [rbp-24] ; buffer address
  cld
  rep movsb

  add qword [rbp-40], r15 ; inc total response size
  add qword [rbp-24], r15 ; move buffer address 

  ; append message
  mov r15, qword [rbp-16]
  mov rcx, r15 ; message length
  mov rsi, [rbp-8] ; 
  mov rdi, qword [rbp-24] ; buffer address
  cld
  rep movsb

  add qword [rbp-40], r15 ; inc total response size

  mov rax, qword [rbp-40] ; set total response size as result
  add rsp, 50
  pop rbp 
  ret

_start:
  push rbp
  mov rbp, rsp
  sub rsp, 8 ; for server socket fd

  lea rdi, [starting_info]
  call str_len
  lea rdi, [starting_info]
  mov rsi, rax
  call print_prompt

  call create_tcp_socket
  mov qword [rbp-8], rax ; save server socket fd

  mov rdi, qword [rbp-8] ; move server fd
  call set_socket_opt

  mov rdi, qword [rbp-8] ; move server fd
  call bind

  mov rdi, qword [rbp-8] ; move server fd
  call listen

  mov rdi, qword [rbp-8] ; move server fd
  call handle_clients_with_poll

  ; this place is unreachable

  mov rdi, qword [rbp-8] ; move server fd
  call close_connection ; close server fd

  call finish

finish: ; (void) -> void
  mov eax, SYS_EXIT
  mov edi, EXIT_STATUS
  syscall
