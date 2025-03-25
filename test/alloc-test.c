// test_alloc.c
#include <stdio.h>
#include <assert.h>
#include <string.h>

// Include your allocator header which declares the functions below.
// For example, if you named it "alloc.h":
#include "../asm-c/alloc.h"

// Basic allocation test: allocates a block and writes data.
void test_basic_alloc() {
    printf("Running test 'test_basic_alloc'...\n");
    void* ptr = asm_alloc(100);
    assert(ptr != NULL);

    // Fill the allocated block with a pattern.
    memset(ptr, 0xAA, 100);

    // Verify that the data was written correctly.
    unsigned char* p = (unsigned char*) ptr;
    for (int i = 0; i < 100; i++) {
        assert(p[i] == 0xAA);
    }
    asm_free(ptr);

	printf("Test 'test_basic_alloc' passed!\n");
}

// Test reallocation when the adjacent free cluster is NOT available.
// This forces asm_realloc to allocate a new block, copy the data, and free the old one.
void test_realloc_move() {
	printf("Running test 'test_realloc_move'...\n");

    // Allocate two blocks.
    void* ptr1 = asm_alloc(100);
    assert(ptr1 != NULL);
    memset(ptr1, 0xBB, 100);

    // Allocate a second block so that the block after ptr1 is reserved.
    void* ptr2 = asm_alloc(100);
    assert(ptr2 != NULL);

    // Reallocate the first block to a larger size.
    // Since the next cluster is in use, the allocator must allocate a new block.
    ptr1 = asm_realloc(ptr1, 200);
    assert(ptr1 != NULL);

    // Check that the original data was copied.
    unsigned char* np = (unsigned char*) ptr1;
    for (int i = 0; i < 100; i++) {
        assert(np[i] == 0xBB);
    }

    asm_free(ptr1);
    asm_free(ptr2);

	printf("Test 'test_basic_alloc' passed!\n");
}

// Test reallocation when an adjacent free cluster is available.
// In this case, the reallocation should be able to expand in-place.
void test_realloc_inplace() {
	printf("Running test 'test_realloc_inplace'...\n");


    // Allocate a block and another block that will be freed.
    void* ptr1 = asm_alloc(100);
    assert(ptr1 != NULL);
    memset(ptr1, 0xCC, 100);

    void* ptr2 = asm_alloc(100);
    assert(ptr2 != NULL);

    // Free the second block to allow in-place expansion.
    asm_free(ptr2);

    // Attempt to realloc the first block to a larger size.
    void* new_ptr = asm_realloc(ptr1, 150);
    assert(new_ptr != NULL);

    // In a successful in-place expansion the pointer should remain the same.
    assert(new_ptr == ptr1);

    // Verify that the original data remains intact.
    unsigned char* np = (unsigned char*) new_ptr;
    for (int i = 0; i < 100; i++) {
        assert(np[i] == 0xCC);
    }

    asm_free(new_ptr);

	printf("Test 'test_realloc_inplace' passed!\n");
}

// Test that freeing memory allows it to be reused.
// This test frees a block and then allocates a new block of the same size.
void test_free_and_reuse() {
	printf("Running test 'test_free_and_reuse'...\n");


    void* ptr = asm_alloc(100);
    assert(ptr != NULL);
    memset(ptr, 0xDD, 100);

    // Free the block.
    asm_free(ptr);

    // Allocate again. Depending on the allocator’s policy, the free block may be reused.
    void* ptr2 = asm_alloc(100);
    assert(ptr2 != NULL);

    // Write a new pattern and check that it was written.
    memset(ptr2, 0xEE, 100);
    unsigned char* p2 = (unsigned char*) ptr2;
    for (int i = 0; i < 100; i++) {
        assert(p2[i] == 0xEE);
    }

    asm_free(ptr2);

	printf("Test 'test_free_and_reuse' passed!\n");
}

#include <unistd.h>
#define CLUSTER_LIST_APPENDIX 50

void test_simple_alloc_free() {
	printf("Running test 'test_simple_alloc_free'...\n");

    long size = 100;
    char *ptr = asm_alloc(size);
    assert(ptr != NULL);
    assert((size_t)ptr % 4 == 0);

    memset(ptr, 'A', size);
    for (int i = 0; i < size; i++) {
        assert(ptr[i] == 'A');
    }

    asm_free(ptr);

    char *ptr2 = asm_alloc(size);
    assert(ptr2 != NULL);

    asm_free(ptr2);
	printf("Test 'test_simple_alloc_free' passed!\n");
}

