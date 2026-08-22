// storyteller-tui: rendering
// Frame skeleton and view widgets (docs/tui-visual-plan.md §5–§6, visuals
// lane): one outer rounded block, a tab strip, a contextual footer key strip,
// and per-view polish driven entirely by theme slots — no hardcoded colors.

use crate::project::Project;
use crate::theme::{status_glyph, Slot, Theme};
use unicode_width::UnicodeWidthStr;
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
    Relations,
}

/// Transient chrome the frame renders from app state: staged-edit counters
/// and the last status message (docs/rework-plan.md Phase D).
#[derive(Default)]
pub struct Hud<'a> {
    pub pending: usize,
    pub message: Option<&'a str>,
}

const TAB_TITLES: [(&str, &str); 4] = [
    ("1", "Dashboard"),
    ("2", "Corkboard"),
    ("3", "Timeline"),
    ("4", "Relations"),
];

impl Tab {
    pub fn next(&self) -> Self {
        match self {
            Tab::Dashboard => Tab::Corkboard,
            Tab::Corkboard => Tab::Timeline,
            Tab::Timeline => Tab::Relations,
            Tab::Relations => Tab::Dashboard,
        }
    }

    fn index(&self) -> usize {
        match self {
            Tab::Dashboard => 0,
            Tab::Corkboard => 1,
            Tab::Timeline => 2,
            _ => 3,
        }
    }

