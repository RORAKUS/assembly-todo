%assign STREND 0x00 ; string termination character
%assign ZERO_ASCII_CODE 0x30 ; self explanatory
%assign NEGATIVE_ONE 0xFFFFFFFF ; self explanatory

section .text

global strlen
global itostr

strlen: ; int strlen(char* string)
    push ebp ; function enter logic - saves and sets ebp to the stack top
    mov ebp, esp

    push ebx ; saves registers
    push ecx
    push edx

    mov ecx, NEGATIVE_ONE ; sets the counter to -1
    mov ebx, [ebp + 8] ; address to the string we want to measure (char* string)
    .strlenWhile1: ; while (string[ecx] != '\0')
        inc ecx ; increase ecx
        cmp [ebx + ecx], byte STREND ; compare the byte on ecx offset from string with null byte (termination byte)
        jne .strlenWhile1 ; if it doesn't equal, do it again
    mov eax, ecx ; eax = return register -- move the length to the return register

    pop edx ; retrieves registers
    pop ecx
    pop ebx

    mov esp, ebp ; clears stack back to it's original state
    pop ebp ; retreive ebp
    ret

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