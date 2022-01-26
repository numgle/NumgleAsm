#![feature(global_asm)]
use std::arch::global_asm;
use std::os::raw::c_char;

#[repr(C)]
pub struct NStrFFI {
    data: *mut u8,
    len: u32,
    capacity: u32
}
pub struct NStr {
    pub buffer: Vec<u8>,
    ffi: NStrFFI
}

impl NStr {
    pub fn new(len: usize) -> Self {
        let mut buf = vec![0; len];
        let buf_ptr = buf.as_mut_ptr();
        Self {
            buffer: buf,
            ffi: NStrFFI {
                data: buf_ptr,
                len: 0,
                capacity: len as u32
            }
        }
    }

    pub fn from(str: &str) -> Self {
        let mut buf =  str.as_bytes().to_vec();
        buf.push(0);
        let buf_ptr = buf.as_mut_ptr();
        Self {
            buffer: buf,
            ffi: NStrFFI {
                data: buf_ptr,
                len: str.len() as u32,
                capacity: str.len() as u32
            }
        }
    }

    pub fn get_ffi(&mut self) -> *mut NStrFFI {
        &mut self.ffi
    }

    pub fn len(&self) -> usize {
        self.ffi.len as usize
    }
    
    pub fn to_str(&self) -> String {
        String::from_utf8(self.buffer[0..self.ffi.len as usize].to_vec()).unwrap()
    }
}

global_asm!(include_str!("numgle.s"));
extern "C" {
    pub fn numgle_char(input: *mut NStrFFI, output: *mut NStrFFI) -> u32;
    fn _decode_codepoint(s: *const c_char) -> u32;
    fn _get_letter_type(s: u32) -> u32;
    fn _numgle_codepoint(str: *mut NStrFFI, s: u32);
    fn _str_append(str: *mut NStrFFI, new: *const c_char);
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
        let mut str = NStr::new(100);
        let cs = CString::new("Hello").unwrap();
        unsafe {
            _str_append(str.get_ffi(), cs.as_ptr());
            assert_eq!(str.len(), 5);
            assert_eq!(str.buffer[0], 'H' as u8);
            assert_eq!(str.buffer[1], 'e' as u8);
            assert_eq!(str.buffer[2], 'l' as u8);
            assert_eq!(str.buffer[3], 'l' as u8);
            assert_eq!(str.buffer[4], 'o' as u8);
        }
    }

    #[test]
    fn test_numgle_codepoint() {
        let data = [
            (72, "工\n")
        ];
        for (s, expected) in data.iter() {
            let mut str = NStr::new(100);
            unsafe {
                _numgle_codepoint(str.get_ffi(), *s);
            }
            assert_eq!(str.to_str(), *expected);
        }
    }
}