.global numgle_char
.global _numgle_codepoint
.global _decode_codepoint
.global _get_letter_type
.global _str_append
.code64

# linux calling convention
# args : rdi, rsi, rdx, rcx, r8, r9, r10, r11, r12, r13, r14, r15
# caller save regs : rdi, rsi, rdx, rcx, r8, r9
# callee save regs : rbx, rbp, r12, r13, r14, r15
# scratch regs : rax

.set cho_table_stride, 8
.set jung_table_stride, 4
.set jong_table_stride, 8
.set han_table_stride, 8
.set english_upper_table_stride, 8
.set english_lower_table_stride, 8
.set number_table_stride, 8
.set cj_table_stride, 304
.set cj_table_element_size, 16
.set newline, 10

# uses rax and rdx
.macro table_ptr dest, table, stride, index
        mov eax, \index
        mov edx, \stride
        mul edx
        lea \dest, [rip + \table]
        lea \dest, [\dest + rax]
.endm

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

# rdi: input str
# rsi: output str
numgle_char:
        save_regs
        .set input_str, 0
        .set output_str, 8
        .set codepoint, 16
        sub rsp, 32

        mov [rsp+input_str], rdi # input str
        mov [rsp+output_str], rsi # output str
        xor rax, rax
        mov [rsp+codepoint], eax # codepoint

        # Decode utf8 data
        mov rdi, [rdi] # input str data
        mov al, [rdi]
        cmp al, 0
        je numgle_char_end
        call decode_utf8
        mov [rsp+codepoint], eax

        # Pop letters
        mov rdi, [rsp+input_str]
        mov rsi, rdx
        call str_pop_front

        # Numgle
        mov rdi, [rsp+output_str]
        mov esi, [rsp+codepoint]
        call numgle
        jmp numgle_char_end

 numgle_char_end:
        add rsp, 32
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

# rdi: Str instance
# rsi: number of bytes to pop
str_pop_front:
        mov rcx, [rdi] # data pointer
        add rcx, rsi
        mov [rdi], rcx
        mov ecx, [rdi+8] # len
        sub ecx, esi
        mov [rdi+8], ecx
        ret

###############################################################################
# Separate hangul routine
###############################################################################
# rdi: code point
# rsi: result pointer
separate_hangul:
        mov ebx, edi
        sub ebx, 44032
        mov eax, ebx
        mov ecx, 28
        xor edx, edx
        div ecx
        mov [rsi+8], edx
        xor edx, edx
        mov ecx, 21
        div ecx
        mov [rsi+4], edx
        mov [rsi], eax
        ret

###############################################################################
# Numgle routine
###############################################################################
_numgle_codepoint:
        save_regs
        call numgle
        load_regs
        ret

# rdi: output str instance
# rsi: codepoint
numgle:
        .set codepoint, 0
        .set output_str, 4
        .set letter_type, 12
        .set newline_str, 16
        .set separated, 20
        sub rsp, 64
        mov [rsp+output_str], rdi 
        mov [rsp+codepoint], esi
        # Get letter type
        mov edi, esi
        call get_letter_type
        mov [rsp+letter_type], eax # letter type

        # Switch
        cmp eax, 0
        je numgle_empty
        cmp eax, 1
        je numgle_complete_hangul
        cmp eax, 2
        je numgle_not_complete_hangul
        cmp eax, 3
        je numgle_english_upper
        cmp eax, 4
        je numgle_english_lower
        cmp eax, 5
        je numgle_number
        jmp numgle_cleanup
        
numgle_empty:
        jmp numgle_append_newline

numgle_complete_hangul:
        mov edi, [rsp+codepoint]
        lea rsi, [rsp+separated]
        call separate_hangul
        mov r12d, [rsp+separated] # cho
        mov r13d, [rsp+separated+4] # jung
        mov r14d, [rsp+separated+8] # jong
        cmp r13d, 8
        jl numgle_complete_hangul_cj_case
        cmp r13d, 20
        je numgle_complete_hangul_cj_case_20
        jmp numgle_complete_hangul_non_cj_case

numgle_complete_hangul_non_cj_case:
        sub r13d, 8
        table_ptr rsi, jong_table, jong_table_stride, r14d
        mov rdi, [rsp+output_str]
        call str_append
        table_ptr rsi, jung_table, jung_table_stride, r13d
        call str_append
        table_ptr rsi, cho_table, cho_table_stride, r12d
        call str_append
        jmp numgle_append_newline

