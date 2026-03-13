fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage: shelf-icon <svg> <output.icns> [--nearest-neighbor]");
        std::process::exit(1);
    }
    let nn = args.iter().any(|a| a == "--nearest-neighbor");
    if shelf_core::icon::generate_icns(&args[1], &args[2], nn) {
        println!("Generated: {}", args[2]);
    } else {
        eprintln!("Failed to generate ICNS");
        std::process::exit(1);
    }
}
