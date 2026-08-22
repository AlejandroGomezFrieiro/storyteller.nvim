//! storyteller-tui — the keyboard-first cockpit for Storyteller projects.
//!
//! One grammar with the Neovim plugin (docs/interaction.md): j/k motion,
//! Tab pane cycling, o opens the focused scene in $EDITOR, q quits. Mouse
//! scroll/click are optional aliases. Structural editing stays in the
//! editor's projection buffers; this app is the glance-and-review surface.

mod project;
mod store;
mod theme;
mod ui;

use anyhow::Result;
use ratatui::{
    backend::CrosstermBackend,
    crossterm::{
        event::{self, Event, KeyCode, KeyEventKind, KeyModifiers, MouseEventKind},
        execute,
        terminal::{EnterAlternateScreen, LeaveAlternateScreen},
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
    let mut prj = project::load(&args.path)?;
    let mut store = store::Store::new(&args.path)?;

    let backend = CrosstermBackend::new(std::io::stdout());
    let mut terminal = Terminal::new(backend)?;
    execute!(
        stdout(),
        event::EnableMouseCapture,
        EnterAlternateScreen
    )?;
    terminal.hide_cursor()?;

    let mut tab = Tab::Dashboard;
    let mut list_state = ratatui::widgets::ListState::default();
    let mut hud_message: Option<String> = None;
    let mut quit = false;

    while !quit {
        let hud = ui::Hud { pending: store.pending(), message: hud_message.as_deref() };
        terminal.draw(|f| ui::render(f, &prj, &tab, &mut list_state, &theme, &hud))?;
        match event::read()? {
            Event::Key(key) if key.kind == KeyEventKind::Press => {
                match key.code {
                    KeyCode::Char('q') => quit = true,
                    KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                        quit = true
                    }
                    // Staged-edit verbs (docs/rework-plan.md Phase D):
                    KeyCode::Char('S') => match store.apply() {
                        Ok(n) => {
                            prj = project::load(&args.path)?;
                            hud_message = Some(format!("applied {n} change(s)"));
                        }
                        Err(e) => hud_message = Some(format!("apply failed: {e}")),
                    },
                    KeyCode::Char('u') | KeyCode::Esc => {
                        if store.pending() > 0 {
                            store.drop_staged();
                            hud_message = Some("staged changes dropped".to_string());
                        }
                    }
                    KeyCode::Char('R') => match project::load(&args.path) {
                        Ok(fresh) => {
                            prj = fresh;
                            store.refresh()?;
                            hud_message = Some("reloaded from disk".to_string());
                        }
                        Err(e) => hud_message = Some(format!("reload failed: {e}")),
                    },
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
                MouseEventKind::Down(_)
                    if tab != Tab::Dashboard => {
                        list_state.select(Some(mouse.row.saturating_sub(2) as usize));
                    }
                _ => {}
            },
            _ => {}
        }
    }

    execute!(
        stdout(),
        event::DisableMouseCapture,
        LeaveAlternateScreen
    )?;
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
