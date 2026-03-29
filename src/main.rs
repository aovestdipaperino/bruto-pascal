#![allow(dead_code)]

mod ast;
mod codegen;
mod commands;
mod debugger;
mod gutter;
mod ide_editor;
mod parser;
mod pascal_syntax;
mod output_panel;
mod watch_window;

use crate::codegen::CodeGen;
use crate::commands::*;
use crate::debugger::{DebugEvent, Debugger};
use crate::gutter::BreakpointGutter;
use crate::ide_editor::IdeEditorWindow;
use crate::output_panel::OutputPanel;
use crate::parser::Parser;
use crate::pascal_syntax::PascalHighlighter;
use crate::watch_window::WatchPanel;

use inkwell::context::Context;
use std::cell::RefCell;
use std::rc::Rc;
use std::time::Duration;

use turbo_vision::app::Application;
use turbo_vision::core::command::{CM_NEW, CM_OPEN, CM_QUIT, CM_SAVE, CM_SAVE_AS};
use turbo_vision::core::event::{Event, EventType, KB_F2, KB_F3, KB_F5, KB_F7, KB_F8, KB_F9};
use turbo_vision::core::geometry::Rect;
use turbo_vision::core::menu_data::{Menu, MenuItem};
use turbo_vision::core::palette::{Attr, TvColor};
use turbo_vision::views::menu_bar::{MenuBar, SubMenu};
use turbo_vision::views::status_line::{StatusItem, StatusLine};
use turbo_vision::views::terminal_widget::TerminalWidget;
use turbo_vision::views::window::Window;
use turbo_vision::views::View;

/// Central IDE state, kept outside the view hierarchy.
struct IdeState {
    debugger: Debugger,
    watch_vars: Vec<(String, String)>,
    source_path: Option<String>,
    exe_path: Option<String>,
    exec_line: Option<usize>,
}

impl IdeState {
    fn new() -> Self {
        Self {
            debugger: Debugger::new(),
            watch_vars: Vec::new(),
            source_path: None,
            exe_path: None,
            exec_line: None,
        }
    }
}

