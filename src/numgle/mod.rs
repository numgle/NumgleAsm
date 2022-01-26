#![feature(global_asm)]
use std::arch::global_asm;
use std::ffi::CStr;
use std::os::raw::c_char;

struct RustStr {
    buffer: Vec<u8>,
    len: u32
}

#[repr(C)]
struct Str {
    data: *mut u8,
    len: u32,
    capacity: u32
}

impl RustStr {
    fn new(len: usize) -> Self {
        Self {
            buffer: vec![0; len],
            len: 0
        }
    }

    fn to_ffi(&mut self) -> Str {
        Str {
            data: self.buffer.as_mut_ptr(),
            len: self.len,
            capacity: self.buffer.len() as u32
        }
    }
}

global_asm!(include_str!("numgle.s"));
extern "C" {
    pub fn _numgle(s: *const c_char) -> u32;
    pub fn _decode_codepoint(s: *const c_char) -> u32;
    pub fn _get_letter_type(s: u32) -> u32;
    pub fn _str_append(str: *mut Str, new: *const c_char);
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

    #[test]
    fn test_get_letter_type() {
        let data = [(0x3147, 2), (0xAC00, 1), (0xC0B0, 1), (32, 0), (10, 0), (13, 0), (65, 3), (97, 4), (53, 5)];
        for (s, expected) in data.iter() {
            unsafe { assert_eq!(_get_letter_type(*s as u32), *expected as u32); }
        }
    }

    #[test]
    fn test_str_append() {
        let mut str = RustStr::new(100);
        let mut ffi = str.to_ffi();
        let cs = CString::new("Hello").unwrap();
        unsafe {
            _str_append(&mut ffi, cs.as_ptr());
            assert_eq!(ffi.len, 5);
            assert_eq!(str.buffer[0], 'H' as u8);
            assert_eq!(str.buffer[1], 'e' as u8);
            assert_eq!(str.buffer[2], 'l' as u8);
            assert_eq!(str.buffer[3], 'l' as u8);
            assert_eq!(str.buffer[4], 'o' as u8);
        }
    }
}