numgle_complete_hangul_cj_case_20:
        mov r13d, 8
        table_ptr rsi, jong_table, jong_table_stride, r14d
        mov rdi, [rsp+output_str]
        call str_append
        table_ptr rsi, cj_table, cj_table_stride, r13d
        mov eax, r12d
        mov ebx, cj_table_element_size
        mul ebx
        lea rsi, [rsi+rax]
        call str_append
        jmp numgle_append_newline

numgle_complete_hangul_cj_case:
        table_ptr rsi, jong_table, jong_table_stride, r14d
        mov rdi, [rsp+output_str]
        call str_append
        table_ptr rsi, cj_table, cj_table_stride, r13d
        mov eax, r12d
        mov ebx, cj_table_element_size
        mul ebx
        lea rsi, [rsi+rax]
        call str_append
        jmp numgle_append_newline

numgle_not_complete_hangul:
        mov esi, [rsp+codepoint]
        mov edi, [rip+ranges_data + 8]
        sub esi, edi
        table_ptr rbx, han_table, han_table_stride, esi
        mov rdi, [rsp+output_str]
        mov rsi, rbx
        call str_append
        jmp numgle_append_newline

numgle_english_upper:
        mov esi, [rsp+codepoint]
        mov edi, [rip+ranges_data + 2*8] # 2 * 8 = 16
        sub esi, edi
        table_ptr rbx, english_upper_table, english_upper_table_stride, esi
        mov rdi, [rsp+output_str]
        mov rsi, rbx
        call str_append
        jmp numgle_append_newline

numgle_english_lower:
        mov esi, [rsp+codepoint]
        mov edi, [rip+ranges_data + 3*8]
        sub esi, edi
        table_ptr rbx, english_lower_table, english_lower_table_stride, esi
        mov rdi, [rsp+output_str]
        mov rsi, rbx
        call str_append
        jmp numgle_append_newline

numgle_number:
        mov esi, [rsp+codepoint]
        mov edi, [rip+ranges_data + 4*8]
        sub esi, edi
        table_ptr rbx, number_table, number_table_stride, esi
        mov rdi, [rsp+output_str]
        mov rsi, rbx
        call str_append
        jmp numgle_append_newline

numgle_append_newline:
        mov ax, newline
        mov [rsp+newline_str], ax
        xor ax, ax
        lea rbx, [rsp+newline_str]
        mov [rbx+1], ax
        mov rdi, [rsp+output_str]
        lea rsi, [rsp+newline_str]
        call str_append
        jmp numgle_cleanup

numgle_cleanup:
        add rsp, 64
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
cho_table: .byte 0x4a,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1,0x96,0xb5,0x00,0x00,0x00,0x00,0x00,0x72
        .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x6e,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xd0
        .byte 0x94,0x00,0x00,0x00,0x00,0x00,0x00,0x72,0x75,0x00,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x85,0x81,0x00,0x00,0x00,0x00,0x00,0xe3,0x84,0xb8,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0x9a,0xa0,0x00,0x00,0x00,0x00,0x00,0x3e,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x95,0x92,0x00,0x00,0x00,0x00,0x00,0xe3,0x85,0x87,0x00,0x00,0x00,0x00,0x00,0xea
        .byte 0x9e,0xb0,0x00,0x00,0x00,0x00,0x00,0xe1,0x95,0x92,0x7c,0x00,0x00,0x00,0x00,0xea
        .byte 0x9e,0xb0,0x2d,0x00,0x00,0x00,0x00,0xe3,0x85,0x9a,0x00,0x00,0x00,0x00,0x00,0x6d
        .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe3,0x85,0x92,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x95,0x84,0x00,0x00,0x00,0x00,0x00
jung_table: .byte 0xe3,0x85,0x8f,0x00,0xe1,0x85,0xb7,0x00,0xe5,0xb7,0xa6,0x00,0xe4,0xb8,0x8a,0x00,0xe3
        .byte 0x85,0x91,0x00,0xe3,0x85,0x93,0x00,0xe1,0x85,0xba,0x00,0xea,0xb3,0xa4,0x00,0xe1
        .byte 0x85,0xbc,0x00,0xe3,0x85,0x95,0x00,0x6c,0x00,0x00,0x00,0xe2,0x8a,0xa5,0x00
