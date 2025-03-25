//
// Created by rorak on 25.3.25.
//

#ifndef ASM_ALLOC_H__
#define ASM_ALLOC_H__

void* asm_realloc(void* ptr, long size);
void* asm_alloc(long size);
int asm_free(void* ptr);
void init_allocator();
int set_alloc_memory_appendix(long value);
int get_alloc_error_code();

#endif