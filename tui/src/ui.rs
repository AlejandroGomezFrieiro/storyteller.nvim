// storyteller-tui: rendering
// Frame skeleton and view widgets (docs/tui-visual-plan.md §5–§6, visuals
// lane): one outer rounded block, a tab strip, a contextual footer key strip,
// and per-view polish driven entirely by theme slots — no hardcoded colors.

use crate::project::Project;
use crate::theme::{status_glyph, Slot, Theme};
use ratatui::{
    layout::{Constraint, Layout, Rect},
    text::{Line, Span},
    widgets::{Block, BorderType, List, ListItem, ListState, Paragraph, Tabs},
    Frame,
};

#[derive(Clone, Copy, PartialEq)]
pub enum Tab {
    Dashboard,
    Corkboard,
    Timeline,
}

/// Transient chrome the frame renders from app state: staged-edit counters
/// and the last status message (docs/rework-plan.md Phase D).
#[derive(Default)]
pub struct Hud<'a> {
    pub pending: usize,
    pub message: Option<&'a str>,
}

const TAB_TITLES: [(&str, &str); 3] =
    [("1", "Dashboard"), ("2", "Corkboard"), ("3", "Timeline")];

impl Tab {
    pub fn next(&self) -> Self {
        match self {
            Tab::Dashboard => Tab::Corkboard,
            Tab::Corkboard => Tab::Timeline,
            Tab::Timeline => Tab::Dashboard,
        }
    }

    fn index(&self) -> usize {
        match self {
            Tab::Dashboard => 0,
            Tab::Corkboard => 1,
            _ => 2,
        }
    }

    /// Footer binding table per tab (§5) so hints can never drift from keys.
    fn bindings(&self) -> Vec<(&'static str, &'static str)> {
        match self {
            Tab::Dashboard => vec![
                ("j/k", "chapters"),
                ("o", "open"),
                ("Tab", "views"),
                ("R", "refresh"),
                ("q", "quit"),
            ],
            Tab::Corkboard => vec![
                ("j/k", "scenes"),
                ("o", "open"),
                ("/", "filter"),
                ("Tab", "views"),
                ("R", "reload"),
                ("q", "quit"),
            ],
            Tab::Timeline => vec![
                ("j/k", "rows"),
                ("o", "open"),
                ("/", "filter"),
                ("Tab", "views"),
                ("R", "reload"),
                ("q", "quit"),
            ],
        }
    }
}

#[derive(Clone, Copy, PartialEq)]
enum WidthClass {
    Compact,
    Standard,
}

fn width_class(width: u16) -> WidthClass {
    if width < 50 {
        WidthClass::Compact
    } else {
        WidthClass::Standard
    }
}

fn project_name(prj: &Project) -> String {
    prj.root
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| prj.root.display().to_string())
}

/// Truncate to `width` display columns, appending an ellipsis when cut.
fn fit(text: &str, width: usize) -> String {
    use unicode_width::UnicodeWidthStr;
    let w = text.width();
    if w <= width {
        return format!("{text:w$}");
    }
    let mut out = String::new();
    let mut used = 0;
    for ch in text.chars() {
        let cw = unicode_width::UnicodeWidthChar::width(ch).unwrap_or(1);
        if used + cw > width.saturating_sub(1) {
            break;
        }
        out.push(ch);
        used += cw;
    }
    out.push('…');
    out
}

/// Compact word count: `1.1k` above 999 (§6.2).
fn words_compact(words: usize) -> String {
    if words > 999 {
        format!("{:.1}k", words as f64 / 1000.0)
    } else {
        format!("{words}")
    }
}

