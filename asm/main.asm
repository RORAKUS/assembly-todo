;;; CONSTANT SECTION
%assign STDOUT_FILENO 1 ; file descriptor for STDOUT
%assign STDIN_FILENO 0 ; file descriptor for STDIN

%assign EXIT_CODE 0 ; exit code of the program

%assign SYS_WRITE 4 ; code for the write() syscall
%assign SYS_READ 3 ; code for the read() syscall
%assign SYS_EXIT 1 ; code for the _exit() syscall

%assign NL 0x0a ; ascii code for a new line
%assign STREND 0x00 ; string termination character

%assign INTEGER_STRING_LENGTH 12 ; the length for a string containing an integer
%assign INTEGER_SIZE 4

%assign TODO_STRUCT_SIZE 12 ; id[4], description*[4], completed[1] (_3)
%assign TODO_ID_INDEX 0
%assign TODO_DESCRIPTION_INDEX 4
%assign TODO_COMPLETED_INDEX 8

;;; MACRO SECTION
%macro write 2 ; write(char* msg, int length)
mov edx, %2
mov ecx, %1
mov ebx, STDOUT_FILENO
mov eax, SYS_WRITE
int 0x80
%endmacro

%macro read 2 ; read(char* msg, int length)
mov edx, %2
mov ecx, %1
mov ebx, STDIN_FILENO
mov eax, SYS_READ
int 0x80
%endmacro

%macro exit 1
mov ebx, %1
mov eax, SYS_EXIT
int 0x80
%endmacro

%macro print 1
push %1
call strlen ; stlen(%1)
add esp, 4 ; clear the stack
write %1, eax
%endmacro

;;; CONSTANT VARIABLE SECTION
section .data
welcomeMessage db "-- Welcome to my todo app! --", NL, STREND
actionMessage db NL, NL, "Select the next action:", NL, "[0] Exit", NL, "[1] List todos", NL, "[2] Add a todo", NL, "[3] Edit a todo", NL, "[4] Delete a todo", NL, "[5] Complete a todo", NL, NL, STREND

wrongInputErrorMessage db "Wrong input, try again!", NL, STREND

noTodosMessage db "No todos!", NL, STREND
emptyDescriptionMessage db "The description cannot be empty!", NL, STREND
listTodosHeader db "Todos: (id) [Completed] Description", NL, STREND
addTodoHeader db "Adding a todo...", NL, "Description: ", STREND
addTodoSuccess db "Successfully added!", NL, STREND

listTodosRow1 db "(", STREND
listTodosRow2 db ") [", STREND
listTodosRow3 db "] ", STREND
listTodosRow4 db NL, STREND

testMsg db "test msg", NL, STREND
testMsgNoNl db "test msg", STREND

;;; VARIABLE SECTION
section .bss
consume resb 1
choice resb 1

todos times TODO_STRUCT_SIZE resb 4 ; fixme

realTodoCount resb INTEGER_SIZE
todoCounter resb INTEGER_SIZE

;;; CODE SECTION
section .text
global _start
global main

extern strlen
extern itostr
extern init_allocator

initializeVariables:
    ; Initialize the variables
    mov dword [realTodoCount], 1
    mov dword [todoCounter], 1
    ; Test initialize one item
    mov todos[0], dword 1
    mov todos[4], dword testMsgNoNl
    mov todos[8], byte 'X'

    ret
_start:
    call main