jong_table: .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x4a,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x96,0xb5,0x00,0x00,0x00,0x00,0x00,0xe2,0x8b,0x9d,0x27,0x00,0x00,0x00,0x00,0x72
        .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x35,0xc4,0xb1,0x00,0x00,0x00,0x00,0x00,0xce
        .byte 0xb4,0xcb,0xab,0x00,0x00,0x00,0x00,0x6e,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x72
        .byte 0x75,0x00,0x00,0x00,0x00,0x00,0x00,0xe3,0x80,0x8c,0xeb,0x8a,0xac,0x00,0x00,0xe3
        .byte 0x80,0x8c,0xeb,0x8b,0x98,0x00,0x00,0xea,0x88,0x89,0x27,0x00,0x00,0x00,0x00,0xe2
        .byte 0xaa,0x9e,0x00,0x00,0x00,0x00,0x00,0xea,0x89,0xb1,0x00,0x00,0x00,0x00,0x00,0x00
        .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xea,0x82,0x9a,0xcb,0xab,0x00,0x00,0x00,0xe3
        .byte 0x85,0x81,0x00,0x00,0x00,0x00,0x00,0xe3,0x84,0xb8,0x00,0x00,0x00,0x00,0x00,0xe2
        .byte 0xaa,0x9a,0x00,0x00,0x00,0x00,0x00,0x3e,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x95,0x92,0x00,0x00,0x00,0x00,0x00,0xe3,0x85,0x87,0x00,0x00,0x00,0x00,0x00,0xea
        .byte 0x9e,0xb0,0x00,0x00,0x00,0x00,0x00,0xea,0x9e,0xb0,0x2d,0x00,0x00,0x00,0x00,0xe3
        .byte 0x85,0x9a,0x00,0x00,0x00,0x00,0x00,0x6d,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x85,0x92,0x00,0x00,0x00,0x00,0x00,0xec,0x95,0x84,0x00,0x00,0x00,0x00,0x00
han_table: .byte 0x4a,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1,0x96,0xb5,0x00,0x00,0x00,0x00,0x00,0xe2
        .byte 0x8b,0x9d,0x27,0x00,0x00,0x00,0x00,0x72,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x35
        .byte 0xc4,0xb1,0x00,0x00,0x00,0x00,0x00,0xce,0xb4,0xcb,0xab,0x00,0x00,0x00,0x00,0x6e
        .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xd0,0x94,0x00,0x00,0x00,0x00,0x00,0x00,0x72
        .byte 0x75,0x00,0x00,0x00,0x00,0x00,0x00,0xe3,0x80,0x8c,0xeb,0x8a,0xac,0x00,0x00,0xe3
        .byte 0x80,0x8c,0xeb,0x8b,0x98,0x00,0x00,0xea,0x88,0x89,0x27,0x00,0x00,0x00,0x00,0xe2
        .byte 0xaa,0x9e,0x00,0x00,0x00,0x00,0x00,0xea,0x89,0xb1,0x00,0x00,0x00,0x00,0x00,0x00
        .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xea,0x82,0x9a,0xcb,0xab,0x00,0x00,0x00,0xe3
        .byte 0x85,0x81,0x00,0x00,0x00,0x00,0x00,0xe3,0x84,0xb8,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0x9a,0xa0,0x00,0x00,0x00,0x00,0x00,0xe2,0xaa,0x9a,0x00,0x00,0x00,0x00,0x00,0x3e
        .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1,0x95,0x92,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x85,0x87,0x00,0x00,0x00,0x00,0x00,0xea,0x93,0x98,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x95,0x92,0x7c,0x00,0x00,0x00,0x00,0xea,0x93,0x98,0x2d,0x00,0x00,0x00,0x00,0xe3
        .byte 0x85,0x9a,0x00,0x00,0x00,0x00,0x00,0x6d,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x85,0x92,0x00,0x00,0x00,0x00,0x00,0xec,0x95,0x84,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x85,0x9c,0x00,0x00,0x00,0x00,0x00,0xe5,0xb7,0xa5,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x85,0xa0,0x00,0x00,0x00,0x00,0x00,0xe3,0x85,0x8d,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x85,0x97,0x00,0x00,0x00,0x00,0x00,0xe3,0x80,0xa7,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x85,0x9b,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x85,0x8f,0x00,0x00,0x00,0x00,0x00,0xe1,0x85,0xb7,0x00,0x00,0x00,0x00,0x00,0xe5
        .byte 0xb7,0xa6,0x00,0x00,0x00,0x00,0x00,0xe4,0xb8,0x8a,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x85,0x91,0x00,0x00,0x00,0x00,0x00,0xe3,0x85,0x93,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x85,0xba,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x85,0xbc,0x00,0x00,0x00,0x00,0x00,0xe3,0x85,0x95,0x00,0x00,0x00,0x00,0x00,0x6c
        .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe2,0x8a,0xa5,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x85,0xa1,0x00,0x00,0x00,0x00,0x00