pub fn render(f: &mut Frame, prj: &Project, tab: &Tab, list_state: &mut ListState, theme: &Theme, hud: &Hud) {
    let area = f.area();
    let class = width_class(area.width);

    let block = Block::default()
        .border_type(BorderType::Rounded)
        .border_style(theme.border())
        .title(Line::from(vec![
            Span::styled(
                format!(" {} ", theme.glyphs.brand),
                theme.accent(),
            ),
            Span::styled("storyteller", theme.text_bold()),
            Span::styled(format!(" · {} · {} scenes", project_name(prj), prj.scenes.len()), theme.dim()),
        ]));
    let inner = block.inner(area);
    f.render_widget(block, area);

    let [tabs_row, body, footer] =
        Layout::vertical([Constraint::Length(1), Constraint::Min(0), Constraint::Length(1)])
            .areas(inner);

    let tabs = Tabs::new(TAB_TITLES.iter().map(|(n, t)| format!("{n} {t}")))
        .select(tab.index())
        .highlight_style(theme.accent())
        .style(theme.dim());
    f.render_widget(tabs, tabs_row);

    match tab {
        Tab::Dashboard => dashboard(f, prj, body, theme, class),
        Tab::Corkboard => corkboard(f, prj, body, list_state, theme, class),
        Tab::Timeline => timeline(f, prj, body, list_state, theme, class),
    }

    // Footer: key strip on the left; status message / staging segment on the
    // right. Pending edits render in the warning slot until applied.
    let mut spans = Vec::new();
    for (key, desc) in tab.bindings() {
        if !spans.is_empty() {
            spans.push(Span::styled("  ", theme.dim()));
        }
        spans.push(Span::styled(key.to_string(), theme.accent()));
        if class != WidthClass::Compact {
            spans.push(Span::styled(format!(" {desc}"), theme.dim()));
        }
    }

    let mut right: Vec<Span> = Vec::new();
    if let Some(msg) = hud.message {
        right.push(Span::styled(msg.to_string(), theme.accent_plain()));
    }
    if hud.pending > 0 {
        if !right.is_empty() {
            right.push(Span::styled(" · ", theme.dim()));
        }
        right.push(Span::styled(
            format!("{} pending", hud.pending),
            theme.slot_fg(Slot::Warning),
        ));
        right.push(Span::styled(" · ", theme.dim()));
        right.push(Span::styled("S apply", theme.slot_fg(Slot::Warning)));
    }

    if right.is_empty() {
        f.render_widget(Line::from(spans), footer);
    } else {
        use unicode_width::UnicodeWidthStr;
        let used_right: usize = right.iter().map(|s| s.content.width()).sum();
        let used_left: usize = spans.iter().map(|s| s.content.width()).sum();
        let gap = (footer.width as usize).saturating_sub(used_left + used_right + 1);
        if gap >= 2 {
            spans.push(Span::raw(" ".repeat(gap)));
            spans.extend(right);
            f.render_widget(Line::from(spans), footer);
        } else {
            // Too narrow for both: staging state wins.
            f.render_widget(Line::from(right), footer);
        }
    }
}

// --- Dashboard ---------------------------------------------------------------

fn dashboard(
    f: &mut Frame,
    prj: &Project,
    area: Rect,
    theme: &Theme,
    class: WidthClass,
) {
    if prj.chapters.is_empty() {
        let msg = Line::from(vec![
            Span::styled(format!("{} ", theme.glyphs.brand), theme.accent_plain()),
            Span::styled("empty project — write your first chapter", theme.dim()),
        ]);
        f.render_widget(msg, centered(area));
        return;
    }

    let totals = Line::from(vec![
        Span::styled(
            format!(
                "{} chapters · {} scenes",
                prj.chapters.len(),
                prj.scenes.len()
            ),
            theme.dim(),
        ),
        Span::raw("  "),
        Span::styled(
            format!("{} w total", words_compact(prj.total_words)),
            theme.text_bold(),
        ),
    ]);
    let title = Line::from(Span::styled(project_name(prj), theme.text_bold()));
    f.render_widget(
        Paragraph::new(vec![title, totals]),
        Rect { height: 2.min(area.height), ..area },
    );
    if area.height <= 2 {
        return;
    }

    let max_words = prj.chapters.iter().map(|c| c.words).max().unwrap_or(1).max(1);
    let bar_width = match class {
        WidthClass::Compact => 10,
        WidthClass::Standard => 22,
    };
    let mut lines = Vec::new();
    for ch in &prj.chapters {
        let over = matches!(ch.target, Some(t) if ch.words > t as usize);
        let ratio = match ch.target {
            Some(t) if t > 0 => (ch.words as f64 / t as f64).min(1.0),
            _ => ch.words as f64 / max_words as f64,
        };
        let filled = (ratio * bar_width as f64).round() as usize;
        let fill_style = if over {
            theme.slot_fg(Slot::Warning)
        } else {
            theme.slot_fg(Slot::Accent)
        };
        let counts = match ch.target {
            Some(t) => format!("{}/{}", words_compact(ch.words), words_compact(t as usize)),
            None => format!("{} w", words_compact(ch.words)),
        };
        lines.push(Line::from(vec![
            Span::styled(fit(&format!(" {}", ch.title), 26), theme.text_bold()),
            Span::styled(theme.glyphs.fill.repeat(filled), fill_style),
            Span::styled(theme.glyphs.track.repeat(bar_width - filled), theme.dim()),
            Span::styled(format!(" {counts}"), theme.dim()),
        ]));
    }
    f.render_widget(
        Paragraph::new(lines),
        Rect {
            y: area.y + 2,
            height: area.height - 2,
            ..area
        },
    );
}

