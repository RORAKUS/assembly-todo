//
// Created by rorak on 25.3.25.
//

#include <stdbool.h>
#include <unistd.h>
#include <limits.h>
#include <memory.h>

#define INITIAL_ALLOC_MEMORY_APPENDIX 2000
#define CLUSTER_LIST_APPENDIX 50

typedef struct {
    void* start;
    void* end;
    bool reserved;
} Cluster;

void* asm_realloc(void* ptr, long size);
void* asm_alloc(long size);
void asm_free(void* ptr);
void init_allocator();
void set_alloc_memory_appendix(long value);

Cluster* asm_joinClusters(Cluster* cl1, Cluster* cl2);
Cluster* asm_findCluster(void* start);
Cluster* asm_addNewCluster(void* start, void* end);
Cluster* asm_emptyClusterWithSize(long size);
void asm_deleteCluster(Cluster* cl);
void asm_reallocClusterList();
void asm_reserveCluster(Cluster* cl, long size);
void* asm_reserveBytes(long num);

Cluster clusterListCluster;
Cluster* clusters;
long clusterCount;
long allocMemoryAppendix;

void set_alloc_memory_appendix(long value) {
    allocMemoryAppendix = (value + 8) & ~7; // align to 8 bytes
}

void* asm_alloc(long size) {
    long correctSize = (size + 4) & ~3; // align to 4 bytes

    Cluster* emptyCluster = asm_emptyClusterWithSize(correctSize);

    if (emptyCluster == NULL) {
        void* start = asm_reserveBytes(allocMemoryAppendix);
        emptyCluster = asm_addNewCluster(start, start + correctSize - 4);
    }

    asm_reserveCluster(emptyCluster, correctSize);

    return emptyCluster->start;
}

void* asm_realloc(void* ptr, long size) {
    long correctSize = (size + 4) & ~3; // align to 4 bytes

    Cluster* cl = asm_findCluster(ptr);
    if (cl == NULL) return NULL;

    Cluster* next = asm_findCluster(cl->end + 4);

    if (next == NULL || next->reserved) {
        // allocate new cluster
        void* newStart = asm_alloc(correctSize);
        // copy
        memcpy(newStart, ptr, cl->end - cl->start);
        // free
        asm_free(ptr);

        return newStart;
    }

    // use the following cluster
    cl->reserved = false;
    asm_joinClusters(cl, next);
    asm_reserveCluster(cl, correctSize);

    return cl->start;
}

void asm_free(void* ptr) {
    Cluster* cl = asm_findCluster(ptr);
    cl->reserved = false;

    // join free clusters around
    Cluster* next = asm_findCluster(cl->end + 4);
    Cluster* previous = asm_findCluster(cl->start - 4);

    if (next != NULL) asm_joinClusters(cl, next);
    if (previous != NULL) asm_joinClusters(cl, previous);
}

void init_allocator() {
    clusterCount = 0;
    allocMemoryAppendix = INITIAL_ALLOC_MEMORY_APPENDIX;

    long bytes = sizeof(Cluster) * CLUSTER_LIST_APPENDIX;
    void* ptr = asm_reserveBytes(bytes);

    clusterListCluster.start = ptr;
    clusterListCluster.end = ptr + bytes - 4;
    clusters = ptr;
}

void asm_deleteCluster(Cluster* cl) {
   for (long i = 0; i < clusterCount; i++) {
       Cluster* current = &clusters[i];

       if (current->start != cl->start) continue;

       if (i != clusterCount - 1)
           memmove(current, &clusters[i + 1], (clusterCount - i - 1) * sizeof(Cluster));

       clusterCount--;
       return;
   }
}

Cluster* asm_joinClusters(Cluster* cl1, Cluster* cl2) {
    if (cl1->end + 4 != cl2->start) return NULL;

    cl1->end = cl2->end;
    asm_deleteCluster(cl2);

    return cl1;
}

Cluster* asm_findCluster(void* start) {
    for (int i = 0; i < clusterCount; i++) {
        Cluster* cl = &clusters[i];

        if (cl->start == start) return cl;
    }

    return NULL;
}

#pragma clang diagnostic push
#pragma ide diagnostic ignored "misc-no-recursion"
void asm_reallocClusterList() {
    long currentListSize = clusterListCluster.end - clusterListCluster.start;

    long reservedBytes = currentListSize + (long) sizeof(Cluster) * CLUSTER_LIST_APPENDIX;
    void* startAddress = asm_reserveBytes(reservedBytes);

    void* oldClusterStart = clusterListCluster.start;
    void* oldClusterEnd = clusterListCluster.end;

    clusterListCluster.start = startAddress;
    clusterListCluster.end = startAddress + reservedBytes - 4;
    clusters = startAddress;

    memcpy(clusterListCluster.start, oldClusterStart, oldClusterEnd - oldClusterStart);

    asm_addNewCluster(oldClusterStart, oldClusterEnd);
}

Cluster* asm_addNewCluster(void* start, void* end) {
    clusterCount++;

    long currentClusterListClusterSize = clusterCount * (long) sizeof(Cluster);
    long maxClusterListClusterSize = clusterListCluster.end - clusterListCluster.start;

    if (currentClusterListClusterSize > maxClusterListClusterSize)
        asm_reallocClusterList();

    Cluster* newCluster = &clusters[clusterCount - 1];
    newCluster->start = start;
    newCluster->end = end;
    newCluster->reserved = false;

    return newCluster;
}

#pragma clang diagnostic pop

void asm_reserveCluster(Cluster* cl, long size) {
    cl->reserved = true;

    long clusterSize = cl->end - cl->start;
    if (clusterSize == size) return;

    void* clusterNewEnd = cl->start + size;

    asm_addNewCluster(clusterNewEnd + 4, cl->end);

    cl->end = clusterNewEnd;
}

Cluster* asm_emptyClusterWithSize(long size) {
    long minSizeDifference = LONG_MAX;
    Cluster* selectedCluster = NULL;

    for (long i = 0; i < clusterCount; i++) {
        Cluster* current = &clusters[i];
        if (current->reserved) continue;

        long clusterSize = (long) current->end - (long) current->start;
        if (size > clusterSize) continue;

        long sizeDifference = clusterSize - size;
        if (sizeDifference < minSizeDifference) {
            minSizeDifference = sizeDifference;
            selectedCluster = current;
        }
    }

    return selectedCluster;
}

void* asm_reserveBytes(long num) {
    void* currentSystemBreak = sbrk(0);
    brk(currentSystemBreak + num);

    return currentSystemBreak;
}