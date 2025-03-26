;; Constants
%define ERROR_NULL_POINTER 1
%define ERROR_INVALID_POINTER 2
%define ERROR_INVALID_SIZE 3
%define ERROR_SYS_BRK_ERR 4

%define SYS_EXIT 1
%define SYS_WRITE 4
%define SYS_BRK 45
%define STDERR_FILENO 2

%define MINUS_ONE 0xFFFFFFFF
%define NULL_PTR 0x0
%define TRUE 1
%define FALSE 0

%define LONG_MAX 0xFFFFFFFF
%define STRING_END 0x0
%define NEWLINE 0xa

%define INITIAL_ALLOC_MEMORY_APPENDIX 2048
%define CLUSTER_LIST_APPENDIX 50
%define ALIGN_TO_BYTE 4
%define ALLOWED_FREE_MEMORY_COEFFICIENT 2

%define CLUSTER_SIZE 12
%define CLUSTER_START_INDEX 0
%define CLUSTER_SIZE_INDEX 4
%define CLUSTER_RESERVED_INDEX 8

%define CLUSTER_LIST_BYTE_APPENDIX (CLUSTER_LIST_APPENDIX * CLUSTER_SIZE)

%define PARAM_1 [ebp + 8]
%define PARAM_2 [ebp + 12]

;; Macros
%macro fun 0
push ebp
mov ebp, esp
%endmacro

%macro return 0
mov esp, ebp
pop ebp
ret
%endmacro

;; Code

section .data
; Error message
allocatorFailMessage db "Failed to initialize the allocator: SYS_BRK error.", NEWLINE, STRING_END

section .bss
clusters resb 4 ; Cluster** = list of clusters
clusterCount resb 4 ; long = number of clusters
clustersCluster resb CLUSTER_SIZE ; Cluster* = the cluster for the cluster list

allocMemoryAppendix resb 4 ; long = the number of bytes to reserve at once
errorCode resb 4 ; int = the error code

section .text
global alloc
global realloc
global free
global init_allocator
global set_alloc_memory_appendix
global get_alloc_error_code

extern memmove
extern strlen

alloc: ; allocates 'size' bytes
    fun ; void* alloc(long size)

    ; 1. Find a free cluster with the lowest size difference
    ; 2. If no cluster, create a new cluster and add it
    ; 3. Reserve the cluster
    ; 4. Return the cluster start address

    ; If the size is invalid, return an error
    cmp dword PARAM_1, 0 ; if (size <= 0) jmp .allocInvalidSize
    jbe .allocInvalidSize

    ; Allocate new space for local variables:
    ;   long alignedSize: [esp]
    ;   Cluster* cluster: [esp + 4]
    sub esp, 8;

    ; Align the number { alignedSize = _alignNumber(size) }
    push dword PARAM_1 ; set the parameter 'size' as size
    call _alignNumber ; eax = _alignNumber(size)
    add esp, 4 ; clear the stack
    mov [esp], eax ; set alignedSize = return value

    ; Find the cluster { cluster = _freeClusterForSize(alignedSize) }
    push dword [esp] ; set the parameter 'size' as alignedSize
    call _freeClusterForSize ; eax = _freeClusterForSize(alignedSize)
    add esp, 4 ; clear the stack
    mov [esp + 4], eax ; set cluster = return value

    ; Check if the cluster was found
    cmp dword [esp + 4], NULL_PTR ; if (cluster != NULL) jmp .allocReserveCluster
    jne .allocReserveCluster

        ; Reserve new memory for the cluster { void* newClusterStart = _reserveMemory(allocMemoryAppendix) }
        ;   void* newClusterStart: [eax]
        push dword [allocMemoryAppendix] ; set parameter 'size' as allocMemoryAppendix
        call _reserveMemory ; eax = _reserveMemory(allocMemoryAppendix)
        add esp, 4 ; clear the stack

        ; If the cluster is invalid return NULL
        cmp eax, NULL_PTR ; if (newClusterStart == NULL) jmp .allocReturnNull
        je .allocReturnNull

        ; Add the new cluster and set the cluster variable { cluster = _addCluster(newClusterStart, allocMemoryAppendix) }
        push dword [allocMemoryAppendix] ; set parameter 'size' as allocMemoryAppendix
        push eax ; set parameter 'start' as newClusterStart
        call _addCluster ; eax = _addCluster(newClusterStart, allocMemoryAppendix)
        add esp, 8 ; clear the stack
        mov [esp + 4], eax ; set cluster = return value

        ; If the cluster is invalid return NULL
        cmp eax, NULL_PTR ; if (cluster == NULL) jmp .allocReturnNull
        je .allocReturnNull

    .allocReserveCluster:

    ; Reserve the cluster and save an exit code { int exitCode = _reserveCluster(cluster, alignedSize) }
    ;   int exitCode: [eax]
    mov ebx, [esp + 4] ; ebx = cluster
    push dword [esp] ; set parameter 'size' as alignedSize
    push ebx ; set parameter 'cl' as cluster
    call _reserveCluster ; eax = _reserveCluster(cluster, alignedSize)
    add esp, 8 ; clear the stack

    ; If _reserveCluster() fails return NULL
    cmp eax, MINUS_ONE ; if (exitCode == -1) jmp .allocReturnNull
    je .allocReturnNull

    ; Return the start address of the cluster
    mov ebx, [esp + 4] ; ebx = cluster
    mov eax, [ebx + CLUSTER_START_INDEX] ; return ebx->start

    return

    .allocInvalidSize:
        mov dword [errorCode], ERROR_INVALID_SIZE ; set the error code
        jmp .allocReturnNull

    .allocReturnNull:
        mov eax, NULL_PTR ; return NULL
        return

