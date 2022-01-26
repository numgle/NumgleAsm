use numgle::NStr;

mod numgle;

use actix_web::{get, web, App, HttpServer, Responder};

#[get("/{name}")]
async fn index(web::Path(name): web::Path<String>) -> impl Responder {
    let mut input: NStr = NStr::from(&name);
    let MAX_SIZE_PER_CHAR = 3 * 32; // (cho + jung + jong) * max_char_size * 2 
    let mut str = NStr::new(name.len() * MAX_SIZE_PER_CHAR);
    unsafe {
        while input.len() > 0 {
            numgle::numgle_char(input.get_ffi(), str.get_ffi());
        }
    }
    let length = str.len();
    str.buffer[length] = 0;
    str.to_str()
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    HttpServer::new(|| App::new().service(index))
        .bind("127.0.0.1:8080")?
        .run()
        .await
}