fn main() -> turbo_vision::core::error::Result<()> {
    let mut app = Application::new()?;
    let (width, height) = app.terminal.size();
    let w = width as i16;
    let h = height as i16;

    // ── Menu bar ─────────────────────────────────────────
    let menu_bar = build_menu_bar(w);
    app.set_menu_bar(menu_bar);

    // ── Status line ──────────────────────────────────────
    let status_line = build_status_line(w, h);
    app.set_status_line(status_line);

    // ── Layout ───────────────────────────────────────────
    //  Desktop area: row 1 .. h-2 (menu=row 0, status=row h-1)
    let desktop_top = 1;
    let desktop_bottom = h - 1;
    let desktop_h = desktop_bottom - desktop_top;

    // Editor window: left ~70%, full height of desktop
    let watch_width: i16 = 26;
    let output_height: i16 = (desktop_h / 4).max(5);
    let editor_right = w - watch_width;
    let editor_bottom = desktop_bottom - output_height;

    // ── Editor window (contains gutter + editor) ─────────
    let editor_bounds = Rect::new(0, desktop_top, editor_right, editor_bottom);
    let ide_win = IdeEditorWindow::new(editor_bounds, "Untitled.pas");
    ide_win.set_highlighter(Box::new(PascalHighlighter::new()));
    ide_win.set_text(SAMPLE_PROGRAM);
    let editor_rc = ide_win.editor_rc();
    let gutter_rc = ide_win.gutter_rc();
    app.desktop.add(Box::new(ide_win));

    // ── Watch window (separate window, right side) ───────
    let watch_bounds = Rect::new(editor_right, desktop_top, w, editor_bottom);
    let watch = Rc::new(RefCell::new(WatchPanel::new(
        // Interior-relative bounds: (0,0) to (interior_w, interior_h)
        Rect::new(0, 0, watch_width - 2, editor_bottom - desktop_top - 2),
    )));
    let mut watch_win = Window::new(watch_bounds, "Watches");
    watch_win.add(Box::new(WatchView(Rc::clone(&watch))));
    app.desktop.add(Box::new(watch_win));

    // ── Output (modeless Dialog with TerminalWidget, black background) ──
    let output_bounds = Rect::new(0, editor_bottom, w, desktop_bottom);
    let output_panel = OutputPanel::new(output_bounds, "Output");
    let output_term = output_panel.terminal_rc();
    output_term.borrow_mut().append_line("Bruto Pascal IDE ready. Press F9 to build.".into());
    app.desktop.add(Box::new(output_panel));

    // ── IDE state ────────────────────────────────────────
    let mut ide = IdeState::new();

    // ── Event loop ───────────────────────────────────────
    app.running = true;
    while app.running {
        // Draw
        app.desktop.draw(&mut app.terminal);
        if let Some(ref mut mb) = app.menu_bar {
            mb.draw(&mut app.terminal);
        }
        if let Some(ref mut sl) = app.status_line {
            sl.draw(&mut app.terminal);
        }
        let _ = app.terminal.flush();

        // Update watch panel from debugger state
        watch.borrow_mut().set_variables(ide.watch_vars.clone());

        // Update exec line highlight in gutter
        gutter_rc.borrow_mut().set_current_exec_line(ide.exec_line);

        // Poll debugger
        if ide.debugger.is_running() {
            let events = ide.debugger.poll();
            for dbg_event in events {
                match dbg_event {
                    DebugEvent::Stopped { line, .. } => {
                        ide.exec_line = Some(line);
                    }
                    DebugEvent::Variables(vars) => {
                        for (name, value) in vars {
                            let mut found = false;
                            for (n, v) in &mut ide.watch_vars {
                                if *n == name {
                                    *v = value.clone();
                                    found = true;
                                    break;
                                }
                            }
                            if !found {
                                ide.watch_vars.push((name, value));
                            }
                        }
                    }
                    DebugEvent::ProgramOutput(line) => {
                        append_output_line(
                            &mut output_term.borrow_mut(),
                            &line,
                            None,
                        );
                    }
                    DebugEvent::Exited { code } => {
                        ide.exec_line = None;
                        ide.watch_vars.clear();
                        let color = if code == 0 {
                            Attr::new(TvColor::LightGreen, TvColor::Black)
                        } else {
                            Attr::new(TvColor::LightRed, TvColor::Black)
                        };
                        append_output_line(
                            &mut output_term.borrow_mut(),
                            &format!("Process exited with code {}", code),
                            Some(color),
                        );
                    }
                }
            }
        }

        // Poll terminal events
        match app.terminal.poll_event(Duration::from_millis(30)) {
            Ok(Some(mut event)) => {
                // Status line pre-process
                if let Some(ref mut sl) = app.status_line {
                    sl.handle_event(&mut event);
                }

                // Menu bar
                if let Some(ref mut mb) = app.menu_bar {
                    mb.handle_event(&mut event);
                    if event.what == EventType::Keyboard || event.what == EventType::MouseUp {
                        if let Some(cmd) = mb.check_cascading_submenu(&mut app.terminal) {
                            if cmd != 0 {
                                event = Event::command(cmd);
                            }
                        }
                    }
                }

                // Handle function key shortcuts BEFORE desktop
                if event.what == EventType::Keyboard {
                    match event.key_code {
                        KB_F9 => {
                            handle_build(&editor_rc, &mut output_term.borrow_mut(), &mut ide);
                            event.clear();
                        }
                        KB_F5 => {
                            handle_debug_start_continue(
                                &editor_rc,
                                &gutter_rc,
                                &mut output_term.borrow_mut(),
                                &mut ide,
                            );
                            event.clear();
                        }
                        KB_F7 => {
                            if ide.debugger.is_running() {
                                let _ = ide.debugger.step_into();
                            }
                            event.clear();
                        }
                        KB_F8 => {
                            if ide.debugger.is_running() {
                                let _ = ide.debugger.step_over();
                            }
                            event.clear();
                        }
                        _ => {}
                    }
                }

                // Desktop handles mouse/keyboard
                app.desktop.handle_event(&mut event);

                // Handle commands from menus/status bar
                if event.what == EventType::Command {
                    handle_command(
                        event.command,
                        &mut app,
                        &editor_rc,
                        &gutter_rc,
                        &mut output_term.borrow_mut(),
                        &mut ide,
                    );
                }
            }
            Ok(None) => {}
            Err(_) => {}
        }
    }

    Ok(())
}

