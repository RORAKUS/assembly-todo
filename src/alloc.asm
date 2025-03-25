%assign SYS_BRK 45 ; code for the brk() syscall

%assign INTEGER_MAX 0xFFFFFFFF
%assign NULL_PTR 0x0
%assign TRUE 1
%assign FALSE 0

%assign CLUSTER_STRUCT_SIZE 12 ; Cluster: 4 - start addr.; 4 - end addr.; 1 - reserved state; _3
%assign CLUSTER_LIST_APPENDIX 50
%assign INITIAL_ALLOC_MEMORY_APPENDIX 2000 ; the initial value for allocMemoryAppendix

%assign CLUSTER_START_ADDR_INDEX 0
%assign CLUSTER_END_ADDR_INDEX 4
%assign CLUSTER_IS_RESERVED_INDEX 8

%macro fun 0
push ebp
mov ebp, esp
%endmacro

%macro return 0
mov esp, ebp
pop ebp
%endmacro

section .data

section .bss
clusterListCluster resb CLUSTER_STRUCT_SIZE ; a cluster for the clusters list
clusters resb 4 ; the list of all clusters - Cluster**

clusterCount resb 4
allocMemoryAppendix resb 4 ; the number of bytes to reserve when calling sys_brk()

section .text
global alloc
global realloc
global free
global init_allocator
global set_alloc_memory_appendix

; Alloc:
;   - check free clusters, return the smallest fit, reserve
;   - if no free clusters, allocate new memory

; Realloc:
;   - if there is a free cluster at the end, just prolong it, reserve
;   - free and allocate again

; Free:
;   - just set the cluster as empty

alloc:
    fun ; void* alloc(int size) - allocates memory in 'size' bytes and returns the pointer to its start



    return

init_allocator:
    fun

    ; Initialize the variables
    mov dword [clusterCount], 0 ; initialize cluster count
    mov dword [allocMemoryAppendix], INITIAL_ALLOC_MEMORY_APPENDIX ; initialize memory appendix

    ; Allocate the initial cluster
    ;   - reserve new memory using _reverseBytes()
    ;   - set the cluster list pointer

    ; Multiply the byte size of the cluster by the count to get the number of bytes to reserve
    mov eax, CLUSTER_STRUCT_SIZE
    mov ebx, CLUSTER_LIST_APPENDIX
    mul ebx ; eax = CLUSTER_STRUCT_SIZE * CLUSTER_LIST_APPENDIX

    ; Call _reserveBytes(eax)
    push eax ; set the parameter, keep in [esp]
    call _reserveBytes ; returns eax = the starting address

    ; Set the start of the cluster list cluster data
    mov [clusterListCluster + CLUSTER_START_ADDR_INDEX], eax ; cluster start address = returned address from _reserveBytes()

    ; Set the clusters pointer to the start address of the cluster too
    mov [clusters], eax

    ; Set the end of the cluster list cluster data
    add eax, [esp] ; compute the end -> add byte size to the starting address
    sub eax, 4 ; substract 4 bytes to get the last dword address
    mov [clusterListCluster + CLUSTER_END_ADDR_INDEX], eax ; set the end

    return

set_alloc_memory_appendix:
    fun ; void set_alloc_memory_appendix(int value)

    mov eax, [ebp + 8] ; [ebp + 8] = param value
    mov [allocMemoryAppendix], eax

    return

