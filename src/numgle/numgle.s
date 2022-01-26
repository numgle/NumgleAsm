.global _numgle   
.global _decode_codepoint
.global _get_letter_type
.global _str_append
.code64

# linux calling convention
# args : rdi, rsi, rdx, rcx, r8, r9, r10, r11, r12, r13, r14, r15
# caller save regs : rdi, rsi, rdx, rcx, r8, r9
# callee save regs : rbx, rbp, r12, r13, r14, r15
# scratch regs : rax

# caller doesnt know the stack layout, so we need to save all the regs
# when it's supposed to be called by rust
.macro save_regs
        push rsi
        push rdx
        push rcx
        push r8
        push r9
        push rbx
        push rbp
        push r12
        push r13
        push r14
        push r15
.endm

.macro load_regs
        pop r15
        pop r14
        pop r13
        pop r12
        pop rbp
        pop rbx
        pop r9
        pop r8
        pop rcx
        pop rdx
        pop rsi
.endm

_numgle:
        save_regs
        load_regs
        ret

###############################################################################
# String interface
###############################################################################
// struct Str 
//    uint8_t data 0
//    uint32_t len 8
//    uint32_t capacity 12
// 
#
_str_append:
        save_regs
        call str_append
        load_regs
        ret

# rdi: Str instance
# rsi: string pointer
str_append:
        mov rbx, rsi # string pointer
        xor rsi, rsi # i
        mov rcx, [rdi] # data pointer
        mov edx, [rdi+8] # cursor
        jmp str_append_loop
        
str_append_loop:
        mov al, [rbx+rsi]
        cmp al, 0
        je str_append_done
        mov [rcx+rdx], al
        inc rsi
        inc rdx
        jmp str_append_loop

str_append_done:
        mov [rdi+8], edx
        ret

###############################################################################
# Numgle routine
###############################################################################
# rdi: string
numgle:
        add rsp, -16
        call decode_utf8
        mov rdi, rax
        call get_letter_type
        mov rbx, rax # letter type

        ret


###############################################################################
# Letter type detection routine
###############################################################################
# Empty = 0
# CompleteHangul = 1
# NotCompleteHangul = 2
# EnglishUpper = 3
# EnglishLower = 4
# Number = 5
# SpecialLetter = 6
# Unknown = 7

_get_letter_type:
        save_regs
        call get_letter_type
        load_regs
        ret

# rdi: codepoint
# rax: letter type
# scratch regs: rsi, rdx
get_letter_type:
        push rbx
        push rcx
        # Detect empty
        cmp edi, 32 # blank
        je get_ltter_type_return_empty
        cmp edi, 10 # newline
        je get_ltter_type_return_empty
        cmp edi, 13 # carriage return
        je get_ltter_type_return_empty
        xor rsi, rsi # i
        jmp get_letter_type_range_loop

get_letter_type_range_loop:
        lea rbx, [rip + ranges_data]
        mov ecx, [rbx + rsi * 8] # start
        cmp ecx, 0
        je get_letter_type_speical_chars
        mov edx, [rbx + rsi * 8 + 4] # end
        cmp edi, ecx
        jl get_letter_type_range_loop_next
        cmp edi, edx
        jge get_letter_type_range_loop_next
        mov rax, rsi
        add rax, 1
        jmp get_letter_type_cleanup

get_letter_type_range_loop_next:
        add rsi, 1
        jmp get_letter_type_range_loop

get_letter_type_speical_chars:
        jmp get_ltter_type_return_empty

get_ltter_type_return_empty:
        xor rax, rax
        jmp get_letter_type_cleanup

get_letter_type_cleanup:
        pop rcx
        pop rbx
        ret

###############################################################################
# UTF8 Decode routine
###############################################################################
_decode_codepoint:
        save_regs
        call decode_utf8
        load_regs
        ret

decode_utf8: 
# rdi: pointer to the string  
# rax: return codepoint   
# rdx: read length of string   
# scratch regs: rsi, rdx
        push rbx
        push rcx
        push r12
        push r13
        xor esi, esi # esi: current position in the string
        xor eax, eax # eax: state
        # edx: codep
        jmp decode_utf8_loop

