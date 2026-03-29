/// Watch window — displays variable names and values during debugging.

use turbo_vision::core::draw::DrawBuffer;
use turbo_vision::core::event::Event;
use turbo_vision::core::geometry::Rect;
use turbo_vision::core::palette::{Attr, TvColor};
use turbo_vision::core::state::StateFlags;
use turbo_vision::terminal::Terminal;
use turbo_vision::views::view::{write_line_to_terminal, OwnerType, View};

const NAME_ATTR: Attr = Attr::new(TvColor::White, TvColor::Blue);
const EQ_ATTR: Attr = Attr::new(TvColor::LightGray, TvColor::Blue);
const VAL_ATTR: Attr = Attr::new(TvColor::Yellow, TvColor::Blue);
const HEADER_ATTR: Attr = Attr::new(TvColor::Black, TvColor::Cyan);
const BG_ATTR: Attr = Attr::new(TvColor::LightGray, TvColor::Blue);

pub struct WatchPanel {
    bounds: Rect,
    state: StateFlags,
    variables: Vec<(String, String)>,
    owner_type: OwnerType,
}

impl WatchPanel {
    pub fn new(bounds: Rect) -> Self {
        Self {
            bounds,
            state: 0,
            variables: Vec::new(),
            owner_type: OwnerType::Window,
        }
    }

    pub fn set_variables(&mut self, vars: Vec<(String, String)>) {
        self.variables = vars;
    }

    pub fn update_variable(&mut self, name: &str, value: &str) {
        for (n, v) in &mut self.variables {
            if n == name {
                *v = value.to_string();
                return;
            }
        }
        self.variables.push((name.to_string(), value.to_string()));
    }

    pub fn clear(&mut self) {
        self.variables.clear();
    }
}

impl View for WatchPanel {
    fn bounds(&self) -> Rect {
        self.bounds
    }

    fn set_bounds(&mut self, bounds: Rect) {
        self.bounds = bounds;
    }

    fn draw(&mut self, terminal: &mut Terminal) {
        let width = self.bounds.width_clamped() as usize;
        let height = self.bounds.height_clamped() as usize;

        // Header row
        if height > 0 {
            let mut buf = DrawBuffer::new(width);
            buf.move_char(0, ' ', HEADER_ATTR, width);
            buf.move_str(1, " Watches ", HEADER_ATTR);
            write_line_to_terminal(terminal, self.bounds.a.x, self.bounds.a.y, &buf);
        }

        // Variable rows
        for row in 1..height {
            let mut buf = DrawBuffer::new(width);
            buf.move_char(0, ' ', BG_ATTR, width);

            let var_idx = row - 1;
            if var_idx < self.variables.len() {
                let (name, value) = &self.variables[var_idx];
                let eq = " = ";
                buf.move_str(1, name, NAME_ATTR);
                buf.move_str(1 + name.len(), eq, EQ_ATTR);
                buf.move_str(1 + name.len() + eq.len(), value, VAL_ATTR);
            }

            write_line_to_terminal(
                terminal,
                self.bounds.a.x,
                self.bounds.a.y + row as i16,
                &buf,
            );
        }
    }

    fn handle_event(&mut self, _event: &mut Event) {
        // Watch panel is read-only, no event handling
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