realloc: ; reallocates pointer 'ptr' to match the size 'size'
    fun ; void* realloc(void* ptr, long size)

    ; 1. If the size parameter is lower than the cluster size
    ;      - reserve the cluster again to split it
    ; 2. Free the current cluster (freeCluster())
    ; 3. Allocate a new cluster for the size
    ; 4. Safely copy the memory
    ; 5. Delete the last cluster if empty
    ; 6. Return the start address

    ; If the pointer is NULL, return an error
    cmp dword PARAM_1, NULL_PTR ; if (ptr == NULL) jmp .reallocNullPointer
    je .reallocNullPointer

    ; If the size is invalid, return an error
    cmp dword PARAM_2, 0 ; if (size <= 0) jmp .reallocInvalidSize
    jbe .reallocInvalidSize

    ; Allocate new space for local variables:
    ;   long alignedSize: [esp]
    ;   Cluster* cluster: [esp + 4]
    ;   void* oldClusterStart: [esp + 8]
    ;   long oldClusterSize: [esp + 12]
    ;   void* newClusterStart: [esp + 16]
    sub esp, 20

    ; Align the number { alignedSize = _alignNumber(size) }
    push dword PARAM_2 ; set the parameter 'size' as size
    call _alignNumber ; eax = _alignNumber(size)
    add esp, 4 ; clear the stack
    mov [esp], eax ; set alignedSize = return value

    ; Find the cluster { cluster = _findClusterByStart(ptr) }
    push dword PARAM_1 ; set the parameter 'start' as ptr
    call _findClusterByStart ; eax = _findClusterByStart(ptr)
    add esp, 4 ; clear the stack
    mov [esp + 4], eax ; set cluster = return value

    ; If the cluster is invalid, return an error
    cmp dword [esp + 4], NULL_PTR ; if (cluster == NULL) jmp .reallocInvalidPointer
    je .reallocInvalidPointer

    ; If the target size equals the cluster size return the pointer without any changes
    mov ebx, [esp + 4] ; ebx = cluster
    mov edx, [esp] ; edx = alignedSize
    cmp edx, [ebx + CLUSTER_SIZE_INDEX] ; if (edx == ebx->size) jmp .reallocReturnPtr
    je .reallocReturnPtr

    ; If the target size is lower the cluster size re-reserve the cluster, else allocate a new one
    jae .reallocNewCluster ; if (alignedSize >= cluster->size) jmp .reallocNewCluster ((flag set from previous cmp))

        ; Reserve the current cluster and save an exit code { int exitCode = _reserveCluster(cluster, alignedSize) }
        ;   int exitCode: [eax]
        mov ebx, [esp + 4] ; ebx = cluster
        push dword [esp] ; set parameter 'size' as alignedSize
        push ebx ; set parameter 'cl' as cluster
        call _reserveCluster ; eax = _reserveCluster(cluster, alignedSize)
        add esp, 8 ; clear the stack

        ; If _reserveCluster() fails return NULL
        cmp eax, MINUS_ONE ; if (exitCode == -1) jmp .reallocReturnNull
        je .reallocReturnNull

        ; Return the current pointer
        jmp .reallocReturnPtr

    .reallocNewCluster:

    ; Save the old cluster start and size into the local variables oldClusterStart and oldClusterSize
    mov ebx, [esp + 4] ; ebx = cluster
    mov edx, [ebx + CLUSTER_START_INDEX] ; edx = ebx->start
    mov [esp + 8], edx ; oldClusterStart = edx (cluster->start)
    mov edx, [ebx + CLUSTER_SIZE_INDEX] ; edx = ebx->size
    mov [esp + 12], edx ; oldClusterSize = edx (cluster->size)

    ; Free the cluster { _freeCluster(cluster) }
    push dword [esp + 4] ; set parameter 'cl' as cluster
    call _freeCluster ; _freeCluster(cluster)
    add esp, 4 ; clear the stack

    ; Allocate a new cluster and save its start into newClusterStart variable { newClusterStart = alloc(alignedSize) }
    push dword [esp] ; set parameter 'size' as alignedSize
    call alloc ; eax = alloc(alignedSize)
    add esp, 4 ; clear the stack
    mov [esp + 16], eax ; set newClusterStart = return value

    ; Move 'oldClusterSize' bytes from oldClusterStart into newClusterStart { memmove(newClusterStart, oldClusterStart, oldClusterSize) }
    mov ebx, [esp + 8] ; ebx = oldClusterStart
    push dword [esp + 12] ; set parameter 'size' as oldClusterSize
    push ebx ; set parameter 'src' as oldClusterStart
    push eax ; set parameter 'dest' as newClusterStart (still the return value from the previous call)
    call memmove ; memmove(newClusterStart, oldClusterStart, oldClusterSize)
    add esp, 12 ; clear the stack

    ; Delete the last cluster's overflowing memory if possible { _deleteUselessMemory() }
    call _deleteUselessMemory ; _deleteUselessMemory()

    ; Return the new cluster start
    mov eax, [esp + 16] ; return newClusterStart

    return

    .reallocReturnPtr:
        mov eax, PARAM_1 ; return ptr
        return

    .reallocInvalidPointer:
        mov dword [errorCode], ERROR_INVALID_POINTER ; set the error code
        jmp .reallocReturnNull

    .reallocInvalidSize:
        mov dword [errorCode], ERROR_INVALID_SIZE ; set the error code
        jmp .reallocReturnNull

    .reallocNullPointer:
        mov dword [errorCode], ERROR_NULL_POINTER ; set the error code
        jmp .reallocReturnNull

    .reallocReturnNull:
        mov eax, NULL_PTR ; return NULL
        return

free: ; frees pointer 'ptr', returns -1 if fails and 0 if succeeds
    fun ; int free(void* ptr)

    ; 1. Free the current cluster (freeCluster())
    ; 2. If the last cluster is free delete it (deleteLastClusterIfEmpty())

    ; If the pointer is NULL, return an error
    cmp dword PARAM_1, NULL_PTR ; if (ptr == NULL) jmp .freeNullPointer
    je .freeNullPointer

    ; Allocate new space for local variables:
    ;   Cluster* cluster: [esp]
    sub esp, 4

    ; Find the cluster { cluster = _findClusterByStart(ptr) }
    push dword PARAM_1 ; set the parameter 'start' as ptr
    call _findClusterByStart ; eax = _findClusterByStart(ptr)
    add esp, 4 ; clear the stack
    mov [esp], eax ; set cluster = return value\

    ; If the cluster is invalid, return an error
    cmp dword [esp], NULL_PTR ; if (cluster == NULL) jmp .freeInvalidPointer
    je .freeInvalidPointer

    ; Free the cluster { _freeCluster(cluster) }
    push dword [esp] ; set parameter 'cl' as cluster
    call _freeCluster ; _freeCluster(cluster)
    add esp, 4 ; clear the stack

    ; Delete the last cluster's overflowing memory if possible { _deleteUselessMemory() }
    call _deleteUselessMemory ; _deleteUselessMemory()

    ; Return success
    mov eax, 0 ; return 0

    return

    .freeNullPointer:
        mov dword [errorCode], ERROR_NULL_POINTER ; set the error code
        mov eax, MINUS_ONE ; return -1
        return
    .freeInvalidPointer:
        mov dword [errorCode], ERROR_INVALID_POINTER ; set the error code
        mov eax, MINUS_ONE ; return -1
        return

