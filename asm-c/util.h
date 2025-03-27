//
// Created by rorak on 26.3.25.
//

#ifndef ASM_UTIL_H
#define ASM_UTIL_H

#define NUMBER_STRING_LENGTH 12

void asm_memmove(void* dest, void* src, long size);
long asm_strlen(const char* string);
void asm_numtostr(char str[NUMBER_STRING_LENGTH], long num);

#endif // ASM_UTIL_H