english_upper_table: .byte 0xe1,0x97,0x86,0x00,0x00,0x00,0x00,0x00,0xcf,0x96,0x00,0x00,0x00,0x00,0x00,0x00,0xe2
        .byte 0x88,0xa9,0x00,0x00,0x00,0x00,0x00,0xe1,0x97,0x9c,0x00,0x00,0x00,0x00,0x00,0x6d
        .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe3,0x84,0xb2,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x98,0x8f,0x00,0x00,0x00,0x00,0x00,0xe5,0xb7,0xa5,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x85,0xa1,0x00,0x00,0x00,0x00,0x00,0x28,0x5f,0x5f,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x85,0x88,0x00,0x00,0x00,0x00,0x00,0xe2,0x94,0x8c,0x2d,0x00,0x00,0x00,0x00,0xe1
        .byte 0x95,0x92,0x00,0x00,0x00,0x00,0x00,0x5a,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x4f
        .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe2,0x80,0xbe,0xe1,0x97,0x9c,0x00,0x00,0x2c
        .byte 0x4f,0x00,0x00,0x00,0x00,0x00,0x00,0x37,0xe1,0x97,0x9c,0x00,0x00,0x00,0x00,0xe2
        .byte 0x88,0xbd,0x00,0x00,0x00,0x00,0x00,0x2d,0xe3,0x85,0x93,0x00,0x00,0x00,0x00,0xe2
        .byte 0x8a,0x82,0x00,0x00,0x00,0x00,0x00,0x3c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xce
        .byte 0xb5,0x00,0x00,0x00,0x00,0x00,0x00,0x58,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x2d
        .byte 0x3c,0x00,0x00,0x00,0x00,0x00,0x00,0x4e,0x00,0x00,0x00,0x00,0x00,0x00,0x00
english_lower_table: .byte 0xe1,0x83,0xb9,0x00,0x00,0x00,0x00,0x00,0xe1,0x93,0x82,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0xb4,0x92,0x00,0x00,0x00,0x00,0x00,0xe1,0x93,0x87,0x00,0x00,0x00,0x00,0x00,0xe0
        .byte 0xb4,0xb0,0x00,0x00,0x00,0x00,0x00,0xe1,0x82,0xb5,0x00,0x00,0x00,0x00,0x00,0xda
        .byte 0xa1,0x00,0x00,0x00,0x00,0x00,0x00,0xe1,0x8d,0x93,0x00,0x00,0x00,0x00,0x00,0x2d
        .byte 0xc2,0xb7,0x00,0x00,0x00,0x00,0x00,0xe3,0x84,0xb4,0x2e,0x00,0x00,0x00,0x00,0xe3
        .byte 0x85,0x88,0x00,0x00,0x00,0x00,0x00,0xe3,0x85,0xa1,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0xb4,0x9f,0x00,0x00,0x00,0x00,0x00,0xe1,0xb4,0x9d,0x00,0x00,0x00,0x00,0x00,0x6f
        .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1,0x93,0x80,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x93,0x84,0x00,0x00,0x00,0x00,0x00,0xe3,0x84,0xb1,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x94,0xa5,0x00,0x00,0x00,0x00,0x00,0x2d,0x2b,0x00,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x84,0xb7,0x00,0x00,0x00,0x00,0x00,0x3c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xea
        .byte 0x97,0xa8,0x00,0x00,0x00,0x00,0x00,0x78,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xef
        .byte 0xbb,0x8b,0x00,0x00,0x00,0x00,0x00,0xe1,0xb4,0xba,0x00,0x00,0x00,0x00,0x00
