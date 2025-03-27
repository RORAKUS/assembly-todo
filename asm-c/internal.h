//
// Created by rorak on 27.3.25.
//

#ifndef ASM_INTERNAL_H
#define ASM_INTERNAL_H

#define FORWARDS_MODE 1
#define BACKWARDS_MODE 2

void rep_movsb(char* dest, const char* src, long count, char mode);

void stack_pushd(long dword);
void stack_pushb(char byte);
long stack_popd();
char stack_popb();

#endif //ASM_INTERNAL_H