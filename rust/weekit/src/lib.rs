#![allow(dead_code)]

#[macro_use]
extern crate lazy_static;

pub mod draw;
pub mod event;
pub mod font;
pub mod key;

mod input;
mod openvg;

use std::sync::{Arc, Mutex};

#[cfg(target_os = "macos")]
fn platform() -> String {
   "macos".to_string()
}

#[cfg(target_os = "linux")]
fn platform() -> String {
   "linux".to_string()
}

/// Specifies required application capabilities.
pub trait Application {
    /// Resizes the current application screen.
    fn size(&mut self, _width: u32, _height: u32) -> () {}

    /// Draws the current application screen.
    fn draw(&mut self, width: u32, height: u32) -> ();

    /// Handles application events.
    fn handle(&mut self, _event: &event::Event) -> () {}
}

/// Starts the application and runs the main event loop.
pub fn main<T: Application + 'static>(application: T) -> i64 {
    unsafe {
	println!("Running on {}", platform());
        APPLICATION = Some(Arc::new(Mutex::new(application)));
        INPUT_LISTENER = Some(input::Listener::new());
        return WKMain(size_handler, draw_handler, input_handler, tick_handler);
    }
}

extern "C" {
    fn WKMain(
        s: extern "C" fn(u32, u32) -> (),
        f: extern "C" fn(u32, u32) -> (),
        e: extern "C" fn(u16, u16, i32) -> (),
        t: extern "C" fn() -> (),
    ) -> i64;
}

static mut APPLICATION: Option<Arc<Mutex<Application>>> = None;

extern "C" fn size_handler(width: u32, height: u32) -> () {
    unsafe {
        match APPLICATION {
            Some(ref arc) => {
                let arc = arc.clone();
                arc.lock().unwrap().size(width, height);
            }
            None => {}
        }
    }
}

extern "C" fn draw_handler(width: u32, height: u32) -> () {
    unsafe {
        match APPLICATION {
            Some(ref arc) => {
                let arc = arc.clone();
                arc.lock().unwrap().draw(width, height);
            }
            None => {}
        }
    }
}

extern "C" fn tick_handler() -> () {
    unsafe {
        match APPLICATION {
            Some(ref arc) => {
                let arc = arc.clone();
                arc.lock().unwrap().handle(&event::Event::new_tick());
            }
            None => {}
        }
    }
}

static mut INPUT_LISTENER: Option<input::Listener> = None;

extern "C" fn input_handler(t: u16, c: u16, v: i32) -> () {
    unsafe {
        match INPUT_LISTENER {
            Some(ref mut listener) => match APPLICATION {
                Some(ref arc) => listener.handle(t, c, v, arc.clone()),
                None => {}
            },
            None => {}
        }
    }
}
