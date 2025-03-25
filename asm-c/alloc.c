#pragma clang diagnostic push
#pragma ide diagnostic ignored "misc-no-recursion"
//
// Created by rorak on 25.3.25.
//

#include <stdbool.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <memory.h>
#include <limits.h>
#include <stdio.h>
#include "alloc.h"

#pragma clang diagnostic push
#pragma ide diagnostic ignored "MemoryLeak"

#define ERROR_NULL_POINTER 1
#define ERROR_INVALID_POINTER 2
#define ERROR_INVALID_SIZE 3
#define ERROR_SYS_BRK_ERR 4

#define CLUSTER_SIZE ((long) sizeof(Cluster))
#define INITIAL_ALLOC_MEMORY_APPENDIX 2048
#define CLUSTER_LIST_APPENDIX 50
#define ALIGN_TO_BYTE 4
#define ALLOWED_FREE_MEMORY_COEFFICIENT 2

#define SYS_BRK(num) ((void*) syscall(SYS_brk, num))
#define CURRENT_BRK SYS_BRK(0)

typedef struct {
    void* start;
    long size;
    bool reserved;
} Cluster;

void* reserveMemory(long size);
void freeMemory(void* newEnd);

Cluster* freeClusterForSize(long size);
Cluster* findClusterByStart(void* start);
Cluster* findClusterByEnd(void* end);
void joinClusters(Cluster* finalCluster, Cluster* appendedCluster);

Cluster* addCluster(void* start, long size);
void joinNeighbourClusters(Cluster* cl);
void removeCluster(Cluster* cl);
int reserveCluster(Cluster* cl, long size);
void freeCluster(Cluster* cl); // without calling freeMemory()
void deleteUselessClusters();

int reallocClustersCluster();

long alignNumber(long value);

Cluster* clusters;
long clusterCount;
Cluster clustersCluster;

long allocMemoryAppendix;
int errorCode;

void* asm_alloc(long size) {
    /*
     * 1. Find a free cluster with the lowest size difference
     * 2. If no cluster, create a new cluster and add it
     * 3. Reserve the cluster
     * 4. Return the cluster start address
     */

    if (size <= 0) {
        errorCode = ERROR_INVALID_SIZE;
        return NULL;
    }

    long alignedSize = alignNumber(size);
    Cluster* cluster = freeClusterForSize(alignedSize);

    if (cluster == NULL) {
        void* newClusterStart = reserveMemory(allocMemoryAppendix);
        if (newClusterStart == NULL) return NULL;

        cluster = addCluster(newClusterStart, allocMemoryAppendix);

        if (cluster == NULL) return NULL;
    }

    int exitCode = reserveCluster(cluster, alignedSize);
    if (exitCode == -1) return NULL;

    return cluster->start;
}

void* asm_realloc(void* ptr, long size) {
    /*
     * 0. If the size parameter is lower than the cluster size
     *      - reserve the cluster again to split it
     * 1. Free the current cluster (freeCluster())
     * 2. Allocate a new cluster for the size
     * 3. Safely copy the memory
     * 4. Delete the last cluster if empty
     * 5. Return the start address
     */

    if (ptr == NULL) {
        errorCode = ERROR_NULL_POINTER;
        return NULL;
    }

    if (size <= 0) {
        errorCode = ERROR_INVALID_SIZE;
        return NULL;
    }

    long alignedSize = alignNumber(size);
    Cluster* cluster = findClusterByStart(ptr);

    if (cluster == NULL) {
        errorCode = ERROR_INVALID_POINTER;
        return NULL;
    }

    if (alignedSize == cluster->size) return ptr;
    if (alignedSize < cluster->size) {
        int exitCode = reserveCluster(cluster, size);
        if (exitCode == -1) return NULL;
        return ptr;
    }

    void* oldClusterStart = cluster->start;
    long oldClusterSize = cluster->size;

    freeCluster(cluster);
    void* newClusterStart = asm_alloc(alignedSize);

    memmove(newClusterStart, oldClusterStart, oldClusterSize);
    deleteUselessClusters();

    return newClusterStart;
}

int asm_free(void* ptr) {
    /*
     *  1. Free the current cluster (freeCluster())
     *  2. If the last cluster is free delete it (deleteLastClusterIfEmpty())
     */

    if (ptr == NULL) {
        errorCode = ERROR_NULL_POINTER;
        return -1;
    }

    Cluster* cluster = findClusterByStart(ptr);

    if (cluster == NULL) {
        errorCode = ERROR_INVALID_POINTER;
        return -1;
    }

    freeCluster(cluster);
    deleteUselessClusters();

    return 0;
}