// ── Command handler ──────────────────────────────────────

fn handle_command(
    cmd: u16,
    app: &mut Application,
    editor_rc: &Rc<RefCell<turbo_vision::views::editor::Editor>>,
    gutter: &Rc<RefCell<BreakpointGutter>>,
    output: &mut TerminalWidget,
    ide: &mut IdeState,
) {
    match cmd {
        CM_QUIT => {
            ide.debugger.stop();
            app.running = false;
        }
        CM_BUILD => {
            handle_build(editor_rc, output, ide);
        }
        CM_RUN => {
            handle_build(editor_rc, output, ide);
            if let Some(ref exe) = ide.exe_path.clone() {
                handle_run(exe, output);
            }
        }
        CM_DEBUG_START | CM_DEBUG_CONTINUE => {
            handle_debug_start_continue(editor_rc, gutter, output, ide);
        }
        CM_DEBUG_STOP => {
            ide.debugger.stop();
            ide.exec_line = None;
            ide.watch_vars.clear();
            append_output_line(
                output,
                "Debugger stopped.",
                Some(Attr::new(TvColor::Yellow, TvColor::Black)),
            );
        }
        CM_DEBUG_STEP_OVER => {
            if ide.debugger.is_running() {
                let _ = ide.debugger.step_over();
            }
        }
        CM_DEBUG_STEP_INTO => {
            if ide.debugger.is_running() {
                let _ = ide.debugger.step_into();
            }
        }
        CM_ABOUT => {
            show_about_dialog(app);
        }
        _ => {}
    }
}

fn show_about_dialog(app: &mut Application) {
    use turbo_vision::views::msgbox::message_box_ok;
    message_box_ok(
        app,
        concat!(
            "\x03",  // center text
            "Bruto Pascal IDE\n",
            "\n",
            "Version 0.1.0\n",
            "\n",
            "A Mini-Pascal IDE with\n",
            "LLVM backend and lldb debugger\n",
            "\n",
            "Built with Turbo Vision for Rust\n",
            "\n",
            "(c) 2026 Enzo Lombardi",
        ),
    );
}

// ── Build ────────────────────────────────────────────────

fn handle_build(
    editor_rc: &Rc<RefCell<turbo_vision::views::editor::Editor>>,
    output: &mut TerminalWidget,
    ide: &mut IdeState,
) {
    let source = editor_rc.borrow().get_text();

    // Save source to a real file so DWARF debug info file references are valid
    // and lldb can resolve breakpoints.
    let source_path = "/tmp/turbo_pascal_src.pas".to_string();
    if let Err(e) = std::fs::write(&source_path, &source) {
        append_output_line(
            output,
            &format!("Failed to write source: {}", e),
            Some(Attr::new(TvColor::LightRed, TvColor::Black)),
        );
        return;
    }
    ide.source_path = Some(source_path.clone());

    output.clear();
    append_output_line(
        output,
        "Building...",
        Some(Attr::new(TvColor::Yellow, TvColor::Black)),
    );

    // Parse
    let mut parser = Parser::new(&source);
    let program = match parser.parse_program() {
        Ok(p) => p,
        Err(e) => {
            append_output_line(
                output,
                &format!("Parse error: {}", e),
                Some(Attr::new(TvColor::LightRed, TvColor::Black)),
            );
            return;
        }
    };

    // Codegen — use the real source path so DWARF references resolve
    let context = Context::create();
    let mut codegen = CodeGen::new(&context, &source_path);
    if let Err(e) = codegen.compile(&program) {
        append_output_line(
            output,
            &format!("Codegen error: {}", e),
            Some(Attr::new(TvColor::LightRed, TvColor::Black)),
        );
        return;
    }

    // Emit executable
    let exe_path = "/tmp/turbo_pascal_out".to_string();
    match codegen.emit_executable(&exe_path) {
        Ok(()) => {
            ide.exe_path = Some(exe_path.clone());
            append_output_line(
                output,
                &format!("Build successful: {}", exe_path),
                Some(Attr::new(TvColor::LightGreen, TvColor::Black)),
            );
        }
        Err(e) => {
            append_output_line(
                output,
                &format!("Link error: {}", e),
                Some(Attr::new(TvColor::LightRed, TvColor::Black)),
            );
        }
    }
}