;; Cluster list manip
_allocClusterList:
    fun ; void _allocClusterList() - allocates the cluster list and sets the cluster list cluster

    ; Reserve new memory using sys_brk()
    ; Set list cluster to the new memory
    ; Copy old data to the new location
    ; Add old list cluster to the list of normal clusters

    ; Compute the current byte size of the cluster list cluster
    mov ebx, [clusterListCluster + CLUSTER_END_ADDR_INDEX]
    sub ebx, [clusterListCluster + CLUSTER_START_ADDR_INDEX] ; ebx = cluster.end - cluster.start

    ; Multiply the amount of new items to reserve by their byte size
    mov eax, CLUSTER_STRUCT_SIZE
    mov ecx, CLUSTER_LIST_APPENDIX
    mul ecx ; eax = CLUSTER_STRUCT_SIZE * CLUSTER_LIST_APPENDIX

    ; Reserve ebx + eax bytes (current size + appendix)
    add eax, ebx
    push eax ; set parameter num = eax + ebx
    call _reserveBytes ; reserve the bytes; returns eax = start address

    ; Save the old cluster: [esp + 4] = end; [esp] = start ([esp + 8] = num)
    push dword [clusterListCluster + CLUSTER_END_ADDR_INDEX]
    push dword [clusterListCluster + CLUSTER_START_ADDR_INDEX]

    ; Set the cluster start to the newly created one
    mov [clusterListCluster + CLUSTER_START_ADDR_INDEX], eax ; start address = returned start address

    ; Set the clusters variable too
    mov [clusters], eax

    ; Set the cluster end
    add eax, [esp + 8] ; eax = start address + added bytes = end address + 4
    sub eax, 4 ; last dword address
    mov [clusterListCluster + CLUSTER_END_ADDR_INDEX], eax

    ; Copy the old data to the new one
    cld
    mov esi, [esp] ; source = old start
    mov edi, [clusterListCluster + CLUSTER_START_ADDR_INDEX] ; destination = new start

    mov ecx, [esp + 4]
    sub ecx, esi ; count = old end - old start
    rep movsb ; repeat byte copy until ecx = 0

    ; Add the old cluster to the cluster list
    call _addNewCluster ; the stack for parameters is already set

    return

