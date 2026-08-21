//! Theme module (docs/tui-visual-plan.md §4).
//!
//! One semantic palette, zero hardcoded colors: every view derives its styles
//! from these slots. Presets store truecolor hex; `termprofile` detects the
//! terminal's capability once at startup and adapts every color down
//! truecolor -> ANSI-256 -> ANSI-16 -> modifiers-only.

use ratatui::style::{Color, Modifier, Style};
use std::io::stdout;
use termprofile::{DetectorSettings, TermProfile};

pub const SLOT_COUNT: usize = 12;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Slot {
    Text,
    TextDim,
    Accent,
    Border,
    BorderActive,
    Surface,
    SelectionBg,
    Success,
    Warning,
    Error,
    Info,
    Draft,
}

pub const ALL_SLOTS: [Slot; SLOT_COUNT] = [
    Slot::Text,
    Slot::TextDim,
    Slot::Accent,
    Slot::Border,
    Slot::BorderActive,
    Slot::Surface,
    Slot::SelectionBg,
    Slot::Success,
    Slot::Warning,
    Slot::Error,
    Slot::Info,
    Slot::Draft,
];

type Hex = u32;

#[allow(dead_code)]
struct PresetDef {
    id: &'static str,
    dark: bool,
    slots: &'static [(Slot, Hex)],
}

const DARK: PresetDef = PresetDef {
    id: "dark",
    dark: true,
    slots: &[
        (Slot::Text, 0xd3d6de),
        (Slot::TextDim, 0x767c88),
        (Slot::Accent, 0x56b6c2),
        (Slot::Border, 0x3a3f4b),
        (Slot::BorderActive, 0x56b6c2),
        (Slot::Surface, 0x262a33),
        (Slot::SelectionBg, 0x2d3340),
        (Slot::Success, 0x98c379),
        (Slot::Warning, 0xe5c07b),
        (Slot::Error, 0xe06c75),
        (Slot::Info, 0x61afef),
        (Slot::Draft, 0xc678dd),
    ],
};

const LIGHT: PresetDef = PresetDef {
    id: "light",
    dark: false,
    slots: &[
        (Slot::Text, 0x3b3a36),
        (Slot::TextDim, 0x8a857c),
        (Slot::Accent, 0x0e7490),
        (Slot::Border, 0xd6d0c4),
        (Slot::BorderActive, 0x0e7490),
        (Slot::Surface, 0xf4efe6),
        (Slot::SelectionBg, 0xe9e2d4),
        (Slot::Success, 0x4a7c37),
        (Slot::Warning, 0xa16207),
        (Slot::Error, 0xb3403a),
        (Slot::Info, 0x2563a8),
        (Slot::Draft, 0x8a4fb0),
    ],
};

const MIDNIGHT: PresetDef = PresetDef {
    id: "midnight",
    dark: true,
    slots: &[
        (Slot::Text, 0xc0c8d8),
        (Slot::TextDim, 0x5c6478),
        (Slot::Accent, 0x7aa2f7),
        (Slot::Border, 0x33395a),
        (Slot::BorderActive, 0x7aa2f7),
        (Slot::Surface, 0x1b2036),
        (Slot::SelectionBg, 0x242b48),
        (Slot::Success, 0x9ece6a),
        (Slot::Warning, 0xe0af68),
        (Slot::Error, 0xf7768e),
        (Slot::Info, 0x7dcfff),
        (Slot::Draft, 0xbb9af7),
    ],
};

const FOREST: PresetDef = PresetDef {
    id: "forest",
    dark: true,
    slots: &[
        (Slot::Text, 0xcbd5bd),
        (Slot::TextDim, 0x7d887a),
        (Slot::Accent, 0xd19a66),
        (Slot::Border, 0x3a463a),
        (Slot::BorderActive, 0xd19a66),
        (Slot::Surface, 0x222b22),
        (Slot::SelectionBg, 0x2c382c),
        (Slot::Success, 0x8fb573),
        (Slot::Warning, 0xd7b56d),
        (Slot::Error, 0xcc6b60),
        (Slot::Info, 0x6ea3a0),
        (Slot::Draft, 0xa68bc9),
    ],
};

const PRESETS: [PresetDef; 4] = [DARK, LIGHT, MIDNIGHT, FOREST];

/// The `contrast` preset maps slots straight to ANSI names — it bypasses
/// conversion entirely and works everywhere.
const CONTRAST: [(Slot, Color); SLOT_COUNT] = [
    (Slot::Text, Color::White),
    (Slot::TextDim, Color::DarkGray),
    (Slot::Accent, Color::Cyan),
    (Slot::Border, Color::Gray),
    (Slot::BorderActive, Color::Cyan),
    (Slot::Surface, Color::Black),
    (Slot::SelectionBg, Color::DarkGray),
    (Slot::Success, Color::Green),
    (Slot::Warning, Color::Yellow),
    (Slot::Error, Color::Red),
    (Slot::Info, Color::Blue),
    (Slot::Draft, Color::Magenta),
];

// --- Glyphs ------------------------------------------------------------------

/// Two tiers per docs/tui-visual-plan.md §9: safe box-drawing/symbols by
/// default, plain ASCII under monochrome detection or `--glyphs ascii`.
#[derive(Clone, Copy)]
pub struct Glyphs {
    pub brand: &'static str,
    pub selection: &'static str,
    pub fill: &'static str,
    pub track: &'static str,
    pub draft: &'static str,
    pub outline: &'static str,
    pub done: &'static str,
    pub revision: &'static str,
    pub unused: &'static str,
}