// ── Run ──────────────────────────────────────────────────

fn handle_run(exe_path: &str, output: &mut TerminalWidget) {
    output.clear();
    output.append_line_colored(
        format!("Running {}...", exe_path),
        CONSOLE_INFO,
    );

    // Truncate capture file, then run — program writes output there via fprintf
    let _ = std::fs::write("/tmp/turbo_pascal_console.txt", "");

    let status = std::process::Command::new(exe_path)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status();

    // Read captured output
    if let Ok(contents) = std::fs::read_to_string("/tmp/turbo_pascal_console.txt") {
        for line in contents.lines() {
            output.append_line(line.to_string());
        }
    }

    match status {
        Ok(s) => {
            let code = s.code().unwrap_or(-1);
            let color = if code == 0 {
                Attr::new(TvColor::LightGreen, TvColor::Black)
            } else {
                CONSOLE_ERR
            };
            output.append_line_colored(format!("Exit code: {}", code), color);
        }
        Err(e) => {
            output.append_line_colored(format!("Failed to run: {}", e), CONSOLE_ERR);
        }
    }
}

// ── Debug ────────────────────────────────────────────────

fn handle_debug_start_continue(
    editor_rc: &Rc<RefCell<turbo_vision::views::editor::Editor>>,
    gutter: &Rc<RefCell<BreakpointGutter>>,
    output: &mut TerminalWidget,
    ide: &mut IdeState,
) {
    if ide.debugger.is_running() {
        let _ = ide.debugger.continue_exec();
        ide.exec_line = None;
        return;
    }

    // Build first
    handle_build(editor_rc, output, ide);
    let Some(ref exe_path) = ide.exe_path.clone() else {
        append_output_line(
            output,
            "No executable to debug.",
            Some(Attr::new(TvColor::LightRed, TvColor::Black)),
        );
        return;
    };

    let source_file = ide
        .source_path
        .clone()
        .unwrap_or_else(|| "untitled.pas".to_string());
    let bp_lines = gutter.borrow().breakpoint_lines();

    append_output_line(
        output,
        &format!("Starting debugger with {} breakpoint(s)...", bp_lines.len()),
        Some(Attr::new(TvColor::Yellow, TvColor::Black)),
    );

    output.clear();

    match ide.debugger.start(exe_path, &source_file, &bp_lines) {
        Ok(()) => {
            append_output_line(
                output,
                "Debugger started.",
                Some(Attr::new(TvColor::LightGreen, TvColor::Black)),
            );
        }
        Err(e) => {
            append_output_line(
                output,
                &format!("Debugger error: {}", e),
                Some(Attr::new(TvColor::LightRed, TvColor::Black)),
            );
        }
    }
}

// ── Output helpers ───────────────────────────────────────

const CONSOLE_ERR: Attr = Attr::new(TvColor::LightRed, TvColor::Black);
const CONSOLE_INFO: Attr = Attr::new(TvColor::Yellow, TvColor::Black);

fn append_output_line(panel: &mut TerminalWidget, text: &str, attr: Option<Attr>) {
    if let Some(attr) = attr {
        panel.append_line_colored(text.to_string(), attr);
    } else {
        panel.append_line(text.to_string());
    }
}

// ── View wrappers for Rc<RefCell<...>> inside Windows ────

struct WatchView(Rc<RefCell<WatchPanel>>);

