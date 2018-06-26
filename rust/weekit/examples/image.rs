extern crate weekit;

use std::ffi::CString;
use std::os::raw::c_char;
use weekit::openvg::{vgDestroyImage, vgSetPixels, VGImage};
use weekit::*;

extern "C" {
    fn createImageFromJpegFile(filename: *const c_char) -> VGImage;
}

struct Demo<'a> {
    serif_typeface: Option<font::Font<'a>>,
}

impl<'a> Demo<'a> {
    fn new() -> Demo<'a> {
        Demo {
            serif_typeface: None,
        }
    }
    fn load_fonts(&mut self) -> () {
        self.serif_typeface = Some(font::Font::serif());
    }
}

impl<'a> Application for Demo<'a> {
    fn draw(&mut self, width: u32, height: u32) -> () {
        match self.serif_typeface {
            Some(_) => (),
            None => self.load_fonts(),
        }

        let canvas = draw::Canvas::new(width, height);
        canvas.background(192, 0, 0);

        unsafe {
            let image = createImageFromJpegFile(CString::new("/tmp/sample.jpg").unwrap().as_ptr());
            vgSetPixels(0, 0, image, 0, 0, 800, 480);
            vgDestroyImage(image);
        }

        draw::fill(255, 255, 255, 1.0); // White text
        let title = "https://picsum.photos/800/400";
        match self.serif_typeface {
            Some(ref font) => draw::text_mid(
                width as f32 / 2.0,
                height as f32 * 0.1,
                title,
                font,
                width / 30,
            ),
            None => {}
        }
    }

    fn handle(&mut self, ev: &event::Event) {
        match ev {
            _default => {}
        }
    }
}

fn main() {
    weekit::main(Demo::new());
}
