mod config;
mod update;

use std::env;
use std::path::Path;
use std::process;

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        // No arguments — launch IDE
        let config_path = config::config_path();

        // First run = config file is missing. Write it eagerly with the flag
        // already flipped to false, then show the About dialog this one time.
        // Eager-write means even a crash during the dialog won't replay it.
        let show_about = if config_path.exists() {
            let cfg = config::Config::load(&config_path);
            cfg.show_about_dialog_on_start
        } else {
            let _ = config::Config { show_about_dialog_on_start: false }.save(&config_path);
            true
        };

        let on_about_shown: Option<Box<dyn FnMut()>> = if show_about && config_path.exists() {
            // Pre-existing config that asked us to show: flip it to false now
            // that the dialog has been shown. (The first-run path already
            // wrote false above, so this only matters for that case.)
            let path = config_path.clone();
            Some(Box::new(move || {
                let _ = config::Config { show_about_dialog_on_start: false }.save(&path);
            }))
        } else {
            None
        };

        let options = bruto_ide::ide::IdeOptions {
            show_about_on_start: show_about,
            on_about_shown,
            about_text: Some(format!(
                "Bruto Pascal {}\n\n(c) 2026 Enzo Lombardi",
                env!("CARGO_PKG_VERSION"),
            )),
            on_desktop_ready: Some(Box::new(|app| {
                update::check_and_prompt(app);
            })),
        };

        if let Err(e) = bruto_ide::ide::run_with_options(
            Box::new(bruto_pascal_lang::MiniPascal),
            options,
        ) {
            eprintln!("IDE error: {e}");
            process::exit(1);
        }
        return;
    }

    // CLI mode — parse flags
    let mut run_after = false;
    let mut source_file = None;
    let mut output_file = None;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "-r" | "--run" => run_after = true,
            "-o" | "--output" => {
                i += 1;
                if i >= args.len() {
                    eprintln!("error: -o requires an output path");
                    process::exit(1);
                }
                output_file = Some(args[i].clone());
            }
            "-h" | "--help" => {
                print_usage();
                return;
            }
            arg if arg.starts_with('-') => {
                eprintln!("error: unknown option '{arg}'");
                print_usage();
                process::exit(1);
            }
            _ => {
                if source_file.is_some() {
                    eprintln!("error: multiple source files not supported");
                    process::exit(1);
                }
                source_file = Some(args[i].clone());
            }
        }
        i += 1;
    }

    let source_file = match source_file {
        Some(f) => f,
        None => {
            eprintln!("error: no source file specified");
            print_usage();
            process::exit(1);
        }
    };

    // Compile
    let code = compile_and_run(&source_file, output_file.as_deref(), run_after);
    process::exit(code);
}

fn compile_and_run(source_file: &str, output_file: Option<&str>, run_after: bool) -> i32 {
    let source_path = Path::new(source_file);
    if !source_path.exists() {
        eprintln!("error: file not found: {source_file}");
        return 1;
    }

    let source = match std::fs::read_to_string(source_path) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("error: cannot read '{source_file}': {e}");
            return 1;
        }
    };

    // Determine output path: -o flag, or replace .pas with no extension
    let exe_path = match output_file {
        Some(p) => p.to_string(),
        None => {
            let stem = source_path.file_stem().unwrap_or_default().to_string_lossy();
            let dir = source_path.parent().filter(|p| !p.as_os_str().is_empty()).unwrap_or(Path::new("."));
            dir.join(stem.as_ref()).to_string_lossy().to_string()
        }
    };

    // Parse
    let mut parser = bruto_pascal_lang::parser::Parser::new(&source);
    let program = match parser.parse_program() {
        Ok(p) => p,
        Err(e) => {
            eprintln!("{source_file}:{e}");
            return 1;
        }
    };

    // Codegen
    let source_abs = std::fs::canonicalize(source_path)
        .unwrap_or_else(|_| source_path.to_path_buf());
    let context = inkwell::context::Context::create();
    let mut codegen = bruto_pascal_lang::codegen::CodeGen::new(
        &context,
        source_abs.to_str().unwrap_or(source_file),
    );
    codegen.set_directives(parser.directives);
    if let Err(e) = codegen.compile(&program) {
        eprintln!("{source_file}:{e}");
        return 1;
    }

    // Emit executable
    if let Err(e) = codegen.emit_executable(&exe_path) {
        eprintln!("error: {e}");
        return 1;
    }
    let _ = codegen.write_metadata(&exe_path);

    eprintln!("Compiled: {source_file} -> {exe_path}");

    // Run if requested
    if run_after {
        eprintln!("Running {exe_path}...");
        match std::process::Command::new(&exe_path).status() {
            Ok(status) => {
                let code = status.code().unwrap_or(1);
                if code != 0 {
                    eprintln!("Exit code: {code}");
                }
                return code;
            }
            Err(e) => {
                eprintln!("error: failed to run '{exe_path}': {e}");
                return 1;
            }
        }
    }

    0
}

fn print_usage() {
    eprintln!("Bruto Pascal Compiler");
    eprintln!();
    eprintln!("Usage:");
    eprintln!("  brutop                     Launch IDE");
    eprintln!("  brutop <file.pas>           Compile to executable");
    eprintln!("  brutop -r <file.pas>        Compile and run");
    eprintln!("  brutop -o <out> <file.pas>  Compile to specific output path");
    eprintln!();
    eprintln!("Options:");
    eprintln!("  -r, --run       Compile and run immediately");
    eprintln!("  -o, --output    Specify output executable path");
    eprintln!("  -h, --help      Show this help");
}
