//
// Created by rorak on 26.3.25.
//

#include "util.h"
#include "internal.h"

#define ZERO_ASCII_CODE '0'

void asm_memmove(void* dest, void* src, long size) {
    if (src == dest) return;
    if (src < dest)
        rep_movsb((char*)(dest + size - 1), (char*)(src + size - 1),size, BACKWARDS_MODE);
    else
        rep_movsb((char*) dest, (char*) src, size, FORWARDS_MODE);
}

long asm_strlen(const char* string) {
    long i = 0;
    while (string[i] != '\0') i++;

    return i;
}

void asm_numtostr(char str[NUMBER_STRING_LENGTH], long num) {
    long wholePart = num;
    long digitCount = 0;
    do {
        long remainder = wholePart % 10;
        stack_pushb((char) (remainder + ZERO_ASCII_CODE));
        wholePart /= 10;
        digitCount++;
    } while (wholePart != 0);

    for (long i = 0; i < digitCount; i++) str[i] = stack_popb();

    str[digitCount] = '\0';
}