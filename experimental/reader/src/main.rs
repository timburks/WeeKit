// Copyright 2018 The WeeKit Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License. 
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

use libc::timeval;
use std::fs::File;
use std::io::Read;
use std::mem;
use std::slice;
use std::thread;

extern crate libc;

#[repr(C, packed)]
struct InputEvent {
    time: timeval,
    kind: u16,
    code: u16,
    value: i32,
}

fn main() {
    println!("Hello, world!");
    handle_inputs("/dev/input/touchscreen");
    handle_inputs("/dev/input/keyboard");
    loop {}
}

fn handle_inputs(filename: &'static str) {
    thread::spawn(move || {
        let mut f = File::open(filename).expect(&("unable to open ".to_owned() + filename));

	// https://stackoverflow.com/questions/25410028/how-to-read-a-struct-from-a-file-in-rust
        let mut input_event: InputEvent = unsafe { mem::zeroed() };
        let input_event_size = mem::size_of::<InputEvent>();
        loop {
            unsafe {
                let input_event_slice = slice::from_raw_parts_mut(
                    &mut input_event as *mut _ as *mut u8,
                    input_event_size,
                );
                f.read_exact(input_event_slice).unwrap();
                println!(
                    "{} {} {}",
                    input_event.kind, input_event.code, input_event.value
                );
            }
        }
    });
}