fn centered(area: Rect) -> Rect {
    Rect {
        x: area.x + 2,
        y: area.y + area.height / 2,
        width: area.width.saturating_sub(4),
        height: 1,
    }
}

// --- Corkboard ---------------------------------------------------------------

fn corkboard(
    f: &mut Frame,
    prj: &Project,
    area: Rect,
    list_state: &mut ListState,
    theme: &Theme,
    class: WidthClass,
) {
    let items: Vec<ListItem> = prj
        .scenes
        .iter()
        .map(|sc| {
            let status = sc.status.as_deref().unwrap_or("outline");
            let glyph = status_glyph(&theme.glyphs, status);
            let mut spans = vec![
                Span::raw(" "),
                Span::styled(glyph.to_string(), theme.status(status)),
                Span::styled(format!(" {status:<9}"), theme.status(status)),
                Span::styled(fit(sc.title.as_str(), 30), theme.text_bold()),
            ];
            if class != WidthClass::Compact {
                spans.push(Span::styled(
                    fit(sc.pov.as_deref().unwrap_or("—"), 16),
                    theme.dim(),
                ));
                spans.push(Span::styled(
                    format!("{:>5} w", words_compact(sc.words)),
                    theme.dim(),
                ));
            }
            ListItem::new(Line::from(spans))
        })
        .collect();
    let list = List::new(items)
        .block(Block::default())
        .highlight_symbol(format!("{} ", theme.glyphs.selection))
        .highlight_style(theme.selection_bg());
    f.render_stateful_widget(list, area, list_state);
}

// --- Timeline ----------------------------------------------------------------