decode_utf8_loop:
        mov bl, [rdi + rsi] # bl: next byte
        movzx ebx, bl # ebx: zext bl
        lea r12, [rip + utf8_table]
        mov cl, [r12 + rbx] # cl: type
        movzx ecx, cl
        # exit if end of string
        cmp bl, 0 
        je decode_utf8_cleanup
        # exit if done consuming
        xor r13d, r13d
        cmp esi, 0
        sete r13b
        or r13d, eax
        cmp r13d, 0
        je decode_utf8_cleanup
        # init codep
        cmp eax, 0 
        je decode_utf8_initcodep
        # parse codep
        and bl, 0x3f
        movzx ebx, bl 
        mov r13d, edx # r13: new codep
        shl r13d, 6
        or r13d, ebx
        mov edx, r13d
        # r13 free
        jmp decode_utf8_change

decode_utf8_initcodep:
        mov edx, 0xff
        shr edx, cl
        and edx, ebx
        jmp decode_utf8_change

decode_utf8_change:
        # change state
        lea r12, [rip + utf8_table]
        lea r12, [r12 + rcx]
        # ecx free
        mov ecx, eax
        shl ecx, 1
        lea r12, [r12 + rcx * 8]
        mov al, [r12 + 256]
        add rsi, 1
        jmp decode_utf8_loop

decode_utf8_cleanup:
        mov rax, rdx
        mov rdx, rsi
        pop r13
        pop r12
        pop rcx
        pop rbx
        ret

utf8_table: 
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
        .byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9
        .byte 7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7
        .byte 8,8,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2
        .byte 0xa,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x3,0x4,0x3,0x3
        .byte 0xb,0x6,0x6,0x6,0x5,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8,0x8
        .byte 0x0,0x1,0x2,0x3,0x5,0x8,0x7,0x1,0x1,0x1,0x4,0x6,0x1,0x1,0x1,0x1
        .byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,1,1,1,1,1,0,1,0,1,1,1,1,1,1
        .byte 1,2,1,1,1,1,1,2,1,2,1,1,1,1,1,1,1,1,1,1,1,1,1,2,1,1,1,1,1,1,1,1
        .byte 1,2,1,1,1,1,1,1,1,2,1,1,1,1,1,1,1,1,1,1,1,1,1,3,1,3,1,1,1,1,1,1
        .byte 1,3,1,1,1,1,1,3,1,3,1,1,1,1,1,1,1,3,1,1,1,1,1,1,1,1,1,1,1,1,1,1