init_allocator: ; initializes the allocator
    fun ; void init_allocator()

    ; 1. Initialize the global variables
    ; 2. Allocate new memory for the clustersCluster
    ; 3. Set the clustersCluster variable
    ; 4. Set the clusters variable

    ; Initialize the global variables with their default values
    mov dword [clusterCount], 0 ; set clusterCount = 0
    mov dword [allocMemoryAppendix], INITIAL_ALLOC_MEMORY_APPENDIX ; set allocMemoryAppendix = INITIAL_ALLOC_MEMORY_APPENDIX

    ; Reserve new memory and save into clustersClusterStart { void* clustersClusterStart = _reserveMemory(CLUSTER_LIST_BYTE_APPENDIX) }
    ;   void* clustersClusterStart: [eax]
    push dword CLUSTER_LIST_BYTE_APPENDIX ; set parameter 'size' as CLUSTER_LIST_BYTE_APPENDIX
    call _reserveMemory ; eax = _reserveMemory(CLUSTER_LIST_BYTE_APPENDIX)
    add esp, 4 ; clear the stack

    ; Check if _reserveMemory() failed
    cmp eax, NULL_PTR ; if (clustersClusterStart == NULL) jmp .iaInitFail
    je .iaInitFail

    ; Set the 'clusters' global variable to clustersClusterStart
    mov [clusters], eax ; clusters = clustersClusterStart

    ; Set the 'clustersCluster' global variable
    mov ebx, [esp] ; ebx = reservedBytes
    mov [clustersCluster + CLUSTER_START_INDEX], eax ; clustersCluster.start = clustersClusterStart
    mov dword [clustersCluster + CLUSTER_SIZE_INDEX], CLUSTER_LIST_BYTE_APPENDIX ; clustersCluster.size = CLUSTER_LIST_BYTE_APPENDIX

    return

    .iaInitFail: ; prints an error and exits
        ; Compute the length of the error message
        push allocatorFailMessage ; set parameter 'str' as allocatorFailMessage
        call strlen ; eax = strlen(allocatorFailMessage)
        add esp, 4 ; clear the stack

        ; Write the messsage into stderr
        mov edx, eax ; length = computed length
        mov ecx, allocatorFailMessage ; data = allocatorFailMessage
        mov ebx, STDERR_FILENO ; output stream = stderr
        mov eax, SYS_WRITE ; syscall = sys_write
        int 0x80 ; interrupt

        ; Exit
        mov ebx, 1 ; exit code = 1
        mov eax, SYS_EXIT ; syscall = sys_exit
        int 0x80 ; interrupt

set_alloc_memory_appendix: ; sets the allocation memory appendix variable
    fun ; int set_alloc_memory_appendix(long value)

    ; If the value is invalid, return an error
    cmp dword PARAM_1, 0 ; if (value <= 0) jmp .samaInvalidValue
    jbe .samaInvalidValue

    ; Set the global variable to the aligned value { allocMemoryAppendix = _alignNumber(value) }
    push dword PARAM_1 ; set the parameter 'size' as value
    call _alignNumber ; eax = _alignNumber(value)
    add esp, 4 ; clear the stack
    mov [allocMemoryAppendix], eax ; set allocMemoryAppendix = return value

    ; Return success
    mov eax, 0 ; return 0

    return

    .samaInvalidValue:
        mov dword [errorCode], ERROR_INVALID_SIZE ; set the error code
        mov eax, MINUS_ONE ; return -1
        return

get_alloc_error_code: ; int get_alloc_error_code() - returns the error code
    mov eax, [errorCode]
    ret

;; Helper functions
_reserveMemory: ; reserves 'size' number of bytes in the memory (moves the program break)
    fun ; void* _reserveMemory(long size)

    ; 1. Get the current system break
    ; 2. Add 'size' bytes to it
    ; 3. Set the system break to the new address
    ; 4. Return the starting address (previous system break)

    ; Allocate new space for local variables:
    ;   void* currentSystemBreak: [esp]
    sub esp, 4

    ; Get the current system break and set currentSystemBreak variable { currentSystemBreak = sys_brk(0) }
    mov ebx, 0 ; address = some invalid address -> sys_brk() will return the current break address
    mov eax, SYS_BRK ; syscall = sys_brk
    int 0x80 ; interrupt -> eax = sys_brk(0)
    mov [esp], eax ; set currentSystemBreak = return value

    ; Move the system break and save the new highest address { void* newSystemBreak = sys_brk(currentSystemBreak + size) }
    ;   void* newSystemBreak: [eax]
    add eax, PARAM_1 ; eax += size (calculate the new system break, eax still has the value of currentSystemBreak)
    mov ebx, eax ; address = the new address
    mov eax, SYS_BRK ; syscall = sys_brk
    int 0x80 ; interrupt -> eax (newSystemBreak) = sys_brk(currentSystemBreak + size)

    ; Check if the system break moved
    cmp eax, [esp] ; if (newSystemBreak == currentSystemBreak) jmp .rmError
    je .rmError

    ; Return the previous system break as the start address of the new cluster
    mov eax, [esp] ; return currentSystemBreak

    return

    .rmError:
        mov dword [errorCode], ERROR_SYS_BRK_ERR ; set the error code
        mov eax, NULL_PTR ; return NULL
        return

_freeMemory: ; sets the system break to 'newEnd'
    fun ; void _freeMemory(void* newEnd)

    ; Set the system break
    mov ebx, PARAM_1 ; address = newEnd
    mov eax, SYS_BRK ; syscall = sys_brk
    int 0x80 ; interrupt

    return

