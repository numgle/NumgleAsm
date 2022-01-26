use std::ffi::{CString, CStr};

mod numgle;


fn main() {
    let a = CString::new("ㅇ").unwrap();
    unsafe {
        println!("{}", numgle::_decode_codepoint(a.as_ptr()));
    }
    println!("Hello, world!");
}