void test_realloc_larger() {
	printf("Running test 'test_realloc_larger'...\n");


    int original_size = 100;
    int new_size = 200;
    char *ptr = asm_alloc(original_size);
    strcpy(ptr, "test string");

    char *block = asm_alloc(50);

    char *new_ptr = asm_realloc(ptr, new_size);
    assert(new_ptr != NULL);
    assert(strcmp(new_ptr, "test string") == 0);

    asm_free(new_ptr);
    asm_free(block);

	printf("Test 'test_realloc_larger' passed!\n");
}

void test_realloc_smaller() {
	printf("Running test 'test_realloc_smaller'...\n");

    int original_size = 200;
    int new_size = 100;
    char *ptr = asm_alloc(original_size);
    strcpy(ptr, "test");

    char *new_ptr = asm_realloc(ptr, new_size);
    assert(new_ptr == ptr);

    char *next_block = asm_alloc(50);
    assert(next_block != NULL);

    asm_free(new_ptr);
    asm_free(next_block);

	printf("Test 'test_realloc_smaller' passed!\n");
}

void test_free_merges_adjacent() {
	printf("Running test 'test_free_merges_adjacent'...\n");

    char *a = asm_alloc(100);
    char *b = asm_alloc(100);
    char *c = asm_alloc(100);

    asm_free(b);
    asm_free(a);
    asm_free(c);

    char *big = asm_alloc(300);
    assert(big != NULL);

    asm_free(big);
	printf("Test 'test_free_merges_adjacent' passed!\n");
}

void test_alloc_no_free_space() {
	printf("Running test 'test_alloc_no_free_space'...\n");

    long large_size = 2000;
    char *large = asm_alloc(large_size);
    assert(large != NULL);

    asm_free(large);

	printf("Test 'test_alloc_no_free_space' passed!\n");
}

void test_cluster_list_expansion() {
	printf("Running test 'test_cluster_list_expansion'...\n");

    for (int i = 0; i < CLUSTER_LIST_APPENDIX + 1; i++) {
        asm_alloc(8);
    }

	printf("Test 'test_cluster_list_expansion' passed!\n");
}

void test_alignment() {
	printf("Running test 'test_alignment'...\n");

    long size1 = 1;
    char *ptr1 = asm_alloc(size1);
    assert((size_t)ptr1 % 4 == 0);
    asm_free(ptr1);

    long size2 = 10;
    char *ptr2 = asm_alloc(size2);
    assert((size_t)ptr2 % 4 == 0);
    asm_free(ptr2);

	printf("Test 'test_alignment' passed!\n");
}

void test_best_fit() {
	printf("Running test 'test_best_fit'...\n");

    char *a = asm_alloc(46); // Correct size 48
    char *b = asm_alloc(96); // Correct size 100
    char *c = asm_alloc(146);// Correct size 148

    asm_free(a);
    asm_free(b);
    asm_free(c);

    char *ptr = asm_alloc(100); // Correct size 104
    assert(ptr != NULL);

    asm_free(ptr);
	printf("Test 'test_best_fit' passed!\n");
}

void test_join_clusters() {
	printf("Running test 'test_join_clusters'...\n");

    char *a = asm_alloc(100);
    char *b = asm_alloc(100);
    asm_free(a);
    asm_free(b);

    char *c = asm_alloc(200);
    assert(c != NULL);

    asm_free(c);
	printf("Test 'test_join_clusters' passed!\n");
}

void test_realloc_null() {
	printf("Running test 'test_realloc_null'...\n");

    char *ptr = asm_realloc(NULL, 100);
    assert(ptr == NULL);

	printf("Test 'test_realloc_null' passed!\n");
}

int main() {
    init_allocator();

    test_basic_alloc();
    test_realloc_move();
    test_realloc_inplace();
    test_free_and_reuse();

    test_simple_alloc_free();
    test_realloc_larger();
    test_realloc_smaller();
    test_free_merges_adjacent();
    test_alloc_no_free_space();
    test_cluster_list_expansion();
    test_alignment();
    test_best_fit();
    test_join_clusters();
    test_realloc_null();

    printf("All tests passed!\n");
    return 0;
}