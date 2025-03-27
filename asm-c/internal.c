//
// Created by rorak on 27.3.25.
//

#include <stdio.h>
#include <stdlib.h>
#include "internal.h"

#define STACK_SIZE (100 * 4)

void checkStackSize();

void rep_movsb(char* dest, const char* src, long count, char mode) {
    if (mode == FORWARDS_MODE)
        for (int i = 0; i < count; i++)
            dest[i] = src[i];
    if (mode == BACKWARDS_MODE)
        for (int i = 0; i > -count; i--)
            dest[i] = src[i];
}

char stack[STACK_SIZE] = {};
long stackPosition = 0;

void stack_pushd(long dword) {
    checkStackSize();

    long* currentStackDword = (long*) &stack[stackPosition];
    *currentStackDword = dword;
    stackPosition += 4;
}
void stack_pushb(char byte) {
    checkStackSize();
    stack[stackPosition++] = byte;
}
long stack_popd() {
    long value = (long) stack[stackPosition];
    stackPosition -= 4;
    return value;
}
char stack_popb() {
    return stack[stackPosition--];
}
void checkStackSize() {
    if (stackPosition < STACK_SIZE) return;

    fprintf(stderr, "The stack is full!\n");
    exit(1);
}