cho_table: .byte 0x4a,0x00,0x00,0x00,0x00,0xe1,0x96,0xb5,0x00,0x00,0x72,0x00,0x00,0x00,0x00,0x6e,0x00,0x00,0x00,0x00,0xd0,0x94,0x00,0x00,0x00,0x72,0x75,0x00,0x00,0x00,0xe3,0x85,0x81,0x00,0x00,0xe3,0x84,0xb8,0x00,0x00,0xeb,0x9a,0xa0,0x00,0x00,0x3e,0x00,0x00,0x00,0x00,0xe1,0x95,0x92,0x00,0x00,0xe3,0x85,0x87,0x00,0x00,0xea,0x9e,0xb0,0x00,0x00,0xe1,0x95,0x92,0x7c,0x00,0xea,0x9e,0xb0,0x2d,0x00,0xe3,0x85,0x9a,0x00,0x00,0x6d,0x00,0x00,0x00,0x00,0xe3,0x85,0x92,0x00,0x00,0xec,0x95,0x84,0x00,0x00
jung_table: .byte 0xe3,0x85,0x8f,0x00,0xe1,0x85,0xb7,0x00,0xe5,0xb7,0xa6,0x00,0xe4,0xb8,0x8a,0x00,0xe3,0x85,0x91,0x00,0xe3,0x85,0x93,0x00,0xe1,0x85,0xba,0x00,0xea,0xb3,0xa4,0x00,0xe1,0x85,0xbc,0x00,0xe3,0x85,0x95,0x00,0x6c,0x00,0x00,0x00,0xe2,0x8a,0xa5,0x00
han_table: .byte 0x4a,0x00,0x00,0x00,0x00,0x00,0x00,0xe1,0x96,0xb5,0x00,0x00,0x00,0x00,0xe2,0x8b,0x9d,0x27,0x00,0x00,0x00,0x72,0x00,0x00,0x00,0x00,0x00,0x00,0x35,0xc4,0xb1,0x00,0x00,0x00,0x00,0xce,0xb4,0xcb,0xab,0x00,0x00,0x00,0x6e,0x00,0x00,0x00,0x00,0x00,0x00,0xd0,0x94,0x00,0x00,0x00,0x00,0x00,0x72,0x75,0x00,0x00,0x00,0x00,0x00,0xe3,0x80,0x8c,0xeb,0x8a,0xac,0x00,0xe3,0x80,0x8c,0xeb,0x8b,0x98,0x00,0xea,0x88,0x89,0x27,0x00,0x00,0x00,0xe2,0xaa,0x9e,0x00,0x00,0x00,0x00,0xea,0x89,0xb1,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xea,0x82,0x9a,0xcb,0xab,0x00,0x00,0xe3,0x85,0x81,0x00,0x00,0x00,0x00,0xe3,0x84,0xb8,0x00,0x00,0x00,0x00,0xeb,0x9a,0xa0,0x00,0x00,0x00,0x00,0xe2,0xaa,0x9a,0x00,0x00,0x00,0x00,0x3e,0x00,0x00,0x00,0x00,0x00,0x00,0xe1,0x95,0x92,0x00,0x00,0x00,0x00,0xe3,0x85,0x87,0x00,0x00,0x00,0x00,0xea,0x93,0x98,0x00,0x00,0x00,0x00,0xe1,0x95,0x92,0x7c,0x00,0x00,0x00,0xea,0x93,0x98,0x2d,0x00,0x00,0x00,0xe3,0x85,0x9a,0x00,0x00,0x00,0x00,0x6d,0x00,0x00,0x00,0x00,0x00,0x00,0xe3,0x85,0x92,0x00,0x00,0x00,0x00,0xec,0x95,0x84,0x00,0x00,0x00,0x00,0xe3,0x85,0x9c,0x00,0x00,0x00,0x00,0xe5,0xb7,0xa5,0x00,0x00,0x00,0x00,0xe3,0x85,0xa0,0x00,0x00,0x00,0x00,0xe3,0x85,0x8d,0x00,0x00,0x00,0x00,0xe3,0x85,0x97,0x00,0x00,0x00,0x00,0xe3,0x80,0xa7,0x00,0x00,0x00,0x00,0xe3,0x85,0x9b,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe3,0x85,0x8f,0x00,0x00,0x00,0x00,0xe1,0x85,0xb7,0x00,0x00,0x00,0x00,0xe5,0xb7,0xa6,0x00,0x00,0x00,0x00,0xe4,0xb8,0x8a,0x00,0x00,0x00,0x00,0xe3,0x85,0x91,0x00,0x00,0x00,0x00,0xe3,0x85,0x93,0x00,0x00,0x00,0x00,0xe1,0x85,0xba,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1,0x85,0xbc,0x00,0x00,0x00,0x00,0xe3,0x85,0x95,0x00,0x00,0x00,0x00,0x6c,0x00,0x00,0x00,0x00,0x00,0x00,0xe2,0x8a,0xa5,0x00,0x00,0x00,0x00,0xe3,0x85,0xa1,0x00,0x00,0x00,0x00
ranges_data: .byte 0x00,0xac,0x00,0x00,0xa3,0xd7,0x00,0x00,0x31,0x31,0x00,0x00,0x63,0x31,0x00,0x00,0x41,0x00,0x00,0x00,0x5a,0x00,0x00,0x00,0x61,0x00,0x00,0x00,0x7a,0x00,0x00,0x00,0x30,0x00,0x00,0x00,0x39,0x00,0x00,0x00,0x0,0x0,0x0,0x0