_addNewCluster:
    fun ; void _addNewCluster(void* start, void* end)

    ; If cluster list capacity exceeded -> reallocate cluster list
    ; clusters[clusterCount] = { start, end, false }

    inc dword [clusterCount] ; clusterCount++

    ; Check if the cluster list is full
    ;   -> clusterCount (already incremented) * CLUSTER_STRUCT_SIZE > clusterListCluster.size

    ; Compute the current list size
    mov eax, [clusterCount]
    mov ebx, CLUSTER_STRUCT_SIZE
    mul ebx ; eax = clusterCount * CLUSTER_STRUCT_SIZE

    ; Compute the clusterListCluster size
    mov ebx, [clusterListCluster + CLUSTER_END_ADDR_INDEX]
    sub ebx, [clusterListCluster + CLUSTER_START_ADDR_INDEX] ; ebx = cluster.end - cluster.start

    ; Compare clusters.bytes and clusterListCluster.size
    cmp eax, ebx
    jbe .ancAppend ; if eax (cluster list byte size) <= ebx (maximum cluster list byte size) do not reserve new memory

    ; Reserve new memory for the cluster list
    push dword FALSE
    call _allocClusterList ; _allocClusterList(false) = reallocates the cluster list
    add esp, 4 ; clear the stack

    .ancAppend: ; appends the new cluster
        ; Get the new cluster address (Cluster* cl = [clusters + clusterCount * CLUSTER_STRUCT_SIZE]
        mov eax, [clusterCount]
        mov ebx, CLUSTER_STRUCT_SIZE
        mul ebx ; eax = eax (clusterCount) * ebx (CLUSTER_STRUCT_SIZE)
        mov ebx, [clusters]
        lea ebx, [ebx + eax] ; ebx = [clusters] + eax (index)

        ; Set the cluster start, end and reserved state
        mov eax, [ebp + 8] ; start parameter
        mov [ebx + CLUSTER_START_ADDR_INDEX], eax ; cl.start = eax

        mov eax, [ebp + 12] ; end parameter
        mov [ebx + CLUSTER_END_ADDR_INDEX], eax ; cl.end = eax

        mov [ebx + CLUSTER_IS_RESERVED_INDEX], byte FALSE ; cl.reserved = false

    return

_reserveCluster:
    fun ; void _reserveCluster(Cluster* cl, int size)
    ; Set cluster as reserved
    ; If cl.size != size -> cl.end = cl.start + size and then create a new empty cluster from cl.start + size to cl.end

    ; Initialize the parameters
    mov ebx, [ebp + 8] ; Cluster* cl -> the cluster pointer

    ; Reserve the cluster
    mov [ebx + CLUSTER_IS_RESERVED_INDEX], byte TRUE

    ; Compute the cluster size
    mov eax, [ebx + CLUSTER_END_ADDR_INDEX]
    sub eax, [ebx + CLUSTER_START_ADDR_INDEX] ; eax = cluster.end - cluster.start

    ; Compare the cluster size with the specified size
    cmp eax, [ebp + 12] ; [ebp + 12] = param size
    je .rcReturn ; if cl.size == size return

    ; Compute the new cluster end and set it (cl.start + size)
    mov eax, [ebx + CLUSTER_START_ADDR_INDEX] ; eax = cl.start
    add eax, [ebp + 12] ; eax += size param
    mov [ebx + CLUSTER_END_ADDR_INDEX], eax ; cl.end = eax

    ; Add a new cluster using _addNewCluster(eax (cl.start + size) + 4; cl.end)
    push dword [ebx + CLUSTER_END_ADDR_INDEX] ; param end
    add eax, 4 ; start must be an address one above the end
    push eax ; param start
    call _addNewCluster ; _addNewCluster(eax, cl.end)
    add esp, 8 ; clear the stack

    .rcReturn:
        return

_emptyClusterWithSize:
    fun ; Cluster* _emptyClusterWithSize(int size) - returns a free cluster with a specified size and the lowest size difference
    ; for every cluster
    ;   - check if free
    ;   - check if size >= size
    ;   - if the size difference < minSizeDiff save as minSizeDiff
    ; return cluster with minSizeDiff or NULL

    ; [esp] = minimum size difference; [esp + 4] = selected address
    sub esp, 8
    mov dword [esp], INTEGER_MAX
    mov dword [esp + 4], NULL_PTR

    ; ecx - counter
    mov ecx, [clusterCount]
    .ecwsLoop1: ; the main loop
        dec ecx ; decrease when starting - index based

        ; Get the cluster at index ecx (Cluster*) - [clusters] + ecx * CLUSTER_STRUCT_SIZE
        mov eax, CLUSTER_STRUCT_SIZE
        mul ecx ; eax = ecx * CLUSTER_STRUCT_SIZE
        mov ebx, [clusters]
        lea ebx, [ebx + eax] ; ebx = [clusters] + eax

        ; Check if the cluster is free
        cmp [ebx + CLUSTER_IS_RESERVED_INDEX], byte FALSE
        jne .ecwsContinue ; continue the loop if cluster.reserved != false

        ; Compute the cluster size
        mov edx, [ebx + CLUSTER_END_ADDR_INDEX]
        sub edx, [ebx + CLUSTER_START_ADDR_INDEX] ; edx = cluster.end - cluster.start
        ; Check if cluster.size >= size parameter
        mov eax, [ebp + 8] ; the size parameter
        cmp eax, edx
        ja .ecwsContinue ; if eax (size param) > edx (cluster size) continue

        ; Compute the size difference
        sub edx, eax ; edx = edx - eax = size difference

        ; Compare the size difference with the minimum one
        cmp edx, [esp] ; if edx (current size difference) < [esp] (saved lowest size difference)
        jb .ecwsSetMin

        jmp .ecwsContinue

        ; Set the minimum cluster
        .ecwsSetMin:
            mov [esp], edx ; save the min. difference
            mov [esp + 4], ebx ; save the cluster pointer

        .ecwsContinue:
            cmp ecx, 0 ; if ecx != 0 continue
            jne .ecwsLoop1

    mov eax, [esp + 4] ; save the right cluster into the return register
    return

_reserveBytes:
    fun ; void* _reserveBytes(int num) = reserves 'num' bytes, returns the start address

    ; Call sys_brk to return the current position of the program break
    mov ebx, 0 ; append 0 bytes => current position returned in eax
    mov eax, SYS_BRK
    int 0x80

    push eax ; save the beggining address of the cluster into [esp]
    add eax, [ebp + 8] ; add the number of bytes to be reserved to eax (the highest address)

    ; Move the program break to eax
    mov ebx, eax
    mov eax, SYS_BRK
    int 0x80

    pop eax ; return the beginning of the newly allocated cluster

    return