impl View for WatchView {
    fn bounds(&self) -> Rect { self.0.borrow().bounds() }
    fn set_bounds(&mut self, b: Rect) { self.0.borrow_mut().set_bounds(b); }
    fn draw(&mut self, t: &mut turbo_vision::terminal::Terminal) { self.0.borrow_mut().draw(t); }
    fn handle_event(&mut self, e: &mut Event) { self.0.borrow_mut().handle_event(e); }
    fn state(&self) -> turbo_vision::core::state::StateFlags { self.0.borrow().state() }
    fn set_state(&mut self, s: turbo_vision::core::state::StateFlags) { self.0.borrow_mut().set_state(s); }
    fn get_palette(&self) -> Option<turbo_vision::core::palette::Palette> { None }
}

// ── Menu and status bar builders ─────────────────────────

fn build_menu_bar(width: i16) -> MenuBar {
    let file_menu = Menu::from_items(vec![
        MenuItem::with_shortcut("~N~ew", CM_NEW, 0, "", 0),
        MenuItem::with_shortcut("~O~pen...", CM_OPEN, KB_F3, "F3", 0),
        MenuItem::with_shortcut("~S~ave", CM_SAVE, KB_F2, "F2", 0),
        MenuItem::with_shortcut("Save ~A~s...", CM_SAVE_AS, 0, "", 0),
        MenuItem::separator(),
        MenuItem::with_shortcut("E~x~it", CM_QUIT, 0x012D, "Alt-X", 0),
    ]);
    let build_menu = Menu::from_items(vec![
        MenuItem::with_shortcut("~B~uild", CM_BUILD, KB_F9, "F9", 0),
        MenuItem::with_shortcut("~R~un", CM_RUN, 0, "Ctrl-F9", 0),
    ]);
    let debug_menu = Menu::from_items(vec![
        MenuItem::with_shortcut("~S~tart / Continue", CM_DEBUG_START, KB_F5, "F5", 0),
        MenuItem::with_shortcut("Step ~O~ver", CM_DEBUG_STEP_OVER, KB_F8, "F8", 0),
        MenuItem::with_shortcut("Step ~I~nto", CM_DEBUG_STEP_INTO, KB_F7, "F7", 0),
        MenuItem::separator(),
        MenuItem::with_shortcut("Sto~p~", CM_DEBUG_STOP, 0, "Shift-F5", 0),
    ]);

    let about_menu = Menu::from_items(vec![
        MenuItem::with_shortcut("~A~bout...", CM_ABOUT, 0, "", 0),
    ]);

    let mut menu_bar = MenuBar::new(Rect::new(0, 0, width, 1));
    menu_bar.add_submenu(SubMenu::new("\u{F0} ", about_menu)); // ≡ system menu
    menu_bar.add_submenu(SubMenu::new("~F~ile", file_menu));
    menu_bar.add_submenu(SubMenu::new("~B~uild", build_menu));
    menu_bar.add_submenu(SubMenu::new("~D~ebug", debug_menu));
    menu_bar
}

fn build_status_line(width: i16, height: i16) -> StatusLine {
    StatusLine::new(
        Rect::new(0, height - 1, width, height),
        vec![
            StatusItem::new("~F5~ Debug", KB_F5, CM_DEBUG_START),
            StatusItem::new("~F7~ Step", KB_F7, CM_DEBUG_STEP_INTO),
            StatusItem::new("~F8~ Next", KB_F8, CM_DEBUG_STEP_OVER),
            StatusItem::new("~F9~ Build", KB_F9, CM_BUILD),
            StatusItem::new("~Alt-X~ Exit", 0x012D, CM_QUIT),
        ],
    )
}

// ── Sample program ───────────────────────────────────────

const SAMPLE_PROGRAM: &str = r#"program Hello;
var
  x: integer;
  i: integer;
begin
  x := 0;
  i := 1;
  while i <= 10 do
  begin
    x := x + i;
    i := i + 1
  end;
  writeln('Sum of 1..10 = ', x);
  if x = 55 then
    writeln('Correct!')
  else
    writeln('Wrong!')
end.
"#;
