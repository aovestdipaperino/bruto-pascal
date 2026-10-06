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
        let cfg = config::Config::load(&config_path);
        let show_about = if config_path.exists() {
            cfg.show_about_dialog_on_start
        } else {
            let _ = config::Config::update(&config_path, |c| {
                c.show_about_dialog_on_start = false;
            });
            true
        };

        let on_about_shown: Option<Box<dyn FnMut()>> = if show_about && config_path.exists() {
            // Pre-existing config that asked us to show: flip it to false now
            // that the dialog has been shown. (The first-run path already
            // wrote false above, so this only matters for that case.)
            let path = config_path.clone();
            Some(Box::new(move || {
                let _ = config::Config::update(&path, |c| {
                    c.show_about_dialog_on_start = false;
                });
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
            build_options: cfg.build.to_options(),
            on_build_options_changed: Some(Box::new(move |opts| {
                let _ = config::Config::update(&config_path, |c| {
                    c.build = config::BuildConfig::from(opts);
                });
            })),
        };

        if let Err(e) =
            bruto_ide::ide::run_with_options(Box::new(bruto_pascal_lang::MiniPascal), options)
        {
            eprintln!("IDE error: {e}");
            process::exit(1);
        }
        return;
    }

    // CLI mode — parse flags
    let mut run_after = false;
    let mut source_file = None;
    let mut output_file = None;
    let mut build_options = bruto_lang::language::BuildOptions::default();

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
            "--debug" => build_options.profile = bruto_lang::language::BuildProfile::Debug,
            "--retail" | "--release" => {
                build_options.profile = bruto_lang::language::BuildProfile::Retail
            }
            "--optimize" => {
                i += 1;
                let goal = args
                    .get(i)
                    .and_then(|a| bruto_lang::language::OptimizeFor::parse(a));
                match goal {
                    Some(g) => build_options.optimize = g,
                    None => {
                        eprintln!("error: --optimize requires size, both or speed");
                        process::exit(1);
                    }
                }
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
    let code = compile_and_run(
        &source_file,
        output_file.as_deref(),
        run_after,
        build_options,
    );
    process::exit(code);
}

fn compile_and_run(
    source_file: &str,
    output_file: Option<&str>,
    run_after: bool,
    build_options: bruto_lang::language::BuildOptions,
) -> i32 {
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
            let stem = source_path
                .file_stem()
                .unwrap_or_default()
                .to_string_lossy();
            let dir = source_path
                .parent()
                .filter(|p| !p.as_os_str().is_empty())
                .unwrap_or(Path::new("."));
            dir.join(stem.as_ref()).to_string_lossy().to_string()
        }
    };

    // Parse
    let mut parser = bruto_pascal_lang::parser::Parser::new(&source);
    let mut program = match parser.parse_program() {
        Ok(p) => p,
        Err(e) => {
            eprintln!("{source_file}:{e}");
            return 1;
        }
    };

    // Resolve `uses` against the source file's directory + cwd.
    let mut search_dirs: Vec<std::path::PathBuf> = Vec::new();
    if let Some(dir) = source_path.parent() {
        if !dir.as_os_str().is_empty() {
            search_dirs.push(dir.to_path_buf());
        }
    }
    if let Ok(cwd) = std::env::current_dir() {
        if !search_dirs.iter().any(|d| d == &cwd) {
            search_dirs.push(cwd);
        }
    }
    if let Err(e) = bruto_pascal_lang::resolve_uses(&mut program, &search_dirs) {
        eprintln!("error: {e}");
        return 1;
    }

    // Codegen
    let source_abs =
        std::fs::canonicalize(source_path).unwrap_or_else(|_| source_path.to_path_buf());
    let context = inkwell::context::Context::create();
    let mut codegen = bruto_pascal_lang::codegen::CodeGen::new(
        &context,
        source_abs.to_str().unwrap_or(source_file),
    );
    codegen.set_directives(parser.directives);
    codegen.set_build_options(build_options);
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

    eprintln!(
        "Compiled ({}): {source_file} -> {exe_path}",
        build_options.describe()
    );

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
    eprintln!("  --debug         Debug build with DWARF info, unoptimized (default)");
    eprintln!("  --retail        Optimized build without debug info");
    eprintln!("  --optimize <g>  Retail optimization goal: size, both (default), speed");
    eprintln!("  -h, --help      Show this help");
}
