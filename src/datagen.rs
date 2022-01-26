use std::{path::Path, fs::File, io::Read};
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
pub struct Range{
    pub start:u32,
    pub end:u32,
}

impl Range{
    pub fn to_tuple(&self) -> (u32,u32){
        (self.start,self.end)
    }
}

#[derive(Deserialize)]
pub struct Ranges{
    pub completeHangul:Range,
    pub notCompleteHangul:Range,
    pub uppercase:Range,
    pub lowercase:Range,
    pub number:Range,
    pub special:Vec<u32>,
}

#[derive(Deserialize)]
pub struct DataSet{
    pub cho:Vec<String>,
    pub jong:Vec<String>,
    pub jung:Vec<String>,
    pub cj:Vec<Vec<String>>,
    pub han:Vec<String>,
    pub englishUpper:Vec<String>,
    pub englishLower:Vec<String>,
    pub number:Vec<String>,
    pub special:Vec<String>,
    pub range:Ranges,
}

fn align(size: usize, align: usize) -> usize {
    (size + align - 1) & !(align - 1)
}

fn hex_table(data: &[String]) -> (String, usize) {
    let max_size = align(data.iter().map(|item| {
        item.as_bytes().len()
    }).reduce(|accum, item| {
        std::cmp::max(accum, item)
    }).unwrap() + 1,4);
    let mut table: Vec<u8> = Vec::with_capacity(max_size * data.len());
    data.iter().for_each(|s| {
        for i in 0..s.len() {
            table.push(s.as_bytes()[i]);
        }
        for i in s.len()..max_size {
            table.push(0);
        }
    });
    let mut joined = String::from(".byte ");
    let MAX_LINE = 16;
    for i in 0..table.len() {
        joined += &format!("0x{:02x?}", table[i]);
        if i % MAX_LINE == 0 && i != 0 {
            joined += "\n";
            joined +=  "        .byte ";
        } else if i != table.len() - 1 {
            joined += ",";
        }
    }
    (joined, max_size)
}

fn hex_word(word: u32) -> String {
    format!("0x{:02x},0x{:02x},0x{:02x},0x{:02x}", word & 0xFF, (word >> 8) & 0xFF, (word >> 16) & 0xFF, word >> 24)
}


fn hex_ranges(range: &Ranges) -> String {
    let mut data: Vec<String> = Vec::new();
    data.push(hex_word(range.completeHangul.start));
    data.push(hex_word(range.completeHangul.end));
    data.push(hex_word(range.notCompleteHangul.start));
    data.push(hex_word(range.notCompleteHangul.end));
    data.push(hex_word(range.uppercase.start));
    data.push(hex_word(range.uppercase.end));
    data.push(hex_word(range.lowercase.start));
    data.push(hex_word(range.lowercase.end));
    data.push(hex_word(range.number.start));
    data.push(hex_word(range.number.end));
    data.push(String::from("0x0,0x0,0x0,0x0"));
    data.join(",")
}

fn main() {
    let path = Path::new("data.json");
    let display = path.display();

    let mut file = match File::open(&path) {
        Err(why) => panic!("couldn't open {}: {}", display, why),
        Ok(file) => file,
    };
    
    let mut s = String::new();
    if let Err(why) = file.read_to_string(&mut s) {
        panic!("couldn't read {}: {}", display, why);
    }
    let dataset: DataSet = serde_json::from_str(&s).unwrap();

    let cho_table = hex_table(&dataset.cho);
    let jung_table = hex_table(&dataset.jung);
    let jong_table = hex_table(&dataset.jong);
    let han_table = hex_table(&dataset.han);
    let english_upper_table = hex_table(&dataset.englishUpper);
    let english_lower_table = hex_table(&dataset.englishLower);
    let number_table = hex_table(&dataset.number);
    println!(".set cho_table_stride, {}", cho_table.1);
    println!(".set jung_table_stride, {}", jung_table.1);
    println!(".set jong_table_stride, {}", jong_table.1);
    println!(".set han_table_stride, {}", han_table.1);
    println!(".set english_upper_table_stride, {}", english_upper_table.1);
    println!(".set english_lower_table_stride, {}", english_lower_table.1);
    println!(".set number_table_stride, {}", number_table.1);
    println!("cho_table: {}", cho_table.0);
    println!("jung_table: {}", jung_table.0);
    println!("jong_table: {}", jong_table.0);
    println!("han_table: {}", han_table.0);
    println!("english_upper_table: {}", english_upper_table.0);
    println!("english_lower_table: {}", english_lower_table.0);
    println!("number_table: {}", number_table.0);
    println!("ranges_data: .byte {}", hex_ranges(&dataset.range));
}