_freeClusterForSize: ; returns an empty cluster for the specified 'size' or NULL if no cluster found
    fun ; Cluster* _freeClusterForSize(long size)

    ; 1. Set variables for the currently selected cluster and its size (min size)
    ; 2. For every cluster:
    ;      a. If reserved continue
    ;      b. If its size < parameter size continue
    ;      c. If the size is lower the current minimum size:
    ;          - set the selected cluster to the current one (+ its size)
    ;  3. Return the selected cluster or NULL

    ; Allocate new space for local variables:
    ;   Cluster* selectedCluster: [esp]
    ;   long minSize: [esp + 4]
    sub esp, 8

    ; Initialize the local variables
    mov dword [esp], NULL_PTR ; selectedCluster = NULL
    mov dword [esp + 4], LONG_MAX ; minSize = LONG_MAX

    ; Go through every cluster { for (long i = 0; i < clusterCount; i++) }
    ;   long i: [ecx]
    mov ecx, 0 ; i = 0
    .fcfsLoop1:
        cmp ecx, [clusterCount] ; if (i >= clusterCount) break
        jae .fcfsExitLoop1

        ; Compute the real index { long realIndex = i * CLUSTER_SIZE }
        ;   long realIndex: [eax]
        mov eax, CLUSTER_SIZE
        mul ecx ; eax = ecx * CLUSTER_SIZE

        ; Get the current cluster { Cluster* currentCluster = &clusters[realIndex] }
        ;   Cluster* currentCluster: [ebx]
        mov ebx, [clusters] ; ebx = clusters
        lea ebx, [ebx + eax] ; ebx = &ebx[eax] = &clusters[realIndex]

        ; If the cluster is reserved continue the loop
        cmp byte [ebx + CLUSTER_RESERVED_INDEX], TRUE ; if (currentCluster->reserved == TRUE) continue
        je .fcfsContinueLoop1

        ; If the cluster size is lower than the parameter size continue
        mov edx, PARAM_1 ; edx = size
        cmp [ebx + CLUSTER_SIZE_INDEX], edx ; if (currentCluster->size < edx) continue
        jb .fcfsContinueLoop1

        ; If the cluster size is greater or equal to the minimal size continue
        mov edx, [esp + 4] ; edx = minSize
        cmp [ebx + CLUSTER_SIZE_INDEX], edx ; if (currentCluster->size >= edx) continue
        jae .fcfsContinueLoop1

        ; Set the minimum size and the selected cluster
        mov edx, [ebx + CLUSTER_SIZE_INDEX] ; edx = cluster->size
        mov [esp + 4], edx ; minSize = edx = cluster->size
        mov [esp], ebx ; selectedCluster = currentCluster

        .fcfsContinueLoop1:
        inc ecx ; i++
        jmp .fcfsLoop1 ; continue the loop
    .fcfsExitLoop1:

    ; Return the selected cluster
    mov eax, [esp] ; return selectedCluster

    return

_findClusterByStart: ; finds the cluster with same start as the 'start' parameter
    fun ; Cluster* _findClusterByStart(void* start)

    ; For every cluster:
    ;      - If its start == parameter start return it
    ; If no clusters found return NULL

    ; Go through every cluster { for (long i = 0; i < clusterCount; i++) }
    ;   long i: [ecx]
    mov ecx, 0 ; i = 0
    .fcfsLoop1:
        cmp ecx, [clusterCount] ; if (i >= clusterCount) break
        jae .fcfsExitLoop1

        ; Compute the real index { long realIndex = i * CLUSTER_SIZE }
        ;   long realIndex: [eax]
        mov eax, CLUSTER_SIZE
        mul ecx ; eax = ecx * CLUSTER_SIZE

        ; Get the current cluster { Cluster* currentCluster = &clusters[realIndex] }
        ;   Cluster* currentCluster: [ebx]
        mov ebx, [clusters] ; ebx = clusters
        lea ebx, [ebx + eax] ; ebx = &ebx[eax] = &clusters[realIndex]

        ; If the cluster start equals the parameter start return it
        mov edx, PARAM_1 ; edx = start
        cmp [ebx + CLUSTER_START_INDEX], edx ; if (currentCluster->start == edx) jmp .fcfsReturnCluster
        je .fcfsReturnCluster

        inc ecx ; i++
        jmp .fcfsLoop1 ; continue the loop
    .fcfsExitLoop1:

    ; No clusters -> returns NULL
    mov eax, NULL_PTR ; return NULL
    return

    .fcfsReturnCluster:
        ; Return the current cluster (in ebx)
        mov eax, ebx ; return currentCluster
        return

_findClusterByEnd: ; finds the cluster with same end as the 'end' parameter
    fun ; Cluster* _findClusterByEnd(void* end)

    ; For every cluster:
    ;      - If its end == parameter end return it
    ; If no clusters found return NULL

    ; Go through every cluster { for (long i = 0; i < clusterCount; i++) }
    ;   long i: [ecx]
    mov ecx, 0 ; i = 0
    .fcfeLoop1:
        cmp ecx, [clusterCount] ; if (i >= clusterCount) break
        jae .fcfeExitLoop1

        ; Compute the real index { long realIndex = i * CLUSTER_SIZE }
        ;   long realIndex: [eax]
        mov eax, CLUSTER_SIZE
        mul ecx ; eax = ecx * CLUSTER_SIZE

        ; Get the current cluster { Cluster* currentCluster = &clusters[realIndex] }
        ;   Cluster* currentCluster: [ebx]
        mov ebx, [clusters] ; ebx = clusters
        lea ebx, [ebx + eax] ; ebx = &ebx[eax] = &clusters[realIndex]

        ; Compute the cluster end { void* currentEnd = currentCluster->start + currentCluster->size }
        ;   void* currentEnd: [eax]
        mov eax, [ebx + CLUSTER_START_INDEX] ; eax = currentCluster->start
        add eax, [ebx + CLUSTER_SIZE_INDEX] ; eax += currentCluster-> size

        ; If the cluster end equals the parameter end return it
        mov edx, PARAM_1 ; edx = end
        cmp eax, edx ; if (currentEnd == edx) jmp .fcfsReturnCluster
        je .fcfeReturnCluster

        inc ecx ; i++
        jmp .fcfeLoop1 ; continue the loop
    .fcfeExitLoop1:

    ; No clusters -> returns NULL
    mov eax, NULL_PTR ; return NULL
    return

    .fcfeReturnCluster:
        ; Return the current cluster (in ebx)
        mov eax, ebx ; return currentCluster
        return

