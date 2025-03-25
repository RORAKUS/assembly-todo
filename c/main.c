#pragma clang diagnostic push
#pragma ide diagnostic ignored "cert-err34-c"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

typedef struct Todo {
    int id;
    char* description;
    char completed; // V - completed; X - uncompleted
} Todo;

void listTodos();
void addTodo();
void editTodo();
void deleteTodo();
void completeTodo();

char* readString();
bool getTodoWithReadId(Todo** todoToChange);

Todo* todos = NULL;
int todoCount = 0;
int realTodoCount = 0;

int main() {
    printf("-- Welcome to my todo app! --\n");
    int choice;

    while (true) {
        printf("\n\n");
        printf("Select the next action:\n");
        printf("[0] Exit\n");
        printf("[1] List todos\n");
        printf("[2] Add a todo\n");
        printf("[3] Edit a todo\n");
        printf("[4] Delete a todo\n");
        printf("[5] Complete a todo\n\n");

        scanf("%i", &choice);
        getchar();

        switch (choice) {
            case 0:
                exit(0);
            case 1:
                listTodos();
                break;
            case 2:
                addTodo();
                break;
            case 3:
                editTodo();
                break;
            case 4:
                deleteTodo();
                break;
            case 5:
                completeTodo();
                break;
            default:
                printf("Wrong input, try again!");
        }
    }
}

void listTodos() {
    if (realTodoCount == 0) {
        printf("No todos!\n");
        return;
    }

    printf("Todos: (id) [Completed] Description\n");

    for (int i = 0; i < todoCount; i++) {
        Todo todo = todos[i];

        if (todo.id == -1) continue;

        printf("(%i) [%c] %s\n", todo.id, todo.completed, todo.description);
    }
}

void addTodo() {
    // read the description
    printf("Adding a todo...\n");
    printf("Description: ");

    char* description = readString();

    if (description == NULL) {
        printf("The description cannot be empty!\n");
        return;
    }

    Todo todo = {todoCount, description, 'X' };

    if (todoCount == 0)
        todos = malloc(++todoCount * sizeof(Todo));
    else
        todos = realloc(todos, ++todoCount * sizeof(Todo));

    todos[todoCount - 1] = todo;
    realTodoCount++;

    printf("Successfully added!\n");
}

void editTodo() {
    printf("Editting a todo...\n");
    listTodos();
    printf("Select the id to edit: ");

    Todo* todo;
    bool success = getTodoWithReadId(&todo);

    if (!success) {
        printf("Invalid input!");
        return;
    }

    printf("New description: ");
    char* description = readString();

    if (description == NULL) {
        printf("New description cannot be empty!\n");
        return;
    }

    free(todo->description);
    todo->description = description;

    printf("Successfully edited!\n");
}

void deleteTodo() {
    printf("Deleting a todo...\n");
    listTodos();
    printf("Select the id to delete:");

    Todo* todo;
    bool success = getTodoWithReadId(&todo);

    if (!success) {
        printf("Invalid input!");
        return;
    }

    free(todo->description);
    todo->id = -1;
    realTodoCount--;

    printf("Successfully deleted!\n");
}

void completeTodo() {
    printf("Completing a todo...\n");
    listTodos();
    printf("Select the id to complete:");

    Todo* todo;
    bool success = getTodoWithReadId(&todo);

    if (!success) return;

    todo->completed = 'V';

    printf("Successfully completed!\n");
}

char* readString() {
    int readChar = getchar();
    int readCharacters = 0;

    int initialSize = 20;
    char* string = malloc(initialSize + 1);

    while(readChar != EOF && readChar != '\n') {
        if (readCharacters >= initialSize) {
            initialSize *= 2;
            string = realloc(string, initialSize + 1);
        }

        string[readCharacters] = (char) readChar;

        readCharacters++;
        readChar = getchar();
    }

    if (readCharacters == 0) {
        free(string);
        return NULL;
    }

    string[readCharacters] = '\0';

    return string;
}
bool getTodoWithReadId(Todo** todoToChange) {
    int id;
    int readCharacters = scanf("%i", &id);
    getchar();

    if (readCharacters == 0) {
        printf("Wrong input!\n");
        return false;
    }

    if (id < 0 || id >= todoCount) {
        printf("Invalid id!\n");
        return false;
    }

    Todo* todo = &todos[id];

    if (todo->id == -1) {
        printf("Invalid id!\n");
        return false;
    }

    *todoToChange = todo;

    return true;
}

#pragma clang diagnostic pop