void init_allocator() {
    clusterCount = 0;
    allocMemoryAppendix = INITIAL_ALLOC_MEMORY_APPENDIX;

    /*
     * 1. Allocate new memory for the clustersCluster
     * 2. Set the clustersCluster variable
     * 3. Set the clusters variable
     */

    long reserveBytes = CLUSTER_LIST_APPENDIX * CLUSTER_SIZE;
    void* clustersClusterStart = reserveMemory(reserveBytes);

    if (clustersClusterStart == NULL)
        fprintf(stderr, "Failed to initialize the allocator: SYS_BRK error.");

    clusters = clustersClusterStart;
    clustersCluster.start = clustersClusterStart;
    clustersCluster.size = reserveBytes;
}

int set_alloc_memory_appendix(long value) {
    if (value <= 0) {
        errorCode = ERROR_INVALID_SIZE;
        return -1;
    }

    allocMemoryAppendix = alignNumber(value);

    return 0;
}

int get_alloc_error_code() {
    return errorCode;
}

// region Helper
void* reserveMemory(long size) {
    /*
     * 1. Get the current system break
     * 2. Add 'size' bytes to it
     * 3. Set the system break to the new address
     * 4. Return the starting address (previous system break)
     */

    void* currentSystemBreak = CURRENT_BRK;
    void* newSystemBreak = SYS_BRK(currentSystemBreak + size);

    if (newSystemBreak == currentSystemBreak) {
        errorCode = ERROR_SYS_BRK_ERR;
        return NULL;
    }

    return currentSystemBreak;
}

void freeMemory(void* newEnd) {
    /*
     * Set the system break to the new end
     */

    SYS_BRK(newEnd);
}

Cluster* freeClusterForSize(long size) {
    /*
     * 1. Set variables for the currently selected cluster and its size (min size)
     * 2. For every cluster:
     *      a. If reserved continue
     *      b. If its size < parameter size continue
     *      c. If the size is lower the current minimum size:
     *          - set the selected cluster to the current one (+ its size)
     *  3. Return the selected cluster or null
     */

    Cluster* selectedCluster = NULL;
    long minSize = LONG_MAX;

    for (long i = 0; i < clusterCount; i++) {
        Cluster* currentCluster = &clusters[i];

        if (currentCluster->reserved) continue;
        if (currentCluster->size < size) continue;

        if (currentCluster->size >= minSize) continue;

        minSize = currentCluster->size;
        selectedCluster = currentCluster;
    }

    return selectedCluster;
}

Cluster* findClusterByStart(void* start) {
    /*
     * For every cluster:
     *      - If its start == parameter start return it
     * If no clusters found return null
     */

    for (long i = 0; i < clusterCount; i++) {
        Cluster* currentCluster = &clusters[i];

        if (currentCluster->start == start) return currentCluster;
    }

    return NULL;
}

Cluster* findClusterByEnd(void* end) {
    /*
     * For every cluster:
     *      - If its end == parameter end return it
     * If no clusters found return null
     */

    for (long i = 0; i < clusterCount; i++) {
        Cluster* currentCluster = &clusters[i];
        void* currentEnd = currentCluster->start + currentCluster->size;

        if (currentEnd == end) return currentCluster;
    }

    return NULL;
}

void joinClusters(Cluster* finalCluster, Cluster* appendedCluster) {
    /*
     * 1. Check if the clusters are directly after each other
     * 2. Add the appendedCluster's size to the finalCluster's size
     * 3. Remove the appendedCluster from the list
     */

    void* finalClusterEnd = finalCluster->start + finalCluster->size;
    if (finalClusterEnd != appendedCluster->start) return; // error?

    finalCluster->size += appendedCluster->size;
    removeCluster(appendedCluster);
}

Cluster* addCluster(void* start, long size) {
    /*
     * 1. Increase the clusterCount variable
     * 2. If the clustersCluster isn't full:
     *      (compare it's size with the clusterCount * cluster byte size)
     *      a. Reallocate the clusters cluster
     * 3. Set the cluster at index [clusterCount - 1]
     * 4. Return the cluster
     */

    clusterCount++;

    long currentClustersClusterSize = clusterCount * CLUSTER_SIZE;
    if (clustersCluster.size < currentClustersClusterSize) {
        int exitCode = reallocClustersCluster();
        if (exitCode == -1) return NULL;
    }

    Cluster* cluster = &clusters[clusterCount - 1];

    cluster->start = start;
    cluster->size = size;
    cluster->reserved = false;

    joinNeighbourClusters(cluster);

    return cluster;
}

