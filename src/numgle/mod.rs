#![feature(global_asm)]
use std::arch::global_asm;
use std::ffi::CStr;
use std::os::raw::c_char;

global_asm!(include_str!("numgle.s"));
extern "C" {
    pub fn _numgle(s: *const c_char) -> u32;
    pub fn _decode_codepoint(s: *const c_char) -> u32;
}

mod tests {
    use std::ffi::CString;

    use super::*;

    #[test]
    fn test_utf8_decoder() {
        let data = [
            ("ㅇ", 0x3147), ("가", 0xAC00), 
            ("산", 0xC0B0), ("G", 0x0047), ("!", 0x0021), ("加카", 0x52A0), 
            ("藤토", 0x85E4), ("恵메구미",0x6075), ("か카", 0x304B), ("と토", 0x3068),
            ("う우", 0x3046), ("め메", 0x3081), ("ぐ구", 0x3050), ("み미", 0x307F)
        ];
        for (s, expected) in data.iter() {
            let cs = CString::new(*s).unwrap();
            unsafe { assert_eq!(_decode_codepoint(cs.as_ptr()), *expected as u32); }
        }
    }

}