_joinClusters: ; joins the two clusters together
    fun ; void _joinClusters(Cluster* finalCluster, Cluster* appendedCluster)

    ; 1. Check if the clusters are directly after each other
    ; 2. Add the appendedCluster's size to the finalCluster's size
    ; 3. Remove the appendedCluster from the list

    ; Compute the end of the final cluster { void* finalClusterEnd = finalCluster->start + finalCluster->size }
    ;   void* finalClusterEnd: [eax]
    mov ebx, PARAM_1 ; ebx = finalCluster
    mov eax, [ebx + CLUSTER_START_INDEX] ; eax = ebx->start
    add eax, [ebx + CLUSTER_SIZE_INDEX] ; eax += ebx->size

    ; If the final cluster end isn't the same as the appendedCluster start return
    mov edx, PARAM_2 ; edx = appendedCluster
    cmp eax, [edx + CLUSTER_START_INDEX] ; if (finalClusterEnd != edx->start) jmp .jcReturn
    jne .jcReturn

    ; Add the appended cluster size to the final cluster size { finalCluster->size += appendedCluster->size }
    mov edx, [edx + CLUSTER_SIZE_INDEX] ; edx = appendedCluster->size
    add [ebx + CLUSTER_SIZE_INDEX], edx ; finalCluster->size += edx

    ; Remove the appended cluster { _removeCluster(appendedCluster) }
    push dword PARAM_2 ; set the parameter 'cl' to appendedCluster
    call _removeCluster ; _removeCluster(appendedCluster)
    add esp, 4 ; clear the stack (not needed, but keeps the format the same)

    .jcReturn:
    return

