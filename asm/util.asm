;; Constants
%define STREND 0x00
%define ZERO_ASCII_CODE 0x30
%define NEGATIVE_ONE 0xFFFFFFFF
%define NUMBER_STRING_LENGTH 12

%define PARAM_1 [ebp + 8]
%define PARAM_2 [ebp + 12]
%define PARAM_3 [ebp + 16]

;; Macros
%macro fun 0
push ebp
mov ebp, esp
%endmacro

%macro return 0
mov esp, ebp
pop ebp
ret
%endmacro

;; Code

section .text
global memmove
global strlen
global numtostr

memmove: ; moves 'size' bytes from 'src' to 'dest'
    fun ; void memmmove(void* dest, void* src, long size)

    ; Compare the destination with the source
    ;   - If equal -> return
    ;   - If src > dest -> copy forwards
    ;   - If src < dest -> copy backwards

    ; Compare source and destination
    mov ebx, PARAM_2 ; ebx = src
    cmp ebx, PARAM_1 ; compare src with dest
    je .memmoveReturn ; if (src == dest) jmp .memmoveReturn
    jb .memmoveBackwards ; if (src < dest) jmp .memmoveBackwards

    ; Copy the memory
    cld ; clear DF => forwards mode
    mov ecx, PARAM_3 ; set the counter to 'size'
    mov esi, PARAM_2 ; set the source to 'src'
    mov edi, PARAM_1 ; set the destination to 'dest'
    rep movsb ; repeat byte copy until ecx == 0 decreasing ecx with every iteration

    ; Return
    jmp .memmoveReturn

    .memmoveBackwards:
    ; Set the registers for manipulation
    mov edx, PARAM_2 ; edx = src
    mov ebx, PARAM_1 ; ebx = dest

    ; Copy the memory
    std ; set DF => backwards mode
    mov ecx, PARAM_3 ; set counter to 'size'
    mov esi, [edx + ecx - 1] ; set the source to 'src + size - 1' (the last byte)
    mov edi, [ebx + ecx - 1] ; set the destination to 'dest + size - 1' (the last byte)
    rep movsb ; repeat byte copy until ecx == 0 decreasing ecx with every iteration
    cld ; clear DF

    .memmoveReturn:
    return

strlen: ; computes and retuns the length of a string
    fun ; int strlen(char* string)

    ; List through every character of the string
    ; { long i = 0; while (i != STREND) }
    ;   long i: [ecx]
    mov ecx, 0 ; i = 0
    mov ebx, PARAM_1 ; ebx = string
    .strlenLoop1:
        cmp byte [ebx + ecx], STREND ; if (string[i] == STREND) break
        je .strlenExitLoop1
        inc ecx ; i++
    .strlenExitLoop1:

    ; Return the counter
    mov eax, ecx ; return i

    return

numtostr: ; converts a number into a string
    fun ; void numtostr(char* str, long num)

    ; 1. Keep dividing the number by 10:
    ;   a. push the remainder as a character onto the stack
    ;   b. set the number to be divided next time to the result
    ;   c. increase the digit count by 1
    ; 2. Pop all the digits from the stack one by one and add them to the string
    ; 3. Append the \0 character

    ; Allocate new space for local variables:
    ;   long digitCount: [esp]
    sub esp, 4

    ; Initialize the variables
    ;   long wholePart: [eax]
    mov eax, PARAM_2 ; wholePart = num
    mov dword [esp], 0 ; digitCount = 0
    mov ebx, 10 ; the divider, must be in a register

    ; Divide the number by 10 until whole part is 0 { do ... while (wholePart != 0) }
    .numtostrLoop1:
        ; Divide the whole part by 10
        ; { long remainder = wholePart % 10 ; wholePart /= 10 }
        ;   long remainder: [edx]
        mov edx, 0 ; needed for division (edx:eax is the divisor)
        div ebx ; eax = wholePart / 10; edx = wholePart % 10

        ; Convert the remainder into an ascii character by adding '0' character code { remainer += '0' }
        add edx, ZERO_ASCII_CODE ; edx += '0'

        ; Push one byte from the remainder onto the stack (there are no other bytes)
        push dl

        ; Increase the digit count
        inc dword [esp] ; digitCount++

        cmp eax, 0 ; if (wholePart != 0) continue
        jne .numtostrLoop1

    ; Save the 'str' parameter into ebx
    mov ebx, PARAM_1 ; ebx = str
    ; Go through all the saved digits on the stack and add them to the string { for (int i = 0; i < digitCount; i++) }
    ;   long i: [ecx]
    mov ecx, 0 ; i = 0
    .numtostrLoop2:
        cmp ecx, [esp] ; if (i >= digitCount) break
        jae .numtostrExitLoop2

        ; Pop the character and add it into the string { str[i] = pop() }
        lea edx, [ebx + ecx] ; edx = &str[i]
        pop byte [edx] ; *edx = pop()

        inc ecx ; i++
        jmp .numtostrLoop2 ; continue the loop
    .numtostrExitLoop2:

    ; Append the NULL byte at the end of the string
    mov edx, [esp] ; edx = digitCount
    mov byte [ebx + edx], STREND ; str[edx] = '\0'

    return