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
global strlen
global itostr
global memmove

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

itostr: ; void itostr(char*[11] str, int num) - converts an integer into a string with a \0 character at the end
    push ebp ; function enter logic - saves and sets ebp to the stack top
    mov ebp, esp

    push eax ; save registers
    push ebx
    push ecx
    push edx
    push edi
    ;; Function logic

    mov edi, [ebp + 8] ; save the string address into edi (param str)

    ; Convert the number into the string and save length in ecx:
    ;   eax - the whole part; ebx - the divider, ecx - the counter; edx - the remainder
    mov eax, [ebp + 12] ; initialize the whole part to the num parameter
    mov ebx, 10 ; the divider
    mov ecx, 0 ; the character counter
    .itostrLoop1: ; the number convertor loop
        mov edx, 0 ; the remainder will also act as the first part for the division, must be zero before
        div ebx ; divide edx:eax with 10, save the whole part into eax and remainder into edx
        add edx, ZERO_ASCII_CODE ; convert the remainder into a character
        push dx ; push the remainder character to the stack
        inc ecx ; increase the counter
        cmp eax, 0 ; if the whole part is greater then 0 continue in the loop
        ja .itostrLoop1

    ; Reverse the number and append the null byte:
    ;   ecx - the character count, ebx - the reverse counter for the final string
    mov ebx, 0 ; initialize the string counter
    .itostrLoop2: ; the reverse loop
        pop ax ; pop the character from the stack
        mov [edi + ebx], al ; move the character into the string

        dec ecx ; decrease the character counter
        inc ebx ; increase the string counter
        cmp ecx, 0 ; if ecx != 0 continue (when all digits are done)
        jne .itostrLoop2
   mov [edi + ebx], byte STREND ; append the null byte

    ;; End function logic

    pop edi ; retreive registers
    pop edx
    pop ecx
    pop ebx
    pop eax

    mov esp, ebp ; clears stack back to it's original state
    pop ebp ; retreive ebp
    ret