_addCluster: ; adds a new cluster to the cluster list
    fun ; Cluster* _addCluster(void* start, long size)

    ; 1. Increase the clusterCount variable
    ; 2. If the clustersCluster isn't full:
    ;      (compare it's size with the clusterCount * cluster byte size)
    ;      a. Reallocate the clusters cluster
    ; 3. Set the cluster at index [clusterCount - 1]
    ; 4. Return the cluster

    ; Increase the cluster count
    inc dword [clusterCount] ; clusterCount++

    ; Compute the current clustersCluster byte size { long currentClustersClusterSize = clusterCount * CLUSTER_SIZE }
    ;   long currentClustersClusterSize: [eax]
    mov eax, CLUSTER_SIZE ; eax = CLUSTER_SIZE
    mul dword [clusterCount] ; eax = eax * clusterCount

    ; If the current size is higher than the maximum size allocate new memory for the clusters cluster
    cmp [clustersCluster + CLUSTER_SIZE_INDEX], eax ; if (clustersCluster.size >= currentClustersClusterSize) jmp .acSetupCluster
    jae .acSetupCluster

        ; Reallocate the clusters cluster and save the exit code { int exitCode = _reallocClustersCluster() }
        ;   int exitCode: [eax]
        call _reallocClustersCluster ; eax = _reallocClustersCluster()

        ; If the reallocation failed return NULL
        cmp eax, MINUS_ONE ; if (exitCode == -1) jmp .acReturnNull
        je .acReturnNull

    .acSetupCluster:

    ; Compute the real index for the new cluster { long realIndex = (clusterCount - 1) * CLUSTER_SIZE }
    ;   long realIndex: [eax]
    mov eax, [clusterCount] ; eax = clusterCount
    dec eax ; eax-- (ecx = ecx - 1)
    mov ebx, CLUSTER_SIZE ; ebx = CLUSTER_SIZE
    mul ebx ; eax = eax * ebx = (clusterCount - 1) * CLUSTER_SIZE

    ; Get the new cluster pointer { Cluster* cluster = &clusters[realIndex] }
    ;   Cluster* cluster: [ebx]
    mov ebx, [clusters] ; ebx = clusters
    lea ebx, [ebx + eax] ; ebx = &ebx[realIndex]

    ; Set the cluster start as the parameter start { cluster->start = start }
    mov eax, PARAM_1 ; eax = start
    mov [ebx + CLUSTER_START_INDEX], eax ; cluster->start = eax

    ; Set the cluster size as the parameter size { cluster->size = size }
    mov eax, PARAM_2 ; eax = size
    mov [ebx + CLUSTER_SIZE_INDEX], eax ; cluster->size = eax

    ; Set the cluster as free { cluster->reserved = FALSE }
    mov byte [ebx + CLUSTER_RESERVED_INDEX], FALSE ; cluster->reserved = FALSE

    ; Join the neighbour clusters and return the result { return _joinNeighbourClusters(cluster) }
    push ebx ; set parameter 'cl' as cluster
    call _joinNeighbourClusters ; eax = _joinNeighbourClusters(cluster)
    add esp, 4 ; clear the stack

    return

    .acReturnNull:
        mov eax, NULL_PTR ; return NULL
        return

_joinNeighbourClusters: ; joins the cluster 'cl' with its next and previous clusters if they are free
    fun ; Cluster* _joinNeighbourClusters(Cluster* cl)

    ; 1. Check if the cluster is free
    ; 2. Find the next cluster
    ; 3. Find the previous cluster
    ; 4. If the next cluster exists and is free join it
    ; 5. If the previous cluster exists and is free join it

    ; If the cluster is reserved just return it
    mov ebx, PARAM_1 ; ebx = cl
    cmp byte [ebx + CLUSTER_RESERVED_INDEX], TRUE ; if (ebx->reserved == TRUE) jmp .jncReturnCl
    je .jncReturnCl

    ; Allocate new space for local variables:
    ;   Cluster* nextCluster: [esp]
    ;   Cluster* previousCluster: [esp + 4]
    sub esp, 8

    ; Find the next cluster by its start and set the variable { nextCluster = _findClusterByStart(cl->start + cl->size) }
    mov edx, [ebx + CLUSTER_START_INDEX] ; edx = cl->start (ebx is still cl)
    add edx, [ebx + CLUSTER_SIZE_INDEX] ; edx += cl->size
    push edx ; set parameter 'start' as the end of cl (cl->start + cl->size)
    call _findClusterByStart ; eax = _findClusterByStart(edx)
    add esp, 4 ; clear the stack
    mov [esp], eax ; set nextCluster = return value

    ; Find the previous cluster by its end and set the variable { previousCluster = _findClusterByEnd(cl->start) }
    mov ebx, PARAM_1 ; ebx = cl
    push dword [ebx + CLUSTER_START_INDEX] ; set parameter 'end' as ebx->start
    call _findClusterByEnd ; eax = _findClusterByEnd(cl->start)
    add esp, 4 ; clear the stack
    mov [esp + 4], eax ; set previousCluster = return value

    ; If the next cluster is NULL or reserved skip joining
    mov ebx, [esp] ; ebx = nextCluster
    cmp ebx, NULL_PTR ; if (ebx == NULL) jmp .jncCheckPrevious
    je .jncCheckPrevious
    cmp byte [ebx + CLUSTER_RESERVED_INDEX], TRUE ; if (ebx->reserved == TRUE) jmp .jncCheckPrevious
    je .jncCheckPrevious

        ; Join the cluster 'cl' with the next cluster { _joinClusters(cl, nextCluster) }
        push ebx ; set parameter 'appendedCluster' as nextCluster (ebx is still nextCluster)
        push dword PARAM_1 ; set parameter 'finalCluster' as cl
        call _joinClusters ; _joinClusters(cl, nextCluster)
        add esp, 8 ; clear the stack

    .jncCheckPrevious:

    ; If the previous cluster is NULL or reserved skip joining
    mov ebx, [esp + 4] ; ebx = previousCluster
    cmp ebx, NULL_PTR ; if (ebx == NULL) jmp .jncReturnCl
    je .jncReturnCl
    cmp byte [ebx + CLUSTER_RESERVED_INDEX], TRUE ; if (ebx->reserved == TRUE) jmp .jncReturnCl
    je .jncReturnCl

        ; Join the previous cluster with the cluster 'cl' { _joinClusters(previousCluster, cl) }
        push dword PARAM_1 ; set parameter 'appendedCluster' as cl
        push ebx ; set parameter 'finalCluster' as previousCluster (ebx is still previousCluster)
        call _joinClusters ; _joinClusters(cl, previousCluster)
        add esp, 8 ; clear the stack

    ; Return the previous cluster
    mov eax, [esp + 4] ; return previousCluster
    return

    .jncReturnCl:
        mov eax, PARAM_1 ; return cl
        return

_removeCluster: ; removes a cluster from the cluster list
    fun ; void _removeCluster(Cluster* cl)

    ; 1. Find the index of the deleted cluster
    ; 2. Copy all memory of the next clusters one space back
    ; 3. Decrease the clusterCount variable

    ; Allocate new space for local variables:
    ;   long finalRealIndex: [esp]
    sub esp, 4

    ; Go through every cluster { for (long i = 0; i < clusterCount; i++) }
    ;   long i: [ecx]
    mov ecx, 0 ; i = 0
    .rcLoop1:
        cmp ecx, [clusterCount] ; if (i >= clusterCount) jmp .rcReturn
        jae .rcReturn

        ; Compute the real index { long realIndex = i * CLUSTER_SIZE }
        ;   long realIndex: [eax]
        mov eax, CLUSTER_SIZE
        mul ecx ; eax = ecx * CLUSTER_SIZE

        ; Set the finalRealIndex variable
        mov [esp], eax ; finalRealIndex = realIndex

        ; Get the current cluster { Cluster* currentCluster = &clusters[realIndex] }
        ;   Cluster* currentCluster: [ebx]
        mov ebx, [clusters] ; ebx = clusters
        lea ebx, [ebx + eax] ; ebx = &ebx[eax] = &clusters[realIndex]

        ; If the current cluster start is the same as 'cl' start copy the bytes
        mov edx, PARAM_1 ; edx = cl
        mov edx, [edx + CLUSTER_START_INDEX] ; edx = edx->start
        cmp [ebx + CLUSTER_START_INDEX], edx ; if (currentCluster->start == edx) jmp .rcCopyBytes
        je .rcCopyBytes

        inc ecx ; i++
        jmp .rcLoop1 ; continue the loop

    .rcCopyBytes:

    ; Compute the number of bytes to copy { long bytesToCopy = clusterCount * CLUSTER_SIZE - realIndex - CLUSTER_SIZE }
    ;   long bytesToCopy: [eax]
    mov eax, [clusterCount] ; eax = clusterCount
    mov ebx, CLUSTER_SIZE ; ebx = CLUSTER_SIZE
    mul ebx ; eax = eax * ebx = clusterCount * CLUSTER_SIZE
    sub eax, [esp] ; eax -= realIndex = clusterCount * CLUSTER_SIZE - realIndex
    sub eax, CLUSTER_SIZE ; eax -= CLUSTER_SIZE = clusterCount * CLUSTER_SIZE - realIndex - CLUSTER_SIZE

    ; Copy only if bytesToCopy > 0
    cmp eax, 0 ; if (bytesToCopy <= 0) jmp .rcDecreaseCount
    jbe .rcDecreaseCount

        ; Copy 'bytesToCopy' bytes from 'cl + CLUSTER_SIZE' to 'cl' { memmove(cl, cl + CLUSTER_SIZE, bytesToCopy) }
        mov ebx, PARAM_1 ; ebx = cl
        add ebx, CLUSTER_SIZE ; ebx += CLUSTER_SIZE = cl + CLUSTER_SIZE
        push eax ; set parameter 'size' as bytesToCopy
        push ebx ; set parameter 'src' as cl + CLUSTER_SIZE
        push dword PARAM_1 ; set parameter 'dest' as cl
        call memmove ; memmove(cl, cl + CLUSTER_SIZE, bytesToCopy)
        add esp, 12 ; clear the stack

        ; Join the neighbour clusters
        push dword PARAM_1 ; set parameter 'cl' as cl
        call _joinNeighbourClusters ; _joinNeighbourClusters(cl)
        add esp, 4 ; clear the stack

    .rcDecreaseCount:
    dec dword [clusterCount] ; clusterCount--

    .rcReturn:
    return

_reserveCluster: ; sets the cluster as reserves and splits it if needed
    fun ; int _reserveCluster(Cluster* cl, long size)

    ; 1. Set cluster as reserved
    ; 2. If cluster size == parameter size just return
    ; 3. Compute the start address of the new cluster (cl.start + size)
    ; 4. Compute the size of the new cluster (cl.size - size)
    ; 5. Set the current cluster size to the parameter size
    ; 6. Create a new free cluster with the computed start and size

    ; Registers:
    ;   ebx = cl
    ;   ecx = size
    mov ebx, PARAM_1 ; ebx = cl
    mov ecx, PARAM_2 ; ecx = size

    ; Set the cluster as reserved
    mov byte [ebx + CLUSTER_RESERVED_INDEX], TRUE ; cl->reserved = TRUE

    ; If the size to reserve is the same as the cluster size, just return
    cmp [ebx + CLUSTER_SIZE_INDEX], ecx ; if (cl->size == ecx) jmp .recReturnSuccess
    je .recReturnSuccess

    ; Compute the new cluster start { void* newClusterStart = cl->start + size }
    ;   void* newClusterStart: [eax]
    mov eax, [ebx + CLUSTER_START_INDEX] ; eax = cl->start
    add eax, ecx ; eax += size = cl->start + size

    ; Compute the new cluster size { long newClusterSize = cl->size - size }
    ;   long newClusterSize: [edx]
    mov edx, [ebx + CLUSTER_SIZE_INDEX] ; edx = cl->size
    sub edx, ecx ; edx -= size = cl->size - size

    ; Set the cluster size to the parameter size
    mov [ebx + CLUSTER_SIZE_INDEX], ecx ; cl->size = size

    ; Add a new cluster with the start and size and save it { Cluster* newCluster = _addCluster(newClusterStart, newClusterSize) }
    ;   Cluster* newCluster: [eax]
    push edx ; set parameter 'size' as newClusterSize
    push eax ; set parameter 'start' as newClusterStart
    call _addCluster ; eax = _addCluster(newClusterSize, newClusterStart)
    add esp, 8 ; clear the stack

    ; If the new cluster is invalid return an error
    cmp eax, NULL_PTR ; if (newCluster == NULL) jmp .recReturnError
    je .recReturnError

    ; Return successfully
    .recReturnSuccess:
        mov eax, 0 ; return 0
        return
    .recReturnError:
        mov eax, MINUS_ONE ; return - 1
        return

_freeCluster: ; frees a cluster without deleting useless memory
    fun ; void _freeCluster(Cluster* cl)

     ; 1. Set cl.reserved to false
     ; 2. Join the next cluster and the previous cluster if they are free

    ; Save the cluster into ebx
    mov ebx, PARAM_1

    ; Set the cluster as free
    mov byte [ebx + CLUSTER_RESERVED_INDEX], FALSE ; cl->reserved = FALSE

    ; Join the neighbour clusters { _joinNeighbourClusters(cl) }
    push ebx ; set parameter 'cl' as cl
    call _joinNeighbourClusters ; _joinNeighbourClusters(cl)
    add esp, 4 ; clear the stack

    return

_deleteUselessMemory: ; shrinks the last cluster if it's too big a frees the memory
    fun

    ; 1. Find a cluster with the highest start address
    ; 2. If the cluster is free and its size is bigger then coefficient * 'allocMemoryAppendix' shrink it using freeMemory()
    ; 3. Set the cluster size to 'allocMemoryAppendix'

    ; Allocate new space for local variables:
    ;   Cluster* lastCluster: [esp]
    ;   void* highestAddress: [esp + 4]
    ;   long maxSize: [esp + 8]
    sub esp, 12

    ; Initialize the local variables
    mov dword [esp], NULL_PTR ; lastCluster = NULL
    mov dword [esp + 4], NULL_PTR ; highestAddress = NULL

    ; Go through every cluster { for (long i = 0; i < clusterCount; i++) }
    ;   long i: [ecx]
    mov ecx, 0 ; i = 0
    .dumLoop1:
        cmp ecx, [clusterCount] ; if (i >= clusterCount) break
        jae .dumExitLoop1

        ; Compute the real index { long realIndex = i * CLUSTER_SIZE }
        ;   long realIndex: [eax]
        mov eax, CLUSTER_SIZE
        mul ecx ; eax = ecx * CLUSTER_SIZE

        ; Get the current cluster { Cluster* currentCluster = &clusters[realIndex] }
        ;   Cluster* currentCluster: [ebx]
        mov ebx, [clusters] ; ebx = clusters
        lea ebx, [ebx + eax] ; ebx = &ebx[eax] = &clusters[realIndex]

        ; If the current cluster start address is lower or equal to the saved highest address continue
        mov edx, [esp + 4] ; edx = highestAddress
        cmp [ebx + CLUSTER_START_INDEX], edx ; if (currentCluster->start <= edx) continue
        jbe .dumContinueLoop1

        ; Set the highest address and the last cluster
        mov edx, [ebx + CLUSTER_START_INDEX] ; edx = currentCluster->start
        mov [esp + 4], edx ; highestAddress = edx
        mov [esp], ebx ; lastCluster = currentCluster

        .dumContinueLoop1:
        inc ecx ; i++
        jmp .dumLoop1 ; continue the loop
    .dumExitLoop1:

    ; If the last cluster is null or reserved return
    mov ebx, [esp] ; ebx = lastCluster
    cmp ebx, NULL_PTR ; if (ebx == NULL) jmp .dumReturn
    je .dumReturn
    cmp byte [ebx + CLUSTER_RESERVED_INDEX], TRUE ; if (ebx->reserved == TRUE) jmp .dumReturn
    je .dumReturn

    ; If the last cluster is the clustersCluster
    mov edx, [esp + 4] ; edx = highestAddress
    cmp [clustersCluster + CLUSTER_START_INDEX], edx ; if (clustersCluster.start > highestAddress) jmp .dumReturn
    ja .dumReturn

    ; Compute the maximum size free size for the last cluster { maxSize = ALLOWED_FREE_MEMORY_COEFFICIENT * allocMemoryAppendix }
    mov eax, ALLOWED_FREE_MEMORY_COEFFICIENT ; eax = ALLOWED_FREE_MEMORY_COEFFICIENT
    mul dword [allocMemoryAppendix] ; eax = eax * allocMemoryAppendix
    mov [esp + 8], eax ; eax = maxSize

    ; If the size of the last cluster is lower or equal to the max size, return
    cmp [ebx + CLUSTER_SIZE_INDEX], eax ; if (lastCluster->size <= maxSize) jmp .dumReturn (ebx is still lastCluster and eax still maxSize)
    jbe .dumReturn

    ; Compute the new cluster end and free the memory from that address { _freeMemory(lastCluster->start + maxSize) }
    add eax, [ebx + CLUSTER_SIZE_INDEX] ; eax = maxSize + lastCluster->start (eax is still maxSize and ebx still lastCluster)
    push eax ; set parameter 'newEnd' as maxSize + lastCluster->start
    call _freeMemory ; _freeMemory(maxSize + lastCluster->start)
    add esp, 4 ; clear the stack

    ; Set the size of the last cluster to the max size
    mov ebx, [esp] ; ebx = lastCluster
    mov edx, [esp + 8] ; edx = maxSize
    mov [ebx + CLUSTER_SIZE_INDEX], edx ; ebx->size = edx

    .dumReturn:
    return

_reallocClustersCluster: ; reallocates the clusters cluster to a new bigger memory address
    fun ; int _reallocClustersCluster()

    ; 1. Reserve new memory with the old size + appendix
    ; 2. Copy the data from old -> new
    ; 4. Set the clustersCluster and clusters variable
    ; 3. Append the old cluster to the clusters list

    ; Allocate new space for local variables:
    ;   long newSize: [esp]
    ;   void* newMemory: [esp + 4]
    sub esp, 8

    ; Compute the new size of the clustersCluster { newSize = clustersCluster.size + CLUSTER_LIST_BYTE_APPENDIX }
    mov eax, [clustersCluster + CLUSTER_SIZE_INDEX] ; eax = clustersCluster.size
    add eax, CLUSTER_LIST_BYTE_APPENDIX ; eax += CLUSTER_LIST_BYTE_APPENDIX
    mov [esp], eax ; newSize = eax = clustersCluster.size + CLUSTER_LIST_BYTE_APPENDIX

    ; Reserve new memory and save the start into the variable { newMemory = _reserveMemory(newSize) }
    push dword [esp] ; set parameter 'size' as newSize
    call _reserveMemory ; eax = _reserveMemory(newSize)
    add esp, 4 ; clear the stack
    mov [esp + 4], eax ; set newMemory = return value

    ; If the memory allocation failed return an error
    cmp eax, NULL_PTR ; if (eax == NULL) jmp .rccReturnError (eax is still newMemory)
    je .rccReturnError

    ; Move the old clusters cluster memory into the new memory { memmove(newMemory, clustersCluster.start, clustersCluster.size) }
    mov ebx, [esp + 4] ; ebx = newMemory
    push dword [clustersCluster + CLUSTER_SIZE_INDEX] ; set parameter 'size' as clustersCluster.size
    push dword [clustersCluster + CLUSTER_START_INDEX] ; set parameter 'src' as clustersCluster.start
    push ebx ; set parameter 'dest' as newMemory (=ebx)
    call memmove ; memmove(newMemory, clustersCluster.start, clustersCluster.size)
    add esp, 12 ; clear the stack

    ; Save the old clustersCluster start and size
    ; { void* oldClustersClusterStart = clustersCluster.start ; long oldClustersClusterSize = clustersCluster.size }
    ;   void* oldClustersClusterStart: [ebx]
    ;   long oldClustersClusterSize: [ecx]
    mov ebx, [clustersCluster + CLUSTER_START_INDEX]
    mov ecx, [clustersCluster + CLUSTER_SIZE_INDEX]

    ; Set the global variables
    ; { clusters = newMemory; clustersCluster.start = newMemory; clustersCluster.size = newSize }
    mov eax, [esp + 4] ; eax = newMemory
    mov edx, [esp] ; edx = newSize
    mov [clusters], eax ; clusters = eax = newMemory
    mov [clustersCluster + CLUSTER_START_INDEX], eax ; clustersCluster.start = eax = newMemory
    mov [clustersCluster + CLUSTER_SIZE_INDEX], edx ; clustersCluster.size = edx = newSize

    ; Add the old clusters cluster into the cluster list itself { Cluster* newCluster = _addCluster(oldClustersClusterStart, oldClustersClusterSize) }
    ;   Cluster* newCluster: [eax]
    push ecx ; set parameter 'size' as oldClustersClusterSize
    push ebx ; set parameter 'start' as oldClustersClusterStart
    call _addCluster ; eax = _addCluster(oldClustersClusterStart, oldClustersClusterSize)
    add esp, 8 ; clear the stack

    ; If adding the cluster failed return an error
    cmp eax, NULL_PTR ; if (newCluster == NULL) jmp .rccReturnError
    je .rccReturnError

    mov eax, 0 ; return 0
    return

    .rccReturnError:
        mov eax, MINUS_ONE ; return -1
        return

_alignNumber: ; aligns a number to 'ALIGN_TO_BYTE' bytes
    fun ; long alignNumber(long value)

    ; If the value is already aligned (= is divisible by) just return it
    mov edx, 0 ; division divides edx:eax, so edx must be 0
    mov eax, PARAM_1 ; eax = value
    mov ebx, ALIGN_TO_BYTE ; ebx = ALIGN_TO_BYTE
    div ebx ; eax, edx = edx:eax /% ebx => edx = value % ALIGN_TO_BYTE
    cmp edx, 0 ; if (edx != 0) jmp .anAlign
    jne .anAlign

        ; The value is aligned, return it
        mov eax, PARAM_1
        return

    .anAlign:

    ; for exanple AND with NOT 3 will AND with 11..1100 (it will set the two last bits to 0)
    ; ==> the number will be divisible by 4

    ; Return the aligned value { return (value + ALIGN_TO_BYTE) & ~(ALIGN_TO_BYTE - 1) }
    mov eax, PARAM_1 ; eax = value
    add eax, ALIGN_TO_BYTE ; eax += ALIGN_TO_BYTE ==> eax = value + ALIGN_TO_BYTE
    mov ebx, ALIGN_TO_BYTE ; ebx = ALIGN_TO_BYTE
    dec ebx ; ebx-- ==> ebx = ALIGN_TO_BYTE - 1
    not ebx ; ~ebx ==> ebx = ~(ALIGN_TO_BYTE - 1)
    and eax, ebx ; eax = eax & ebx ==> eax = (value + ALIGN_TO_BYTE) & ~(ALIGN_TO_BYTE - 1)

    ; Return value already in eax
    return