    /// Footer binding table per tab (§5) so hints can never drift from keys.
    fn bindings(&self) -> Vec<(&'static str, &'static str)> {
        match self {
            Tab::Dashboard => vec![
                ("j/k", "chapters"),
                ("CR", "open"),
                ("Tab", "views"),
                ("R", "refresh"),
                ("q", "quit"),
            ],
            Tab::Corkboard => vec![
                ("j/k", "scenes"),
                ("CR", "open"),
                ("/", "filter"),
                ("Tab", "views"),
                ("R", "reload"),
                ("q", "quit"),
            ],
            Tab::Timeline => vec![
                ("j/k", "rows"),
                ("t", "axis"),
                ("o", "order"),
                ("w", "lanes"),
                ("h/l", "retime"),
                ("S/u", "staging"),
            ],
            Tab::Relations => vec![
                ("Tab", "panes"),
                ("j/k", "nodes/edges"),
                ("h/l", "walk"),
                ("a/e/x", "edges"),
                ("/", "filter"),
                ("R", "reload"),
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

#[allow(clippy::too_many_arguments)]
pub fn render(
    f: &mut Frame,
    prj: &Project,
    tab: &Tab,
    list_state: &mut ListState,
    theme: &Theme,
    hud: &Hud,
    tl_ctx: Option<&TlCtx<'_>>,
    rel: Option<(&RelState, &crate::relations::RelView)>,
) {
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
        Tab::Relations => {
            if let Some((state, view)) = rel {
                relations(f, prj, body, theme, class, state, view);
            }
        }
        Tab::Corkboard => corkboard(f, prj, body, list_state, theme, class),
        Tab::Timeline => {
            if let Some(ctx) = tl_ctx {
                timeline(f, prj, body, list_state, theme, class, ctx);
            }
        }
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

/// Swimlane grouping for the Timeline tab.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Swimlane {
    Off,
    Pov,
    Location,
    Chapter,
}

impl Swimlane {
    pub fn next(self) -> Self {
        match self {
            Swimlane::Off => Swimlane::Pov,
            Swimlane::Pov => Swimlane::Location,
            Swimlane::Location => Swimlane::Chapter,
            Swimlane::Chapter => Swimlane::Off,
        }
    }

}

/// Timeline tab state owned by the app (docs/rework-plan.md §E3).
pub struct TlState {
    /// Index into the axis list (main first, then declared axes sorted).
    pub axis: usize,
    /// Story order (chronological) vs reading order (manuscript).
    pub story_order: bool,
    pub swimlane: Swimlane,
    /// First marked row for the `s` swap verb.
    pub mark: Option<usize>,
}

impl Default for TlState {
    fn default() -> Self {
        TlState { axis: 0, story_order: true, swimlane: Swimlane::Off, mark: None }
    }
}

/// Everything the Timeline view and its key handlers need per frame.
pub struct TlCtx<'a> {
    pub axes: &'a storyteller_core::axes::Axes,
    pub axis: &'a str,
    pub story_order: bool,
    pub swimlane: Swimlane,
    /// Staged ops (to mark retimed rows ▒).
    pub staged: &'a [crate::store::Op],
}

/// One selectable Timeline row: a scene placement on the focused axis.
pub struct TlRow<'a> {
    pub scene: &'a crate::project::Scene,
    /// Some(placement) when this row is a secondary (`also:`) placement.
    pub secondary: Option<&'a (String, String)>,
    /// Coordinate as displayed.
    pub raw: String,
    /// Numeric/ordinal rank when the coordinate can order.
    pub rank: Option<i64>,
    /// Local diagnostics: (regression, overlap, sync-conflict).
    pub regression: bool,
    pub overlap: bool,
    pub sync_conflict: bool,
    pub staged: bool,
}

/// The axis list: implicit main first, then every declared axis sorted.
pub fn axis_list(prj: &Project, axes: &storyteller_core::axes::Axes) -> Vec<String> {
    let mut out = vec!["main".to_string()];
    for sc in &prj.scenes {
        if let Some(a) = &sc.axis {
            if !out.iter().any(|n| n.eq_ignore_ascii_case(a)) {
                out.push(a.clone());
            }
        }
    }
    let mut declared: Vec<String> = axes
        .by_name
        .values()
        .map(|m| m.name.clone())
        .filter(|n| !out.iter().any(|o| o.eq_ignore_ascii_case(n)))
        .collect();
    declared.sort();
    declared.dedup();
    out.extend(declared);
    out
}

fn scene_coord_raw(sc: &crate::project::Scene) -> Option<String> {
    sc.day.map(|d| d.to_string())
}

/// Build the selectable rows for one axis, ordered per the view mode, with
/// local regression/overlap/sync diagnostics and staged markers.
pub fn timeline_rows<'a>(prj: &'a Project, ctx: &TlCtx<'_>) -> Vec<TlRow<'a>> {
    let axis_meta = ctx.axes.meta(ctx.axis);
    let mut rows: Vec<TlRow<'a>> = Vec::new();
    for sc in &prj.scenes {
        // Primary placement.
        let on_axis = sc
            .axis
            .as_deref()
            .map(|a| a.eq_ignore_ascii_case(ctx.axis))
            .unwrap_or(ctx.axis.eq_ignore_ascii_case("main"));
        if on_axis {
            let raw = scene_coord_raw(sc);
            let rank = raw
                .as_deref()
                .and_then(|c| storyteller_core::axes::Coord::parse(c).rank(&axis_meta.order));
            rows.push(TlRow {
                scene: sc,
                secondary: None,
                raw: raw.clone().unwrap_or_else(|| "·".into()),
                rank,
                regression: false,
                overlap: false,
                sync_conflict: false,
                staged: false,
            });
        }
        // Secondary placements on this axis.
        for placement in &sc.also {
            if placement.0.eq_ignore_ascii_case(ctx.axis) {
                let rank = storyteller_core::axes::Coord::parse(&placement.1).rank(&axis_meta.order);
                rows.push(TlRow {
                    scene: sc,
                    secondary: Some(placement),
                    raw: placement.1.clone(),
                    rank,
                    regression: false,
                    overlap: false,
                    sync_conflict: false,
                    staged: false,
                });
            }
        }
    }

    // Intra-scene sync conflicts: primary projected onto each secondary must
    // land on it (exact anchors/origins only).
    for sc in &prj.scenes {
        let Some(primary) = scene_coord_raw(sc) else { continue };
        let from = sc.axis.as_deref().unwrap_or("main");
        for (bname, bcoord) in &sc.also {
            if let Some(projected) =
                storyteller_core::axes::project(ctx.axes, from, &storyteller_core::axes::Coord::parse(&primary), bname)
            {
                if projected.raw() != *bcoord {
                    for r in rows.iter_mut().filter(|r| r.scene.line == sc.line) {
                        r.sync_conflict = true;
                    }
                }
            }
        }
    }

    // Order.
    if ctx.story_order {
        rows.sort_by_key(|r| (r.rank.unwrap_or(i64::MAX), r.scene.line, r.secondary.is_some()));
    }

    // Local regression + overlap among linear-mode placements, in the
    // displayed order's story axis.
    if ctx.story_order {
        let mut prev: Option<i64> = None;
        let mut prev_line: Option<usize> = None;
        for r in rows.iter_mut() {
            let linear = r
                .scene
                .mode
                .as_deref()
                .map(|m| m.is_empty() || m == "linear")
                .unwrap_or(true);
            if let Some(rank) = r.rank {
                if linear {
                    if let (Some(p), Some(pl)) = (prev, prev_line) {
                        if rank < p && pl != r.scene.line {
                            r.regression = true;
                        }
                        if rank == p && pl != r.scene.line {
                            r.overlap = true;
                        }
                    }
                    prev = Some(rank);
                    prev_line = Some(r.scene.line);
                }
            }
        }
    }

    // Staged markers: any staged op touching this scene's file+line.
    for r in rows.iter_mut() {
        r.staged = ctx.staged.iter().any(|op| {
            let (file, line) = match op {
                crate::store::Op::SetCoord { scene, .. }
                | crate::store::Op::SetField { scene, .. }
                | crate::store::Op::AddPlacement { scene, .. }
                | crate::store::Op::RemovePlacement { scene, .. } => (&scene.file, scene.line),
                _ => return false,
            };
            file == &r.scene.file.to_string_lossy() && line == r.scene.line
        });
    }
    rows
}

/// Swimlane-grouped rows: (Some(header), empty) for lane titles, then rows.
pub fn timeline_lanes<'a>(
    prj: &'a Project,
    ctx: &TlCtx<'_>,
) -> Vec<(Option<String>, TlRow<'a>)> {
    let rows = timeline_rows(prj, ctx);
    if ctx.swimlane == Swimlane::Off {
        return rows.into_iter().map(|r| (None, r)).collect();
    }
    let key = |r: &TlRow| -> String {
        match ctx.swimlane {
            Swimlane::Pov => r.scene.pov.clone().unwrap_or_else(|| "—".into()),
            Swimlane::Location => r.scene.location.clone().unwrap_or_else(|| "—".into()),
            Swimlane::Chapter => r.scene.chapter.clone(),
            Swimlane::Off => String::new(),
        }
    };
    let mut groups: Vec<(String, Vec<TlRow>)> = Vec::new();
    for r in rows {
        let k = key(&r);
        match groups.last_mut() {
            Some((gk, list)) if *gk == k => list.push(r),
            _ => groups.push((k, vec![r])),
        }
    }
    let mut out = Vec::new();
    for (k, list) in groups {
        out.push((Some(k.clone()), TlRow::header(&list)));
        out.extend(list.into_iter().map(|r| (None, r)));
    }
    out
}

impl<'a> TlRow<'a> {
    fn header(from: &[TlRow<'a>]) -> Self {
        match from.first() {
            Some(r) => TlRow {
                scene: r.scene,
                secondary: r.secondary,
                raw: String::new(),
                rank: None,
                regression: false,
                overlap: false,
                sync_conflict: false,
                staged: false,
            },
            None => unreachable!("header from non-empty lane"),
        }
    }
}

fn timeline(
    f: &mut Frame,
    prj: &Project,
    area: Rect,
    list_state: &mut ListState,
    theme: &Theme,
    class: WidthClass,
    ctx: &TlCtx<'_>,
) {
    let lanes = timeline_lanes(prj, ctx);
    let mut items: Vec<ListItem> = Vec::new();
    for (header, r) in &lanes {
        if let Some(h) = header {
            items.push(ListItem::new(Line::from(vec![
                Span::styled(format!("▌ {h} "), theme.accent()),
                Span::styled("┈".repeat(6), theme.dim()),
            ])));
            continue;
        }
        let marker = if r.staged { "▒" } else { " " };
        let coord_span = if r.secondary.is_some() {
            Span::styled(format!(" {marker}{:>4}~", r.raw), theme.dim())
        } else if r.rank.is_some() {
            Span::styled(format!(" {marker}{:>4} ", r.raw), theme.accent_plain())
        } else {
            Span::styled(format!(" {marker}{:>4} ", "·"), theme.dim())
        };
        let mode_badge = r
            .scene
            .mode
            .as_deref()
            .filter(|m| !m.is_empty() && *m != "linear")
            .map(|_| Span::styled("~", theme.dim()));
        let title_style = if r.regression || r.overlap || r.sync_conflict {
            theme.slot_fg(Slot::Warning)
        } else {
            theme.text_bold()
        };
        let mut spans = vec![
            coord_span,
            Span::styled(fit(r.scene.title.as_str(), 30), title_style),
        ];
        if let Some(badge) = mode_badge {
            spans.push(badge);
        }
        if let Some((axis, _)) = r.secondary {
            spans.push(Span::styled(format!(" also:{axis}"), theme.dim()));
        }
        if class != WidthClass::Compact {
            spans.push(Span::styled(
                fit(r.scene.pov.as_deref().unwrap_or("—"), 16),
                theme.dim(),
            ));
            spans.push(Span::styled(
                format!("{:>5} w", words_compact(r.scene.words)),
                theme.dim(),
            ));
        }
        items.push(ListItem::new(Line::from(spans)));
    }
    let list = List::new(items)
        .block(Block::default())
        .highlight_symbol(format!("{} ", theme.glyphs.selection))
        .highlight_style(theme.selection_bg());
    f.render_stateful_widget(list, area, list_state);
}

// --- Relations ---------------------------------------------------------------

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Pane {
    Graph,
    Inspector,
}

/// Relations tab state owned by the app.
pub struct RelState {
    /// Focus position within the visible order (see `relations::RelView`).
    pub node: usize,
    pub pane: Pane,
    /// Selected edge within the focused node's inspector list.
    pub edge: usize,
    pub filter: Option<String>,
    pub hide_orphans: bool,
}

impl Default for RelState {
    fn default() -> Self {
        RelState { node: 0, pane: Pane::Graph, edge: 0, filter: None, hide_orphans: false }
    }
}

fn relations(
    f: &mut Frame,
    _prj: &Project,
    area: Rect,
    theme: &Theme,
    class: WidthClass,
    rel: &RelState,
    view: &crate::relations::RelView,
) {
    let graph = &view.graph;
    let order = view.order_visible();
    if order.is_empty() {
        f.render_widget(
            Line::from(Span::styled("no cards match — / to clear the filter", theme.dim())),
            centered(area),
        );
        return;
    }
    let node_i = order[rel.node.min(order.len() - 1)];

    // Two panes at comfortable widths; graph-only when compact.
    let (graph_area, inspector_area) = if class == WidthClass::Compact || area.width < 80 {
        (area, None)
    } else {
        let [left, right] =
            Layout::horizontal([Constraint::Percentage(62), Constraint::Min(24)]).areas(area);
        (left, Some(right))
    };

    let canvas = ratatui::widgets::canvas::Canvas::default()
        .x_bounds([0.0, 1.0])
        .y_bounds([0.0, 1.0])
        .paint(|ctx| {
            for e in &graph.edges {
                let (x0, y0) = graph.positions[e.from];
                let (x1, y1) = graph.positions[e.to];
                ctx.draw(&ratatui::widgets::canvas::Line {
                    x1,
                    y1,
                    x2: x0,
                    y2: y0,
                    color: theme.border().fg.unwrap_or(ratatui::style::Color::DarkGray),
                });
            }
            for (i, ni) in order.iter().enumerate() {
                let node = &graph.nodes[*ni];
                let (x, y) = graph.positions[*ni];
                let focused = *ni == node_i;
                ctx.draw(&ratatui::widgets::canvas::Points {
                    coords: &[(x, y)],
                    color: if focused {
                        theme.accent().fg.unwrap_or(ratatui::style::Color::Yellow)
                    } else if node.rtype == "?" {
                        ratatui::style::Color::DarkGray
                    } else {
                        theme.text().fg.unwrap_or(ratatui::style::Color::Gray)
                    },
                });
                use unicode_width::UnicodeWidthStr;
                let label = if node.rtype == "?" {
                    format!("{}?", node.name)
                } else {
                    node.name.clone()
                };
                let _ = i;
                ctx.print(
                    x - (label.width() as f64) * 0.004,
                    y + 0.02,
                    Span::styled(label, if focused { theme.accent_plain() } else { theme.dim() }),
                );
            }
        });
    f.render_widget(canvas, graph_area);

    if let Some(inspector) = inspector_area {
        let node = &graph.nodes[node_i];
        let mut lines = vec![
            Line::from(vec![
                Span::styled(format!("◆ {} ", node.name), theme.text_bold()),
                Span::styled(format!("· {}", node.rtype), theme.dim()),
            ]),
            Line::from(Span::styled(format!("{} mentions", node.mentions), theme.dim())),
        ];
        let edges_of = graph.edges_of(node_i);
        lines.push(Line::from(Span::styled("edges:", theme.dim())));
        if edges_of.is_empty() {
            lines.push(Line::from(Span::styled("  (none)", theme.dim())));
        }
        for (i, (ei, outgoing)) in edges_of.iter().enumerate() {
            let e = &graph.edges[*ei];
            let other = if *outgoing { e.to } else { e.from };
            let mut spans = vec![Span::raw(format!(
                "  {} {} {:?} ",
                if rel.edge == i { "▸" } else { " " },
                e.kind,
                graph.nodes[other].name
            ))];
            if graph.nodes[other].rtype == "?" {
                spans.push(Span::styled("(unresolved)", theme.slot_fg(Slot::Warning)));
            }
            lines.push(Line::from(spans));
        }
        lines.push(Line::from(Span::styled(
            "a add · e rename · x delete · Tab back",
            theme.dim(),
        )));
        f.render_widget(Paragraph::new(lines), inspector);
    }
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
                    ..Default::default()
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
                    ..Default::default()
                },
            ],
            tracks: Vec::new(),
            cards: Vec::new(),
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
        let axes = storyteller_core::axes::Axes {
            by_name: std::collections::HashMap::new(),
        };
        let ctx = TlCtx {
            axes: &axes,
            axis: "main",
            story_order: true,
            swimlane: Swimlane::Off,
            staged: &[],
        };
        terminal
            .draw(|f| {
                let mut tl_ctx = Some(&ctx);
                if *tab != Tab::Timeline {
                    tl_ctx = None;
                }
                render(f, prj, tab, &mut ls, theme, &Hud::default(), tl_ctx, None)
            })
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
                    Tab::Relations => {}
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
            .draw(|f| render(f, &prj, &Tab::Timeline, &mut ls, &theme, &hud, None, None))
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
            .draw(|f| render(f, &prj, &Tab::Timeline, &mut ls, &theme, &hud, None, None))
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