main:
    call init_allocator
    call initializeVariables

    ; Write out the welcome message
    print welcomeMessage

    ; Main program loop
    .mainWhile1:
        ; Write out the select action message
        print actionMessage

        ; Get a next byte from the stdin
        read choice, 1
        ; Consume a new line
        read consume, 1
        ; Depending on the choice execute an action
        cmp byte [choice], '0'
        je .mainExit
        cmp byte [choice], '1'
        je .mainListTodos
        cmp byte [choice], '2'
        je .mainAddTodo
        cmp byte [choice], '3'
        je .mainEditTodo
        cmp byte [choice], '4'
        je .mainDeleteTodo
        cmp byte [choice], '5'
        je .mainCompleteTodo
        ; Invalid input - display an error
        print wrongInputErrorMessage
        jmp .mainWhile1 ; continue the loop

    .mainListTodos:
        call listTodos ; listTodos()
        jmp .mainWhile1 ; continue the loop
    .mainAddTodo:
        call addTodo ; addTodo()
        jmp .mainWhile1 ; continue the loop
    .mainEditTodo:
        ;call editTodo ; editTodo()
        jmp .mainWhile1 ; continue the loop
    .mainDeleteTodo:
        ;call deleteTodo ; deleteTodo()
        jmp .mainWhile1 ; continue the loop
    .mainCompleteTodo:
        ;call completeTodo ; completeTodo()
        jmp .mainWhile1 ; continue the loop
    .mainExit:
        exit EXIT_CODE ; exit the program

listTodos:
    mov ebp, esp ; save the stack top

    ; If there are no entries, print noTodosMessage
    cmp dword [realTodoCount], 0
    je .listTodosNoTodos

    ; Print the header
    print listTodosHeader

    ; Print all entries
    mov ecx, 0 ; initialize the counter
    sub esp, INTEGER_STRING_LENGTH ; str = free 12 bytes at the top of the stack for the string character
    ; str = esp + 0
    .listTodosLoop1:
        ;; Loop logic
        mov eax, ecx ; multiply the counter with the struct size to get the index
        mov ebx, TODO_STRUCT_SIZE
        mul ebx ; index = eax = ecx * STRUCT_SIZE
        lea eax, todos[eax] ; copy the address into eax
        push eax ; list[index] - the current item pointer
        ; str = esp + 4
        ; current = esp + 0

        push ecx ; save the counter
        ; str = esp + 8
        ; current = esp + 4
        ; counter = esp + 0

        print listTodosRow1 ; print the first part

        ; Convert the id into a string, save in esp + 11 and print it
        mov eax, [esp + 4] ; get the address of the current item
        push dword [eax + TODO_ID_INDEX] ; push the id of the item (current.id)
        ; str = esp + 12
        ; current = esp + 8
        ; counter = esp + 4
        lea eax, [esp + 12] ; copy the address into eax
        push eax ; push the address of the 11 bytes reserved - str
        call itostr ; itostr(str, current.id)
        add esp, 8 ; clear the stack of the function parameters
        ; str = esp + 8
        ; current = esp + 4
        ; counter = esp + 0
        lea esi, [esp + 8] ; copy the address id into esi
        print esi ; print the id

        print listTodosRow2 ; print the second part

        ; Print the character
        mov esi, [esp + 4] ; get the pointer to the current item
        lea esi, [esi + TODO_COMPLETED_INDEX] ; get the pointer to the character part
        write esi, 1 ; write one character

        print listTodosRow3 ; print the third part

        ; Print the description
        mov esi, [esp + 4] ; get the address of the current item
        print dword [esi + TODO_DESCRIPTION_INDEX] ; print the description

        print listTodosRow4 ; print the last part

        pop ecx ; retreive the counter
        sub esp, 4 ; clear the stack of the current item address

        ;; End loop logic
        inc ecx ; ecx++
        cmp ecx, dword [todoCounter] ; if (ecx < counter) continue
        jb .listTodosLoop1

    jmp .listTodosReturn

    .listTodosNoTodos:
        print noTodosMessage

    .listTodosReturn:
        mov esp, ebp ; retreive the stack
        ret

addTodo:
    mov ebp, esp ; save the stack top

    print addTodoHeader ; print the header message

    .addTodoEmptyDescription:
        print emptyDescriptionMessage

    .addTodoReturn:
        mov esp, ebp ; retreive the stack
        ret