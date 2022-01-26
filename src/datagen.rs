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

fn hex_table(data: &[String]) -> (String, usize) {
    let max_size = data.iter().map(|item| {
        item.as_bytes().len()
    }).reduce(|accum, item| {
        std::cmp::max(accum, item)
    }).unwrap() + 1;
    let mut table: Vec<u8> = Vec::with_capacity(max_size * data.len());
    data.iter().for_each(|s| {
        for i in 0..s.len() {
            table.push(s.as_bytes()[i]);
        }
        for i in s.len()..max_size {
            table.push(0);
        }
    });
    let mut joined = table.iter().map(|ch| {
        format!("0x{:02x?}", ch)
    }).fold(String::new(), |a, b| a + &b + ",");
    joined = joined[0..joined.len() - 1].to_string();
    (joined, max_size)
}

fn hex_ranges(range: &Ranges) -> String {
    let mut data: Vec<String> = Vec::new();
    data.push(format!("0x{:x?}", range.completeHangul.start));
    data.push(format!("0x{:x?}", range.completeHangul.end));
    data.push(format!("0x{:x?}", range.notCompleteHangul.start));
    data.push(format!("0x{:x?}", range.notCompleteHangul.end));
    data.push(format!("0x{:x?}", range.uppercase.start));
    data.push(format!("0x{:x?}", range.uppercase.end));
    data.push(format!("0x{:x?}", range.lowercase.start));
    data.push(format!("0x{:x?}", range.lowercase.end));
    data.push(format!("0x{:x?}", range.number.start));
    data.push(format!("0x{:x?}", range.number.end));
    data.push(String::from("0x0"));
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

    println!("cho_table: .byte {}", hex_table(&dataset.cho).0);
    println!("jung_table: .byte {}", hex_table(&dataset.jung).0);
    println!("han_table: .byte {}", hex_table(&dataset.han).0);
    println!("ranges_data: .word {}", hex_ranges(&dataset.range));
}
