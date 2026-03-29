/// Breakpoint gutter — a narrow View placed to the left of the editor.
///
/// Displays breakpoint markers (red squares) and the current execution line indicator.
/// Mouse clicks on the gutter toggle breakpoints.

use std::collections::HashSet;
use turbo_vision::core::draw::DrawBuffer;
use turbo_vision::core::event::{Event, EventType, MB_LEFT_BUTTON};
use turbo_vision::core::geometry::Rect;
use turbo_vision::core::palette::{Attr, TvColor};
use turbo_vision::core::state::StateFlags;
use turbo_vision::terminal::Terminal;
use turbo_vision::views::view::{write_line_to_terminal, OwnerType, View};

/// Width of the gutter in characters.
pub const GUTTER_WIDTH: i16 = 3;

/// Color for breakpoint markers (red on dark background).
const BP_ATTR: Attr = Attr::new(TvColor::LightRed, TvColor::Red);

/// Color for current execution line indicator.
const EXEC_ATTR: Attr = Attr::new(TvColor::Yellow, TvColor::Blue);

/// Default gutter background.
const GUTTER_BG: Attr = Attr::new(TvColor::DarkGray, TvColor::Cyan);

pub struct BreakpointGutter {
    bounds: Rect,
    state: StateFlags,
    breakpoints: HashSet<usize>,
    top_line: usize,
    current_exec_line: Option<usize>,
    owner_type: OwnerType,
}

impl BreakpointGutter {
    pub fn new(bounds: Rect) -> Self {
        Self {
            bounds,
            state: 0,
            breakpoints: HashSet::new(),
            top_line: 0,
            current_exec_line: None,
            owner_type: OwnerType::Window,
        }
    }

    pub fn toggle_breakpoint(&mut self, line: usize) {
        if !self.breakpoints.remove(&line) {
            self.breakpoints.insert(line);
        }
    }

    pub fn has_breakpoint(&self, line: usize) -> bool {
        self.breakpoints.contains(&line)
    }

    pub fn breakpoints(&self) -> &HashSet<usize> {
        &self.breakpoints
    }

    pub fn breakpoint_lines(&self) -> Vec<usize> {
        self.breakpoints.iter().copied().collect()
    }

    pub fn set_top_line(&mut self, line: usize) {
        self.top_line = line;
    }

    pub fn current_exec_line(&self) -> Option<usize> {
        self.current_exec_line
    }

    pub fn set_current_exec_line(&mut self, line: Option<usize>) {
        self.current_exec_line = line;
    }
}

impl View for BreakpointGutter {
    fn bounds(&self) -> Rect {
        self.bounds
    }

    fn set_bounds(&mut self, bounds: Rect) {
        self.bounds = bounds;
    }

    fn draw(&mut self, terminal: &mut Terminal) {
        let height = self.bounds.height_clamped() as usize;
        let width = self.bounds.width_clamped() as usize;

        for row in 0..height {
            let line_num = self.top_line + row + 1; // 1-based line numbers
            let mut buf = DrawBuffer::new(width);

            // Fill background
            buf.move_char(0, ' ', GUTTER_BG, width);

            if self.breakpoints.contains(&line_num) {
                // Red square for breakpoint — use block character
                buf.put_char(1, '\u{25A0}', BP_ATTR); // ■
            } else if self.current_exec_line == Some(line_num) {
                // Execution indicator
                buf.put_char(1, '\u{25BA}', EXEC_ATTR); // ►
            }

            write_line_to_terminal(
                terminal,
                self.bounds.a.x,
                self.bounds.a.y + row as i16,
                &buf,
            );
        }
    }

    fn handle_event(&mut self, event: &mut Event) {
        if event.what == EventType::MouseDown && (event.mouse.buttons & MB_LEFT_BUTTON != 0) {
            let mouse_y = event.mouse.pos.y;
            let mouse_x = event.mouse.pos.x;

            // Check if click is within our bounds
            if mouse_x >= self.bounds.a.x
                && mouse_x < self.bounds.b.x
                && mouse_y >= self.bounds.a.y
                && mouse_y < self.bounds.b.y
            {
                let row = (mouse_y - self.bounds.a.y) as usize;
                let line_num = self.top_line + row + 1;
                self.toggle_breakpoint(line_num);
                event.clear();
            }
        }
    }

    fn state(&self) -> StateFlags {
        self.state
    }

    fn set_state(&mut self, state: StateFlags) {
        self.state = state;
    }

    fn get_palette(&self) -> Option<turbo_vision::core::palette::Palette> {
        None
    }

    fn get_owner_type(&self) -> OwnerType {
        self.owner_type
    }

    fn set_owner_type(&mut self, owner_type: OwnerType) {
        self.owner_type = owner_type;
    }
}
