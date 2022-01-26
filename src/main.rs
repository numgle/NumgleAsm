use std::ffi::{CString, CStr};

use numgle::RustStr;

mod numgle;


fn main() {
    let mut str = RustStr::new(100);
    let mut ffi = str.to_ffi();
    unsafe {
        numgle::_numgle_codepoint(&mut ffi, 0x3149);
        str.len = ffi.len;
    }
    println!("{}", str.to_str());
    println!("Hello, world!");
}