number_table: .byte 0x6f,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe3,0x85,0xa1,0x00,0x00,0x00,0x00,0x00,0x72
        .byte 0x75,0x00,0x00,0x00,0x00,0x00,0x00,0xcf,0x89,0x00,0x00,0x00,0x00,0x00,0x00,0x2d
        .byte 0x46,0x00,0x00,0x00,0x00,0x00,0x00,0x55,0x54,0x00,0x00,0x00,0x00,0x00,0x00,0x30
        .byte 0xe2,0x80,0xbe,0xe2,0x80,0xbe,0x00,0x5f,0x5f,0x7c,0x00,0x00,0x00,0x00,0x00,0xe2
        .byte 0x88,0x9e,0x00,0x00,0x00,0x00,0x00,0x5f,0x5f,0x30,0x00,0x00,0x00,0x00,0x00
cj_table: .byte 0xe1,0x86,0x97,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x85,0xbe,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x46
        .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe5
        .byte 0xae,0x81,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe6
        .byte 0x97,0xa9,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x80,0x8c,0xeb,0x89,0x98,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0xac,0xb4,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0x9a,0x9c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xea
        .byte 0xa5,0xb9,0xe1,0x85,0xae,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe2
        .byte 0xaa,0xb2,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe5
        .byte 0xaf,0xbb,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x9a,0xb0,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x89,0xac,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xed
        .byte 0x80,0xb4,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x84,0x89,0xe1,0x85,0xb7,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x85,0x9f,0xe1,0x85,0xac,0xe1,0x86,0xa8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x91,0xa4,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0xb6,0x80,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x84,0x8b,0xe1,0x85,0xb7,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe2
        .byte 0x89,0x9a,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x20
        .byte 0xcd,0x9f,0xe1,0x85,0xbe,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0x8f,0x84,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0xaa,0xa8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe5
        .byte 0x9c,0xbc,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xea
        .byte 0x84,0xb9,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x84,0x86,0xed,0x9e,0xbc,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x84,0x84,0xed,0x9e,0xbc,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xea
        .byte 0xa5,0xb9,0xed,0x9e,0xbc,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x92,0xb0,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0xbf,0xa4,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x84,0x8b,0xed,0x9e,0xbc,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x89,0xb0,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xed
        .byte 0x80,0xb8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x84,0x89,0xe1,0x85,0xb7,0xe1,0x86,0xab,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xea
        .byte 0x81,0x88,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x84,0x8a,0xed,0x9e,0xbc,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x84,0x87,0xed,0x9e,0xbc,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x84,0x8b,0xe1,0x85,0xb7,0xe1,0x86,0xab,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x85,0x9f,0xe1,0x86,0x9c,0xe1,0x86,0xa9,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x85,0x9f,0xe1,0x85,0xa7,0xe1,0x86,0xa9,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe6
        .byte 0x96,0xa4,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x80,0x8c,0xea,0xb7,0x9c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x6c
        .byte 0xed,0x81,0x90,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x80,0x8c,0xe1,0x84,0x82,0xe1,0x86,0x94,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0xae,0xa4,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0x9c,0x8c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xea
        .byte 0xa5,0xb9,0xe1,0x85,0xb2,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x8a,0x88,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xed
        .byte 0x81,0xae,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x9c,0xa0,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x84,0x89,0xe1,0x86,0x94,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xed
        .byte 0x81,0x90,0x7c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x84,0x89,0xe1,0x86,0x8e,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x85,0x9f,0xe1,0x85,0xac,0xe1,0x86,0xa9,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x93,0x94,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0xb7,0xb0,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x84,0x8b,0xe1,0x86,0x8e,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x85,0x9f,0xe1,0x85,0xb4,0xe1,0x87,0x81,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x85,0x9f,0xe1,0x85,0xa7,0xe1,0x87,0x81,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0x90,0xb4,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0xac,0x98,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe6
        .byte 0x98,0xb1,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x80,0x8c,0xeb,0x89,0xb8,0x6c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0xae,0xa8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0x9c,0x90,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xed
        .byte 0x8a,0xa0,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x8a,0x8c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xed
        .byte 0x82,0x86,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x9c,0xa4,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x8a,0x8c,0x7c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xed
        .byte 0x81,0x94,0x7c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x8a,0x8c,0x7c,0x2d,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x3d
        .byte 0xeb,0x89,0xb8,0x6c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x93,0x98,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0xb7,0xb4,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x9c,0xa4,0x7c,0x2d,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x96,0xb5,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x85,0xbd,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x80,0x8c,0xe5,0xb7,0xa5,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x80,0x8c,0xea,0xb3,0xa0,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x6c
        .byte 0xec,0xbd,0x94,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xea
        .byte 0x8c,0xb0,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0xaa,0xa8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0x98,0x90,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xea
        .byte 0xa5,0xb9,0xe1,0x85,0xa9,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x86,0x8c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x98,0xa4,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x87,0xa0,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0xbe,0xa8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x86,0xa8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x3d
        .byte 0xeb,0x87,0x8c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x8f,0x98,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0xb3,0xb4,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x99,0x80,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe2
        .byte 0x89,0x9a,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0x9c,0xa8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x80,0x8c,0xea,0xb3,0xa4,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x6c
        .byte 0xec,0xbd,0x98,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xea
        .byte 0x84,0xb9,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0xaa,0xac,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0x98,0x94,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xea
        .byte 0xa5,0xb9,0xe1,0x85,0xa9,0xe1,0x86,0xab,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x86,0x90,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x98,0xa8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x87,0xa4,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0xbe,0xac,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x86,0xac,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xea
        .byte 0x81,0x88,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x8f,0x9c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0xb3,0xb8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x99,0x84,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x85,0x9f,0xe1,0x85,0xb5,0xe1,0x87,0x81,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x85,0x9f,0xe1,0x85,0xa7,0xe1,0x87,0xbf,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x80,0x8c,0xe7,0xab,0x8b,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x80,0x8c,0xea,0xb5,0x90,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x6c
        .byte 0xec,0xbf,0x84,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x80,0x8c,0xe1,0x84,0x82,0xe1,0x86,0x88,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0xac,0x98,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0x9a,0x80,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xea
        .byte 0xa5,0xb9,0xe1,0x85,0xad,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x87,0xbc,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x84,0x8f,0xe1,0x85,0xb3,0xe1,0x87,0xbf,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x9a,0x94,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x84,0x89,0xe1,0x86,0x88,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0xbf,0x84,0x7c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x84,0x89,0xed,0x9e,0xb2,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x3d
        .byte 0xeb,0x87,0xa8,0x6c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x91,0x88,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0xb5,0xa4,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x84,0x8b,0xed,0x9e,0xb2,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x85,0x9f,0xed,0x9f,0x83,0xe1,0x86,0xae,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
        .byte 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x80,0x8c,0xed,0x94,0x84,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x80,0x8c,0xea,0xb5,0x94,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x6c
        .byte 0xec,0xbf,0x88,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x80,0x8c,0xe1,0x84,0x82,0xe1,0x86,0x88,0xe1,0x86,0xab,0x00,0x00,0x00,0x00,0xeb
        .byte 0xac,0x9c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0x9a,0x84,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xea
        .byte 0xa5,0xb9,0xe1,0x85,0xad,0xe1,0x86,0xab,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x88,0x80,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xed
        .byte 0x81,0x97,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x9a,0x98,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x88,0x80,0x7c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0xbf,0x88,0x7c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x84,0x89,0xed,0x9e,0xb2,0xe1,0x86,0xab,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x3d
        .byte 0xeb,0x87,0xac,0x6c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x91,0x8c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0xb5,0xa8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x84,0x8b,0xed,0x9e,0xb2,0xe1,0x86,0xab,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe2
        .byte 0x87,0xb2,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x20
        .byte 0xcd,0x9f,0xe1,0x96,0xb5,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x84,0xb7,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe3
        .byte 0x80,0x8c,0xea,0xb7,0xb8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe6
        .byte 0x97,0xa5,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0xb9,0x88,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0xaf,0x80,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0x9c,0xa8,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xea
        .byte 0xa5,0xb9,0xe1,0x85,0xb3,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe2
        .byte 0x89,0xa5,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe2
        .byte 0xaa,0xad,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x9c,0xbc,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x8b,0x80,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xed
        .byte 0x82,0x88,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x84,0x89,0xed,0x9e,0xb9,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x3d
        .byte 0xeb,0x8a,0xac,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xec
        .byte 0x93,0xb0,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xeb
        .byte 0xb8,0x8c,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xe1
        .byte 0x84,0x8b,0xed,0x9e,0xb9,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
ranges_data: .byte 0x00,0xac,0x00,0x00,0xa3,0xd7,0x00,0x00,0x31,0x31,0x00,0x00,0x63,0x31,0x00,0x00,0x41,0x00,0x00,0x00,0x5a,0x00,0x00,0x00,0x61,0x00,0x00,0x00,0x7a,0x00,0x00,0x00,0x30,0x00,0x00,0x00,0x39,0x00,0x00,0x00,0x0,0x0,0x0,0x0