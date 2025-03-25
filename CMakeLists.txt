cmake_minimum_required(VERSION 3.30)
project(todo C)

set(CMAKE_C_STANDARD 11)

add_executable(c c/main.c)
add_executable(asm-c asm-c/main.c asm-c/alloc.c asm-c/alloc.h)
add_executable(unit-tests test/alloc-test.c asm-c/alloc.c asm-c/alloc.h)
add_executable(test test/test.c)