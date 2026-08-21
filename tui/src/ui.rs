// storyteller-tui: rendering
// Read-only mirrors of the storyboards (docs/projections.md): the same
// information the Neovim projection buffers show, rendered as ratatui
// widgets. Editing stays in $EDITOR for now (docs/interaction.md).

use crate::project::Project;
use ratatui::{
    layout::{Constraint, Layout},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph},
    Frame,
};

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Tab {
    Dashboard,
    Corkboard,
    Timeline,
}

impl Tab {
    pub fn next(&self) -> Self {
        match self {
            Tab::Dashboard => Tab::Corkboard,
            Tab::Corkboard => Tab::Timeline,
            Tab::Timeline => Tab::Dashboard,
        }
    }

    pub fn title(&self) -> &'static str {
        match self {
            Tab::Dashboard => "dashboard",
            Tab::Corkboard => "corkboard",
            Tab::Timeline => "timeline",
        }
    }
}

fn status_color(status: Option<&str>) -> Color {
    match status.unwrap_or("outline") {
        "done" => Color::Green,
        "revision" => Color::Yellow,
        "draft" => Color::Magenta,
        "unused" => Color::Red,
        _ => Color::Blue,
    }
}

pub fn render(
    f: &mut Frame,
    prj: &Project,
    tab: &Tab,
    list_state: &mut ListState,
) {
    let [header, body] =
        Layout::vertical([Constraint::Length(1), Constraint::Min(0)]).areas(f.area());

    let tabs = ["dashboard", "corkboard", "timeline"]
        .iter()
        .map(|t| {
            if *t == tab.title() {
                Span::styled(format!(" [{t}] "), Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD))
            } else {
                Span::raw(format!(" {t} "))
            }
        })
        .collect::<Vec<_>>();
    f.render_widget(Line::from(tabs), header);

    match tab {
        Tab::Dashboard => dashboard(f, prj, body),
        Tab::Corkboard => corkboard(f, prj, body, list_state),
        Tab::Timeline => timeline(f, prj, body, list_state),
    }
}

fn dashboard(f: &mut Frame, prj: &Project, area: ratatui::layout::Rect) {
    let mut lines = vec![
        Line::from(Span::styled(
            format!(" ✦ {} ", prj.root.display()),
            Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD),
        )),
        Line::default(),
        Line::from(format!(
            " chapters: {}   scenes: {}   words: {}",
            prj.chapters.len(),
            prj.scenes.len(),
            prj.total_words
        )),
        Line::default(),
    ];
    let max_words = prj.chapters.iter().map(|c| c.words).max().unwrap_or(1).max(1);
    for ch in &prj.chapters {
        let bar_len = (ch.words * 20 / max_words).clamp(0, 20);
        lines.push(Line::from(vec![
            Span::raw(format!(" {:<28}", ch.title)),
            Span::styled("█".repeat(bar_len), Style::default().fg(Color::Blue)),
            Span::raw(format!(" {}", ch.words)),
        ]));
    }
    lines.push(Line::default());
    lines.push(Line::from(Span::styled(
        " j/k navigate · 1/2/3 or Tab switch view · o open in $EDITOR · q quit",
        Style::default().fg(Color::DarkGray),
    )));
    f.render_widget(Paragraph::new(lines), area);
}

fn corkboard(f: &mut Frame, prj: &Project, area: ratatui::layout::Rect, list_state: &mut ListState) {
    let items: Vec<ListItem> = prj
        .scenes
        .iter()
        .map(|sc| {
            ListItem::new(Line::from(vec![
                Span::styled(
                    format!(" {:<10}", sc.status.as_deref().unwrap_or("outline").to_uppercase()),
                    Style::default().fg(status_color(sc.status.as_deref())),
                ),
                Span::styled(format!("{:<30}", sc.title), Style::default().add_modifier(Modifier::BOLD)),
                Span::raw(format!(
                    "{:<18} {:>5} words",
                    sc.pov.as_deref().unwrap_or("—"),
                    sc.words
                )),
            ]))
        })
        .collect();
    let list = List::new(items)
        .block(Block::default().borders(Borders::ALL).title(" Corkboard "))
        .highlight_style(Style::default().bg(Color::DarkGray))
        .highlight_symbol("> ");
    f.render_stateful_widget(list, area, list_state);
}

fn timeline(f: &mut Frame, prj: &Project, area: ratatui::layout::Rect, list_state: &mut ListState) {
    let items: Vec<ListItem> = prj
        .timeline()
        .into_iter()
        .map(|sc| {
            let day = sc.day.map(|d| d.to_string()).unwrap_or_else(|| "·".into());
            ListItem::new(Line::from(vec![
                Span::styled(format!(" {:>4} ", day), Style::default().fg(Color::Cyan)),
                Span::styled(format!("{:<30}", sc.title), Style::default().add_modifier(Modifier::BOLD)),
                Span::raw(format!("{:<16}", sc.pov.as_deref().unwrap_or("—"))),
                Span::raw(format!("{} words", sc.words)),
            ]))
        })
        .collect();
    let list = List::new(items)
        .block(Block::default().borders(Borders::ALL).title(" Timeline · story time "))
        .highlight_style(Style::default().bg(Color::DarkGray))
        .highlight_symbol("> ");
    f.render_stateful_widget(list, area, list_state);
}