void joinNeighbourClusters(Cluster* cl) {
    /*
     * 0. Check if the cluster is free
     * 1. Find the next cluster
     * 2. Find the previous cluster
     * 3. If the next cluster exists and is free join it
     * 4. If the previous cluster exists and is free join it
     */

    if (cl->reserved) return;

    Cluster* nextCluster = findClusterByStart(cl->start + cl->size);
    Cluster* previousCluster = findClusterByEnd(cl->start);

    if (nextCluster != NULL && !nextCluster->reserved)
        joinClusters(cl, nextCluster);

    if (previousCluster != NULL && !previousCluster->reserved)
        joinClusters(cl, previousCluster);
}

void removeCluster(Cluster* cl) {
    /*
     * 1. Find the index of the deleted cluster
     * 2. Copy all memory of the next clusters one space back
     * 3. Decrease the clusterCount variable
     */
    long i;

    for (i = 0; i < clusterCount; i++) {
        Cluster* currentCluster = &clusters[i];

        if (currentCluster->start == cl->start) break;
    }
    if (i == clusterCount) return; // ERR?

    long bytesToCopy = (clusterCount - i - 1) * CLUSTER_SIZE;

    if (bytesToCopy != 0) {
        memcpy(&clusters[i], &clusters[i + 1], bytesToCopy);
        joinNeighbourClusters(&clusters[i]);
    }

    clusterCount--;
}

int reserveCluster(Cluster* cl, long size) {
    /*
     * 1. Set cluster as reserved
     * 2. If cluster size == parameter size just return
     * 3. Compute the start address of the new cluster (cl.start + size)
     * 4. Compute the size of the new cluster (cl.size - size)
     * 5. Set the current cluster size to the parameter size
     * 6. Create a new free cluster with the computed start and size
     */

    cl->reserved = true;
    if (cl->size == size) return 0;

    void* newClusterStart = cl->start + size;
    long newClusterSize = cl->size - size;

    cl->size = size;
    Cluster* newCluster = addCluster(newClusterStart, newClusterSize);

    if (newCluster == NULL) return -1;

    return 0;
}

void freeCluster(Cluster* cl) {
    /*
     * 1. Set cl.reserved to false
     * 2. Join the next cluster and the previous cluster if they are free
     */

    cl->reserved = false;
    joinNeighbourClusters(cl);
}

void deleteUselessClusters() {
    /**
     * 1. Find a cluster with the highest start address
     * 2. If the cluster is free and its size is bigger then 2 x 'allocMemoryAppendix' shrink it using freeMemory()
     * 3. Set the cluster size to 'allocMemoryAppendix'
     */

    Cluster* lastCluster = NULL;
    void* highestAddress = NULL;

    for (long i = 0; i < clusterCount; i++) {
        Cluster* currentCluster = &clusters[i];

        if (currentCluster->start <= highestAddress) continue;

        highestAddress = currentCluster->start;
        lastCluster = currentCluster;
    }

    if (lastCluster == NULL || lastCluster->reserved) return;
    // if the clusters cluster is the last cluster
    if (clustersCluster.start > highestAddress) return;

    long maxSize = ALLOWED_FREE_MEMORY_COEFFICIENT * allocMemoryAppendix;

    if (lastCluster->size <= maxSize) return;

    void* newClusterEnd = lastCluster->start + maxSize;
    freeMemory(newClusterEnd);

    lastCluster->size = maxSize;
}

int reallocClustersCluster() {
    /*
     * 1. Reserve new memory with the old size + appendix
     * 2. Copy the data from old -> new
     * 4. Set the clustersCluster and clusters variable
     * 3. Append the old cluster to the clusters list
     */

    long newSize = clustersCluster.size + CLUSTER_LIST_APPENDIX * CLUSTER_SIZE;
    void* newMemory = reserveMemory(newSize);

    if (newMemory == NULL) return -1;

    memmove(newMemory, clustersCluster.start, clustersCluster.size);

    void* oldClustersClusterStart = clustersCluster.start;
    long oldClustersClusterSize = clustersCluster.size;

    clusters = newMemory;
    clustersCluster.start = newMemory;
    clustersCluster.size = newSize;

    Cluster* newCluster = addCluster(oldClustersClusterStart, oldClustersClusterSize);
    if (newCluster == NULL) return -1;

    return 0;
}

long alignNumber(long value) {
    if (value % ALIGN_TO_BYTE == 0) return value;
    /*
     * & ~3 will AND the value with 11..1100 (it will set the two last bits to 0
     * ==> the number will be divisible by 4
     */
    return (value + ALIGN_TO_BYTE) & ~(ALIGN_TO_BYTE - 1); // +4 -> it doesn't decrease
}
// endregion
#pragma clang diagnostic pop
#pragma clang diagnostic pop