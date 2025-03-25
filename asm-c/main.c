//
// Created by rorak on 13.3.25.
//

#include <unistd.h>

#define TODO_SIZE 12

const char* WELCOME_MESSAGE = "-- Welcome to my todo app! --\n";
const char* ACTION_MESSAGE = "\n\nSelect the next action:\n[0] Exit\n[1] List todos\n[2] Add a todo\n[3] Edit a todo\n[4] Delete a todo\n[5] Complete a todo\n\n";

const char* INVALID_INPUT_ERROR = "Wrong input, try again!\n";

const char* NO_TODOS_MESSAGE = "No todos!\n";
const char* TODO_LIST_HEADER = "Todos: (id) [Completed] Description\n";

unsigned int strlen_(const char* string);

void listTodos();
void addTodo();
void editTodo();
void deleteTodo();
void completeTodo();

char* readString();
char getTodoWithReadId(void* todoToChange);

void* todos;
unsigned int todoCounter = 0;
unsigned int realTodoCount = 0;

int main() {
    write(STDOUT_FILENO, WELCOME_MESSAGE, strlen_(WELCOME_MESSAGE));
    char choice;

    mainLoop:
    write(STDOUT_FILENO, ACTION_MESSAGE, strlen_(ACTION_MESSAGE));

    read(STDIN_FILENO, &choice, 1);
    read(STDIN_FILENO, NULL, 1); // consume new line

    choice -= 48; // convert to int

    if (choice == 0) goto mainExit;
    if (choice == 1) goto mainListTodos;
    if (choice == 2) goto mainAddTodo;
    if (choice == 3) goto mainEditTodo;
    if (choice == 4) goto mainDeleteTodo;
    if (choice == 5) goto mainCompleteTodo;

    // error
    write(STDOUT_FILENO, INVALID_INPUT_ERROR, strlen_(INVALID_INPUT_ERROR));
    goto mainLoop;

    mainExit:
        _exit(0);
    mainListTodos:
        listTodos();
        goto mainLoop;
    mainAddTodo:
        addTodo();
        goto mainLoop;
    mainEditTodo:
        addTodo();
        goto mainLoop;
    mainDeleteTodo:
        deleteTodo();
        goto mainLoop;
    mainCompleteTodo:
        completeTodo();
        goto mainLoop;
}

void listTodos() {
    if (realTodoCount == 0) goto listTodosNoTodos;

    write(STDOUT_FILENO, TODO_LIST_HEADER, strlen_(TODO_LIST_HEADER));

    unsigned int ecx = 0;

    listTodosFor1:;
        void* todo = &todos[ecx * TODO_SIZE];



    listTodosNoTodos:
        write(STDOUT_FILENO, NO_TODOS_MESSAGE, strlen_(NO_TODOS_MESSAGE));
}

unsigned int strlen_(const char* string) {
    int ecx = -1;
    strlen1:
        ecx++;
        if (string[ecx] != '\0') goto strlen1;

    return ecx;
}