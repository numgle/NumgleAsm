use std::ffi::{CString, CStr};

mod numgle;


fn main() {
    let a = CString::new("ㅇ").unwrap();
    unsafe {
        println!("{}", numgle::_get_letter_type(0x3147));
    }
    println!("Hello, world!");
}
