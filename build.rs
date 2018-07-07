use std::env;
use std::process::Command;

fn main() {
    let target = env::var("TARGET").unwrap();
    println!("target {}", target);

    if target.contains("apple") {
        let out_dir = env::var("OUT_DIR").unwrap();
        println!("OUT_DIR = {}", out_dir);
        Command::new("make")
            .arg(&"-f")
            .arg(&"tools/Makefile.macOS")
            .status()
            .unwrap();
        println!("cargo:rustc-link-search=native={}", out_dir);
        println!("cargo:rustc-link-lib=platform");
        println!("cargo:rustc-link-search=native=/usr/local/lib");
        println!("cargo:rustc-link-lib=jpeg");
        println!(
            "cargo:rustc-link-search=native=third-party/amanithvg-sdk/lib/macosx/ub/gle/standalone"
        );
        println!("cargo:rustc-link-lib=AmanithVG.4");
        println!("cargo:rustc-link-lib=framework=Cocoa");
        println!("cargo:rustc-link-lib=framework=OpenGL");
        println!("cargo:rustc-link-lib=framework=QuartzCore");
    } else {
        let out_dir = env::var("OUT_DIR").unwrap();
        println!("OUT_DIR = {}", out_dir);
        Command::new("make")
            .arg(&"-f")
            .arg(&"tools/Makefile.pi")
            .status()
            .unwrap();
        println!("cargo:rustc-link-search=native={}", out_dir);
        println!("cargo:rustc-link-search=native=/opt/vc/lib");
        println!("cargo:rustc-link-lib=platform");
        println!("cargo:rustc-link-lib=jpeg");
        println!("cargo:rustc-link-lib=brcmOpenVG");
        println!("cargo:rustc-link-lib=brcmEGL");
        println!("cargo:rustc-link-lib=bcm_host");
        println!("cargo:rustc-link-lib=vcos");
        println!("cargo:rustc-link-lib=brcmGLESv2");
    }
}
