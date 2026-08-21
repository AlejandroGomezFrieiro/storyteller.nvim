//! storyteller-tui — the keyboard-first cockpit for Storyteller projects.
//!
//! One grammar with the Neovim plugin (docs/interaction.md): j/k motion,
//! Tab pane cycling, o opens the focused scene in $EDITOR, q quits. Mouse
//! scroll/click are optional aliases. Structural editing stays in the
//! editor's projection buffers; this app is the glance-and-review surface.

mod project;
mod theme;
mod ui;

use anyhow::Result;
use ratatui::{
    backend::CrosstermBackend,
    crossterm::{
        event::{self, Event, KeyCode, KeyEventKind, KeyModifiers, MouseEventKind},
        execute,
    },
    Terminal,
};
use std::{io::stdout, path::PathBuf};
use ui::Tab;

struct Args {
    theme: Option<String>,
    background: Option<String>,
    path: PathBuf,
}

fn parse_args() -> Result<Args> {
    let mut args = std::env::args().skip(1);
    let mut theme = None;
    let mut background = None;
    let mut path = None;
    while let Some(arg) = args.next() {
        let mut value_for = |name: &str| -> Result<String> {
            args.next()
                .ok_or_else(|| anyhow::anyhow!("--{name} requires a value"))
        };
        match arg.as_str() {
            "--theme" => theme = Some(value_for("theme")?),
            "--background" => background = Some(value_for("background")?),
            "--glyphs" => {
                // Nerd tier ships later (§9); safe is the only table for now.
                let _ = value_for("glyphs")?;
            }
            "--help" | "-h" => {
                println!(
                    "storyteller-tui [--theme dark|light|midnight|forest|contrast] \
                     [--background dark|light] [path]"
                );
                std::process::exit(0);
            }
            other => {
                if path.is_none() && !other.starts_with('-') {
                    path = Some(PathBuf::from(other));
                }
            }
        }
    }
    Ok(Args {
        theme,
        background,
        path: path.unwrap_or_else(|| {
            std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
        }),
    })
}

fn main() -> Result<()> {
    let args = parse_args();
    let args = match args {
        Ok(a) => a,
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(2);
        }
    };
    let theme = std::sync::Arc::new(theme::Theme::load(
        args.theme.as_deref(),
        args.background.as_deref(),
    ));
    let prj = std::sync::Arc::new(project::load(&args.path)?);

    let backend = CrosstermBackend::new(std::io::stdout());
    let mut terminal = Terminal::new(backend)?;
    execute!(stdout(), event::EnableMouseCapture)?;
    terminal.hide_cursor()?;

    let mut tab = Tab::Dashboard;
    let mut list_state = ratatui::widgets::ListState::default();
    let mut quit = false;

    while !quit {
        terminal.draw(|f| ui::render(f, &prj, &tab, &mut list_state, &theme))?;
        match event::read()? {
            Event::Key(key) if key.kind == KeyEventKind::Press => {
                match key.code {
                    KeyCode::Char('q') => quit = true,
                    KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                        quit = true
                    }
                    KeyCode::Char('j') | KeyCode::Down => {
                        list_state.select_next();
                    }
                    KeyCode::Char('k') | KeyCode::Up => {
                        list_state.select_previous();
                    }
                    KeyCode::Tab | KeyCode::Char('l') => tab = tab.next(),
                    KeyCode::Char('h') => {
                        tab = match tab {
                            Tab::Dashboard => Tab::Timeline,
                            Tab::Corkboard => Tab::Dashboard,
                            Tab::Timeline => Tab::Corkboard,
                        }
                    }
                    KeyCode::Char('1') => tab = Tab::Dashboard,
                    KeyCode::Char('2') => tab = Tab::Corkboard,
                    KeyCode::Char('3') => tab = Tab::Timeline,
                    KeyCode::Char('o') => {
                        let scene = match tab {
                            Tab::Timeline => prj
                                .timeline()
                                .get(list_state.selected().unwrap_or(0))
                                .map(|s| (s.file.clone(), s.line)),
                            _ => prj
                                .scenes
                                .get(list_state.selected().unwrap_or(0))
                                .map(|s| (s.file.clone(), s.line)),
                        };
                        if let Some((file, line)) = scene {
                            open_in_editor(&file, line)?;
                        }
                    }
                    _ => {}
                }
            }
            // Optional mouse aliases (docs/interaction.md: never required).
            Event::Mouse(mouse) => match mouse.kind {
                MouseEventKind::ScrollDown => list_state.select_next(),
                MouseEventKind::ScrollUp => list_state.select_previous(),
                MouseEventKind::Down(_) => {
                    if tab != Tab::Dashboard {
                        list_state.select(Some(mouse.row.saturating_sub(2) as usize));
                    }
                }
                _ => {}
            },
            _ => {}
        }
    }

    execute!(stdout(), event::DisableMouseCapture)?;
    terminal.show_cursor()?;
    Ok(())
}

// Suspend the TUI, open the scene at its heading in $EDITOR, resume.
fn open_in_editor(file: &std::path::Path, line: usize) -> Result<()> {
    let editor = std::env::var("EDITOR").unwrap_or_else(|_| "vi".into());
    let editor: Vec<&str> = editor.split_whitespace().collect();
    if editor.is_empty() {
        return Ok(());
    }
    let mut cmd = std::process::Command::new(editor[0]);
    cmd.args(&editor[1..]);
    cmd.arg(format!("+{}", line));
    cmd.arg(file);
    cmd.status()?;
    Ok(())
}
