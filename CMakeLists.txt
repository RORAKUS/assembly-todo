cmake_minimum_required(VERSION 3.30)
project(todo C)

set(CMAKE_C_STANDARD 11)

add_executable(todo c/main.c)
add_executable(todo-asm c/main.asm.c)