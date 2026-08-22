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
    let mut axes = load_axes(&args.path);
    let mut tl = ui::TlState::default();
    // Single-line prompt state: H/L absolute coordinates, `a` placements.
    let mut prompt: Option<(PromptKind, String)> = None;

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
        let axis_names = ui::axis_list(&prj, &axes);
        let axis_name = axis_names
            .get(tl.axis.min(axis_names.len() - 1))
            .cloned()
            .unwrap_or_else(|| "main".to_string());
        let tl_ctx = ui::TlCtx {
            axes: &axes,
            axis: &axis_name,
            story_order: tl.story_order,
            swimlane: tl.swimlane,
            staged: &store.staged,
        };
        let rows = ui::timeline_lanes(&prj, &tl_ctx);
        let prompt_msg: Option<String> = prompt.as_ref().map(|(kind, buf)| match kind {
            PromptKind::Coordinate => format!("coordinate: {buf}▏ (Enter stage · Esc cancel)"),
            PromptKind::Placement => {
                format!("placement axis@coord: {buf}▏ (Enter stage · Esc cancel)")
            }
        });
        let hud = ui::Hud {
            pending: store.pending(),
            message: hud_message.as_deref().or(prompt_msg.as_deref()),
        };
        terminal.draw(|f| {
            let ctx_ref = (tab == Tab::Timeline).then_some(&tl_ctx);
            ui::render(f, &prj, &tab, &mut list_state, &theme, &hud, ctx_ref)
        })?;
        match event::read()? {
            Event::Key(key) if key.kind == KeyEventKind::Press => {
                // An active prompt swallows keys first.
                if let Some((_kind, buf)) = prompt.as_mut() {
                    match key.code {
                        KeyCode::Esc => prompt = None,
                        KeyCode::Enter => {
                            let (kind, buf) = prompt.take().unwrap();
                            let text = buf.trim().to_string();
                            if text.is_empty() {
                                continue;
                            }
                            match kind {
                                PromptKind::Coordinate => {
                                    if let Some(sc) = focused_scene(&rows, &list_state) {
                                        store.stage(store::Op::SetCoord {
                                            scene: sc.clone(),
                                            coord: Some(text),
                                        });
                                        hud_message =
                                            Some("staged coordinate — S to apply".into());
                                    }
                                }
                                PromptKind::Placement => {
                                    if let Some((axis, coord)) = text.split_once('@') {
                                        if let Some(sc) = focused_scene(&rows, &list_state) {
                                            store.stage(store::Op::AddPlacement {
                                                scene: sc.clone(),
                                                axis: axis.trim().to_string(),
                                                coord: coord.trim().to_string(),
                                            });
                                            hud_message = Some(
                                                "staged placement — S to apply".into(),
                                            );
                                        }
                                    } else {
                                        hud_message =
                                            Some("expected axis@coord (e.g. Past@40)".into());
                                        continue;
                                    }
                                }
                            }
                        }
                        KeyCode::Backspace => {
                            buf.pop();
                        }
                        KeyCode::Char(c) => buf.push(c),
                        _ => {}
                    }
                    continue;
                }
                match key.code {
                    KeyCode::Char('q') => quit = true,
                    KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                        quit = true
                    }
                    // Staged-edit verbs (docs/rework-plan.md Phase D):
                    KeyCode::Char('S') => match store.apply() {
                        Ok(n) => {
                            prj = project::load(&args.path)?;
                            axes = load_axes(&args.path);
                            hud_message = Some(format!("applied {n} change(s)"));
                        }
                        Err(e) => hud_message = Some(format!("apply failed: {e}")),
                    },
                    KeyCode::Char('u') | KeyCode::Esc => {
                        if store.pending() > 0 {
                            store.drop_staged();
                            hud_message = Some("staged changes dropped".to_string());
                        } else {
                            tl.mark = None;
                        }
                    }
                    KeyCode::Char('R') => match project::load(&args.path) {
                        Ok(fresh) => {
                            prj = fresh;
                            axes = load_axes(&args.path);
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
                    // On the Timeline surface h/l retime (scoped verb);
                    // elsewhere they cycle tabs. Tab always cycles views.
                    KeyCode::Tab => tab = tab.next(),
                    KeyCode::Char('l') if tab != Tab::Timeline => tab = tab.next(),
                    KeyCode::Char('h') if tab != Tab::Timeline => {
                        tab = match tab {
                            Tab::Dashboard => Tab::Timeline,
                            Tab::Corkboard => Tab::Dashboard,
                            Tab::Timeline => Tab::Corkboard,
                        }
                    }
                    KeyCode::Char('1') => tab = Tab::Dashboard,
                    KeyCode::Char('2') => tab = Tab::Corkboard,
                    KeyCode::Char('3') => tab = Tab::Timeline,
                    // Timeline-surface verbs (docs/interaction.md, TUI keys):
                    // t axis · o order · w swimlanes · h/l retime · H/L
                    // absolute · d clear · s swap · a placement · x remove.
                    KeyCode::Char('t') if tab == Tab::Timeline => {
                        tl.axis = (tl.axis + 1) % axis_names.len();
                        tl.mark = None;
                        hud_message = Some(format!("axis: {}", axis_names[tl.axis]));
                    }
                    KeyCode::Char('o') if tab == Tab::Timeline => {
                        tl.story_order = !tl.story_order;
                        hud_message = Some(if tl.story_order {
                            "story order".to_string()
                        } else {
                            "reading order".to_string()
                        });
                    }
                    KeyCode::Char('w') if tab == Tab::Timeline => {
                        tl.swimlane = tl.swimlane.next();
                    }
                    KeyCode::Char('h') if tab == Tab::Timeline => {
                        tl_retime(&mut store, &mut hud_message, &rows, &list_state, &axis_name, &axes, -1);
                    }
                    KeyCode::Char('l') if tab == Tab::Timeline => {
                        tl_retime(&mut store, &mut hud_message, &rows, &list_state, &axis_name, &axes, 1);
                    }
                    KeyCode::Char('H') if tab == Tab::Timeline => {
                        if focused_scene(&rows, &list_state).is_some() {
                            prompt = Some((PromptKind::Coordinate, String::new()));
                        }
                    }
                    KeyCode::Char('L') if tab == Tab::Timeline => {
                        if focused_scene(&rows, &list_state).is_some() {
                            prompt = Some((PromptKind::Coordinate, String::new()));
                        }
                    }
                    KeyCode::Char('d') if tab == Tab::Timeline => {
                        if let Some(sc) = focused_scene(&rows, &list_state) {
                            store.stage(store::Op::SetCoord { scene: sc, coord: None });
                            hud_message = Some("staged unschedule — S to apply".into());
                        }
                    }
                    KeyCode::Char('s') if tab == Tab::Timeline => {
                        let sel = list_state.selected().unwrap_or(0);
                        match tl.mark {
                            None => {
                                tl.mark = Some(sel);
                                hud_message = Some("marked — move and press s to swap".into());
                            }
                            Some(from) => {
                                tl.mark = None;
                                tl_swap(&mut store, &mut hud_message, &rows, from, sel);
                            }
                        }
                    }
                    KeyCode::Char('a') if tab == Tab::Timeline => {
                        if focused_scene(&rows, &list_state).is_some() {
                            prompt = Some((PromptKind::Placement, String::new()));
                        }
                    }
                    KeyCode::Char('x') if tab == Tab::Timeline => {
                        if let Some((scene, secondary)) = focused_secondary(&rows, &list_state) {
                            let axis = secondary.0.clone();
                            store.stage(store::Op::RemovePlacement { scene, axis });
                            hud_message = Some("staged placement removal — S to apply".into());
                        } else {
                            hud_message =
                                Some("x removes a secondary (also:) placement row".into());
                        }
                    }
                    // Open: <CR> everywhere; `o` is the Timeline order toggle.
                    KeyCode::Enter => {
                        let scene = if tab == Tab::Timeline {
                            focused_scene(&rows, &list_state).map(|sc| {
                                (
                                    prj.root.join(&sc.file).to_string_lossy().to_string(),
                                    sc.line + 1,
                                )
                            })
                        } else {
                            prj.scenes
                                .get(list_state.selected().unwrap_or(0))
                                .map(|s| (s.file.to_string_lossy().to_string(), s.line))
                        };
                        if let Some((file, line)) = scene {
                            open_in_editor(std::path::Path::new(&file), line)?;
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

// Axis metadata via storyteller-core: single-sourced rank/order/projection
// semantics (docs/rework-plan.md decision 1).
fn load_axes(path: &std::path::Path) -> storyteller_core::axes::Axes {
    let (schema, _) = storyteller_core::schema::Schema::load(None, None);
    let index = storyteller_core::index::scan(path, &schema);
    storyteller_core::axes::Axes::collect(&index)
}

enum PromptKind {
    Coordinate,
    Placement,
}

// The selectable (non-header) row under the cursor.
fn focused_row<'a>(
    rows: &'a [(Option<String>, ui::TlRow<'a>)],
    selected: Option<usize>,
) -> Option<&'a ui::TlRow<'a>> {
    rows.iter()
        .filter(|(header, _)| header.is_none())
        .nth(selected.unwrap_or(0))
        .map(|(_, r)| r)
}

fn focused_scene(
    rows: &[(Option<String>, ui::TlRow<'_>)],
    list_state: &ratatui::widgets::ListState,
) -> Option<store::SceneRef> {
    focused_row(rows, list_state.selected()).map(|r| store::SceneRef {
        file: r.scene.file.to_string_lossy().to_string(),
        line: r.scene.line,
    })
}

fn focused_secondary(
    rows: &[(Option<String>, ui::TlRow<'_>)],
    list_state: &ratatui::widgets::ListState,
) -> Option<(store::SceneRef, (String, String))> {
    focused_row(rows, list_state.selected()).and_then(|r| {
        let secondary = r.secondary?;
        Some((
            store::SceneRef {
                file: r.scene.file.to_string_lossy().to_string(),
                line: r.scene.line,
            },
            secondary.clone(),
        ))
    })
}

// Stage a coordinate shift of ±delta on the focused placement: numeric
// coordinates shift; ordinal coordinates cycle their axis's order list.
fn tl_retime(
    store: &mut store::Store,
    hud_message: &mut Option<String>,
    rows: &[(Option<String>, ui::TlRow<'_>)],
    list_state: &ratatui::widgets::ListState,
    axis_name: &str,
    axes: &storyteller_core::axes::Axes,
    delta: i64,
) {
    let Some(r) = focused_row(rows, list_state.selected()) else { return };
    let order = axes.meta(axis_name).order;
    let next = match r.raw.parse::<i64>() {
        Ok(n) => (n + delta).to_string(),
        Err(_) => match order.iter().position(|o| o == &r.raw) {
            Some(p) => {
                let len = order.len() as i64;
                let nextp = ((p as i64 + delta).rem_euclid(len)) as usize;
                order[nextp].clone()
            }
            None => {
                *hud_message =
                    Some(format!("“{}” is not orderable on this axis", r.raw));
                return;
            }
        },
    };
    let scene = store::SceneRef {
        file: r.scene.file.to_string_lossy().to_string(),
        line: r.scene.line,
    };
    store.stage(store::Op::SetCoord { scene, coord: Some(next.clone()) });
    *hud_message = Some(format!("staged {} → {} — S to apply", r.raw, next));
}

fn tl_swap(
    store: &mut store::Store,
    hud_message: &mut Option<String>,
    rows: &[(Option<String>, ui::TlRow<'_>)],
    from: usize,
    to: usize,
) {
    let pick = |sel: usize| -> Option<(String, String, usize)> {
        focused_row(rows, Some(sel)).map(|r| {
            (
                r.scene.file.to_string_lossy().to_string(),
                r.raw.clone(),
                r.scene.line,
            )
        })
    };
    let (Some((file_a, coord_a, line_a)), Some((file_b, coord_b, line_b))) =
        (pick(from), pick(to))
    else {
        *hud_message = Some("swap needs two scheduled rows".into());
        return;
    };
    if file_a == file_b && line_a == line_b {
        *hud_message = Some("mark a different row to swap".into());
        return;
    }
    if coord_a.is_empty() || coord_b.is_empty() {
        *hud_message = Some("swap needs two scheduled rows".into());
        return;
    }
    store.stage(store::Op::SetCoord {
        scene: store::SceneRef { file: file_a.clone(), line: line_a },
        coord: Some(coord_b.clone()),
    });
    store.stage(store::Op::SetCoord {
        scene: store::SceneRef { file: file_b, line: line_b },
        coord: Some(coord_a.clone()),
    });
    *hud_message = Some(format!("staged swap {coord_a} ⇄ {coord_b} — S to apply"));
}