fn timeline(
    f: &mut Frame,
    prj: &Project,
    area: Rect,
    list_state: &mut ListState,
    theme: &Theme,
    class: WidthClass,
) {
    let items: Vec<ListItem> = prj
        .timeline()
        .into_iter()
        .map(|sc| {
            let day = sc.day.map(|d| d.to_string()).unwrap_or_else(|| "·".into());
            let day_span = if sc.day.is_some() {
                Span::styled(format!(" {:>4} ", day), theme.accent_plain())
            } else {
                Span::styled(format!(" {:>4} ", day), theme.dim())
            };
            let mut spans = vec![day_span, Span::styled(fit(sc.title.as_str(), 30), theme.text_bold())];
            if class != WidthClass::Compact {
                spans.push(Span::styled(
                    fit(sc.pov.as_deref().unwrap_or("—"), 16),
                    theme.dim(),
                ));
                spans.push(Span::styled(format!("{:>5} w", words_compact(sc.words)), theme.dim()));
            }
            ListItem::new(Line::from(spans))
        })
        .collect();
    let list = List::new(items)
        .block(Block::default())
        .highlight_symbol(format!("{} ", theme.glyphs.selection))
        .highlight_style(theme.selection_bg());
    f.render_stateful_widget(list, area, list_state);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::theme::{ASCII_GLYPHS, SAFE_GLYPHS};
    use std::path::PathBuf;
    use ratatui::{backend::TestBackend, Terminal};
    use termprofile::TermProfile;

    fn fixture() -> Project {
        Project {
            root: PathBuf::from("/tmp/odyssey"),
            chapters: vec![crate::project::Chapter {
                title: "The Harbor".into(),
                file: PathBuf::from("01.md"),
                words: 6120,
                target: Some(8000),
                status: None,
            }],
            scenes: vec![
                crate::project::Scene {
                    title: "The warning".into(),
                    chapter: "The Harbor".into(),
                    file: PathBuf::from("01.md"),
                    line: 3,
                    status: Some("draft".into()),
                    pov: Some("Odysseus".into()),
                    location: None,
                    day: Some(1),
                    words: 412,
                },
                crate::project::Scene {
                    title: "Storm lands".into(),
                    chapter: "The Harbor".into(),
                    file: PathBuf::from("01.md"),
                    line: 20,
                    status: Some("done".into()),
                    pov: None,
                    location: None,
                    day: None,
                    words: 1101,
                },
            ],
            total_words: 6120,
        }
    }

    fn frame_text(
        width: u16,
        height: u16,
        tab: &Tab,
        prj: &Project,
        theme: &Theme,
    ) -> String {
        let backend = TestBackend::new(width, height);
        let mut terminal = Terminal::new(backend).unwrap();
        let mut ls = ListState::default();
        terminal
            .draw(|f| render(f, prj, tab, &mut ls, theme, &Hud::default()))
            .unwrap();
        terminal
            .backend()
            .buffer()
            .content()
            .iter()
            .map(|cell| cell.symbol())
            .collect::<Vec<_>>()
            .join("")
    }

    #[test]
    fn tabs_render_at_breakpoint_widths() {
        let prj = fixture();
        for width in [40u16, 60, 100] {
            for tab in [Tab::Dashboard, Tab::Corkboard, Tab::Timeline] {
                let theme = Theme::from_profile(TermProfile::TrueColor, "dark");
                let text = frame_text(width, 24, &tab, &prj, &theme);
                assert!(text.contains("storyteller"), "brand at {width}");
                assert!(
                    text.contains("Dashboard") && text.contains("Corkboard"),
                    "tab strip present at {width}"
                );
                match tab {
                    Tab::Dashboard => assert!(
                        text.contains("The Harbor"),
                        "chapter rows at {width}"
                    ),
                    Tab::Corkboard => assert!(
                        text.contains("The warning"),
                        "scene rows at {width}"
                    ),
                    Tab::Timeline => {
                        assert!(text.contains("The warning"), "timeline rows at {width}")
                    }
                }
            }
        }
    }

    #[test]
    fn footer_shows_descriptions_when_room_allows() {
        let prj = fixture();
        let theme = Theme::from_profile(TermProfile::TrueColor, "dark");
        let wide = frame_text(100, 24, &Tab::Dashboard, &prj, &theme);
        assert!(wide.contains("chapters"), "footer descriptions at 100 cols");
        assert!(wide.contains('q'), "footer keys at 100 cols");
        let narrow = frame_text(40, 24, &Tab::Dashboard, &prj, &theme);
        assert!(!narrow.contains("views"), "compact footer hides descriptions");
        assert!(narrow.contains('q'), "compact footer keeps keys");
    }

    #[test]
    fn footer_shows_pending_staging_segment() {
        let prj = fixture();
        let theme = Theme::from_profile(TermProfile::TrueColor, "dark");
        let backend = TestBackend::new(100, 24);
        let mut terminal = Terminal::new(backend).unwrap();
        let mut ls = ListState::default();
        let hud = Hud { pending: 2, message: None };
        terminal
            .draw(|f| render(f, &prj, &Tab::Timeline, &mut ls, &theme, &hud))
            .unwrap();
        let text: String = terminal
            .backend()
            .buffer()
            .content()
            .iter()
            .map(|cell| cell.symbol())
            .collect();
        assert!(text.contains("2 pending"), "pending count on the footer");
        assert!(text.contains("S apply"), "apply hint while staging");

        // A status message renders instead when present.
        let hud = Hud { pending: 0, message: Some("applied 3 change(s)") };
        let backend = TestBackend::new(100, 24);
        let mut terminal = Terminal::new(backend).unwrap();
        terminal
            .draw(|f| render(f, &prj, &Tab::Timeline, &mut ls, &theme, &hud))
            .unwrap();
        let text: String = terminal
            .backend()
            .buffer()
            .content()
            .iter()
            .map(|cell| cell.symbol())
            .collect();
        assert!(text.contains("applied 3"), "status message visible");
    }

    #[test]
    fn status_glyph_mapping_covers_schema_statuses() {
        let table = [
            ("draft", SAFE_GLYPHS.draft),
            ("outline", SAFE_GLYPHS.outline),
            ("done", SAFE_GLYPHS.done),
            ("revision", SAFE_GLYPHS.revision),
            ("unused", SAFE_GLYPHS.unused),
        ];
        for (status, expected) in table {
            assert_eq!(status_glyph(&SAFE_GLYPHS, status), expected);
        }
    }

    #[test]
    fn contrast_preset_degrades_glyphs_and_colors() {
        let theme = Theme::from_profile(TermProfile::Ansi16, "contrast");
        assert_eq!(theme.glyphs.brand, ASCII_GLYPHS.brand);
        // ANSI-named colors survive as named variants.
        assert_eq!(theme.color_of(Slot::Accent), ratatui::style::Color::Cyan);
    }

    #[test]
    fn degradation_keeps_structure_identical() {
        let prj = fixture();
        let truecolor = frame_text(100, 24, &Tab::Corkboard, &prj, &Theme::from_profile(TermProfile::TrueColor, "dark"));
        let ansi16 = frame_text(100, 24, &Tab::Corkboard, &prj, &Theme::from_profile(TermProfile::Ansi16, "dark"));
        assert_eq!(truecolor, ansi16, "same project renders identical text under any capability");
    }
}