pub const SAFE_GLYPHS: Glyphs = Glyphs {
    brand: "✦",
    selection: "▌",
    fill: "▇",
    track: "░",
    draft: "●",
    outline: "○",
    done: "✔",
    revision: "↻",
    unused: "×",
};

pub const ASCII_GLYPHS: Glyphs = Glyphs {
    brand: "*",
    selection: ">",
    fill: "#",
    track: "-",
    draft: "o",
    outline: "o",
    done: "x",
    revision: "~",
    unused: "x",
};

pub fn status_glyph(glyphs: &Glyphs, status: &str) -> &'static str {
    match status {
        "done" => glyphs.done,
        "revision" => glyphs.revision,
        "draft" => glyphs.draft,
        "unused" => glyphs.unused,
        _ => glyphs.outline,
    }
}

/// Status -> palette slot (§4.1 mapping table).
pub fn status_slot(status: &str) -> Slot {
    match status {
        "done" => Slot::Success,
        "revision" => Slot::Warning,
        "draft" => Slot::Draft,
        "unused" => Slot::Error,
        _ => Slot::Info,
    }
}

// --- Theme -------------------------------------------------------------------

#[allow(dead_code)]
pub struct Theme {
    colors: [Color; SLOT_COUNT],
    mono: bool,
    pub dark: bool,
    pub glyphs: Glyphs,
    pub preset_id: &'static str,
}

impl Theme {
    /// Deterministic constructor used by tests and presets tooling.
    pub fn from_profile(profile: TermProfile, preset_id: &str) -> Self {
        let mono = profile == TermProfile::NoColor;

        let preset_id: &'static str = match preset_id {
            "light" => "light",
            "midnight" => "midnight",
            "forest" => "forest",
            "contrast" => "contrast",
            _ => "dark",
        };

        let mut colors = [Color::Reset; SLOT_COUNT];
        if preset_id == "contrast" {
            for (slot, color) in CONTRAST {
                colors[slot as usize] = color;
            }
        } else {
            let def = PRESETS.iter().find(|p| p.id == preset_id).unwrap_or(&DARK);
            for slot in ALL_SLOTS {
                let hex = def
                    .slots
                    .iter()
                    .find(|(s, _)| *s == slot)
                    .map(|(_, hex)| *hex)
                    .unwrap_or(0xffffff);
                let rgb = Color::Rgb(
                    ((hex >> 16) & 0xff) as u8,
                    ((hex >> 8) & 0xff) as u8,
                    (hex & 0xff) as u8,
                );
                colors[slot as usize] =
                    profile.adapt_color(rgb).unwrap_or(Color::Reset);
            }
        }

        let ascii = mono || preset_id == "contrast";
        Theme {
            colors,
            mono,
            dark: !matches!(preset_id, "light"),
            glyphs: if ascii { ASCII_GLYPHS } else { SAFE_GLYPHS },
            preset_id,
        }
    }

    /// Resolve a theme from explicit flags and the environment.
    ///
    /// Order (§4.2): `--theme` wins; else `--background` picks dark/light;
    /// else `$NVIM` (inside nvim :terminal) defaults to dark; else dark.
    pub fn load(preset_flag: Option<&str>, background_flag: Option<&str>) -> Self {
        let profile = TermProfile::detect(&stdout(), DetectorSettings::default());
        let id = match preset_flag {
            Some("light") | Some("midnight") | Some("forest") | Some("contrast") => {
                preset_flag.unwrap()
            }
            _ => match background_flag {
                Some("light") => "light",
                _ => "dark",
            },
        };
        Self::from_profile(profile, id)
    }

    fn color(&self, slot: Slot) -> Color {
        self.colors[slot as usize]
    }

    /// Direct slot color access (tests, contrast assertions).
    #[allow(dead_code)]
    pub fn color_of(&self, slot: Slot) -> Color {
        self.color(slot)
    }

    /// Foreground style from an arbitrary slot (bar fills, status cells).
    pub fn slot_fg(&self, slot: Slot) -> Style {
        if self.mono {
            return Style::new().add_modifier(Modifier::BOLD);
        }
        Style::new().fg(self.color(slot))
    }

    fn styled(&self, slot: Slot, mods: Modifier) -> Style {
        self.slot_fg(slot).add_modifier(mods)
    }

    /// Primary prose/list content.
    #[allow(dead_code)]
    pub fn text(&self) -> Style {
        self.styled(Slot::Text, Modifier::empty())
    }

    pub fn text_bold(&self) -> Style {
        self.styled(Slot::Text, Modifier::BOLD)
    }

    /// Hints, secondary metadata.
    pub fn dim(&self) -> Style {
        self.styled(Slot::TextDim, Modifier::empty())
    }

    /// Active tab, focused border, selection edge, day numbers.
    pub fn accent(&self) -> Style {
        self.styled(Slot::Accent, Modifier::BOLD)
    }

    pub fn accent_plain(&self) -> Style {
        self.styled(Slot::Accent, Modifier::empty())
    }

    /// Inactive borders.
    pub fn border(&self) -> Style {
        self.styled(Slot::Border, Modifier::empty())
    }

    /// Card/panel background tint.
    #[allow(dead_code)]
    pub fn surface_bg(&self) -> Style {
        if self.mono {
            return Style::new();
        }
        Style::new().bg(self.color(Slot::Surface))
    }

    /// Selected-row background.
    pub fn selection_bg(&self) -> Style {
        if self.mono {
            return Style::new().add_modifier(Modifier::REVERSED);
        }
        Style::new().bg(self.color(Slot::SelectionBg))
    }

    /// Status styles share one slot each (§4.1): shape and hue agree.
    pub fn status(&self, status: &str) -> Style {
        self.styled(status_slot(status), Modifier::BOLD)
    }
}
