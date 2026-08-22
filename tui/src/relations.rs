//! relations.rs — the Relations graph (docs/rework-plan.md Phase F).
//!
//! Port of `lua/storyteller/relations.lua` semantics: node/edge build over
//! reference cards, deterministic layouts only (ellipse circle up to 14
//! nodes, type columns above), nearest-node focus stepping. Rendering happens
//! through a ratatui Canvas; this module owns the data and geometry.

use crate::project::Card;

#[derive(Debug, Clone)]
pub struct Node {
    pub name: String,
    /// Reference-type folder id; "?" marks an unresolved ghost.
    pub rtype: String,
    pub mentions: usize,
    /// Card anchor for edits (None on ghosts).
    pub file: Option<String>,
    pub heading_line: usize,
}

#[derive(Debug, Clone)]
pub struct GraphEdge {
    pub from: usize,
    pub to: usize,
    pub kind: String,
}

#[derive(Debug, Clone, Default)]
pub struct Graph {
    pub nodes: Vec<Node>,
    pub edges: Vec<GraphEdge>,
    /// Normalized positions (0..1), parallel to `nodes`.
    pub positions: Vec<(f64, f64)>,
}

const CIRCLE_MAX: usize = 14;
/// Vertical squash of the focus ellipse (§6.4: the 0.62 rule).
const SQUASH: f64 = 0.62;

#[derive(Clone, Copy)]
pub enum Dir {
    Left,
    Right,
    #[allow(dead_code)]
    Up,
    #[allow(dead_code)]
    Down,
}

impl Graph {
    /// Build from cards; dangling edge targets become dim ghost nodes so the
    /// inspector can surface them without dropping information.
    pub fn build(cards: &[Card]) -> Graph {
        let mut graph = Graph::default();
        let mut idx_of: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
        let mut ghost_of: std::collections::HashMap<String, usize> =
            std::collections::HashMap::new();

        for card in cards {
            // Timeline cards participate through sync anchors, not the
            // character graph — their axis relationships live on the
            // Timeline surface (rework-plan §F).
            if card.rtype == "timelines" {
                continue;
            }
            let i = graph.nodes.len();
            graph.nodes.push(Node {
                name: card.name.clone(),
                rtype: card.rtype.clone(),
                mentions: card.mentions,
                file: Some(card.path.to_string_lossy().to_string()),
                heading_line: card.heading_line,
            });
            idx_of.insert(card.name.to_lowercase(), i);
        }
        for card in cards {
            if card.rtype == "timelines" {
                continue;
            }
            let from = idx_of[&card.name.to_lowercase()];
            for edge in &card.edges {
                if edge.kind == "syncs_with" {
                    continue;
                }
                let key = edge.to.to_lowercase();
                let to = match idx_of.get(&key) {
                    Some(i) => *i,
                    None => match ghost_of.get(&key) {
                        Some(i) => *i,
                        None => {
                            let i = graph.nodes.len();
                            graph.nodes.push(Node {
                                name: edge.to.clone(),
                                rtype: "?".into(),
                                mentions: 0,
                                file: None,
                                heading_line: 0,
                            });
                            ghost_of.insert(key.clone(), i);
                            i
                        }
                    },
                };
                graph.edges.push(GraphEdge {
                    from,
                    to,
                    kind: edge.kind.clone(),
                });
            }
        }
        graph.layout();
        graph
    }

    /// Deterministic layout: ellipse circle ≤ CIRCLE_MAX nodes, otherwise one
    /// column per reference type (types sorted, nodes sorted within).
    pub fn layout(&mut self) {
        let n = self.nodes.len();
        if n == 0 {
            return;
        }
        self.positions = vec![(0.5, 0.5); n];
        if n == 1 {
            self.positions[0] = (0.5, 0.5);
            return;
        }
        if n <= CIRCLE_MAX {
            for (i, pos) in self.positions.iter_mut().enumerate() {
                let angle =
                    (i as f64) / (n as f64) * std::f64::consts::TAU - std::f64::consts::FRAC_PI_2;
                *pos = (0.5 + 0.42 * angle.cos(), 0.5 + 0.42 * SQUASH * angle.sin());
            }
            return;
        }
        // Columns by type.
        let mut groups: Vec<(String, Vec<usize>)> = Vec::new();
        for (i, node) in self.nodes.iter().enumerate() {
            match groups.last_mut() {
                Some((t, list)) if *t == node.rtype => list.push(i),
                _ => groups.push((node.rtype.clone(), vec![i])),
            }
        }
        let cols = groups.len().max(1) as f64;
        for (c, (_, list)) in groups.iter().enumerate() {
            let x = 0.12 + 0.76 * (c as f64 + 0.5) / cols;
            let rows = list.len().max(1) as f64;
            for (r, ni) in list.iter().enumerate() {
                let y = 0.9 - 0.8 * (r as f64 + 0.5) / rows;
                self.positions[*ni] = (x, y);
            }
        }
    }

    /// Nearest node in a direction from the focused one (h/l walking).
    pub fn step_dir(&self, cur: usize, dir: Dir) -> usize {
        let (cx, cy) = self.positions[cur];
        let mut best: Option<(usize, f64)> = None;
        for (i, (x, y)) in self.positions.iter().enumerate() {
            if i == cur {
                continue;
            }
            let dx = x - cx;
            let dy = -(y - cy); // screen y is inverted
            let (along, across) = match dir {
                Dir::Left => (-dx, dy),
                Dir::Right => (dx, dy),
                Dir::Up => (dy, dx),
                Dir::Down => (-dy, dx),
            };
            if along > 0.02 && across.abs() <= along.abs() + 0.25 {
                let score = along + across.abs();
                if best.map(|(_, b)| score < b).unwrap_or(true) {
                    best = Some((i, score));
                }
            }
        }
        best.map(|(i, _)| i).unwrap_or(cur)
    }

    /// Focus order top-to-bottom, left-to-right (j/k walking).
    #[allow(dead_code)]
    pub fn order(&self) -> Vec<usize> {
        let mut idx: Vec<usize> = (0..self.nodes.len()).collect();
        idx.sort_by(|a, b| {
            let (ax, ay) = self.positions[*a];
            let (bx, by) = self.positions[*b];
            ay.partial_cmp(&by)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then(ax.partial_cmp(&bx).unwrap_or(std::cmp::Ordering::Equal))
        });
        idx
    }

    /// Edges touching a node, as (edge_index, outgoing?) sorted stably.
    pub fn edges_of(&self, node: usize) -> Vec<(usize, bool)> {
        let mut out: Vec<(usize, bool)> = Vec::new();
        for (ei, e) in self.edges.iter().enumerate() {
            if e.from == node {
                out.push((ei, true));
            } else if e.to == node {
                out.push((ei, false));
            }
        }
        out
    }

    pub fn filter_by(&self, query: &str) -> Vec<usize> {
        let q = query.to_lowercase();
        (0..self.nodes.len())
            .filter(|i| self.nodes[*i].name.to_lowercase().contains(&q))
            .collect()
    }
}

/// A built graph plus the visible-node subset (filter / orphan toggle).
pub struct RelView {
    pub graph: Graph,
    pub visible: Vec<usize>,
}

impl RelView {
    pub fn build(cards: &[Card], filter: Option<&str>, hide_orphans: bool) -> RelView {
        let graph = Graph::build(cards);
        let mut visible: Vec<usize> = match filter {
            Some(q) if !q.is_empty() => graph.filter_by(q),
            _ => (0..graph.nodes.len()).collect(),
        };
        if hide_orphans {
            visible.retain(|i| !graph.edges_of(*i).is_empty());
        }
        RelView { graph, visible }
    }

    /// Focus order top-to-bottom, left-to-right over visible nodes.
    pub fn order_visible(&self) -> Vec<usize> {
        let mut idx = self.visible.clone();
        idx.sort_by_key(|i| {
            let (x, y) = self.graph.positions[*i];
            (y.to_bits(), x.to_bits())
        });
        idx
    }

    pub fn clamp(&self, n: usize) -> usize {
        if self.visible.is_empty() {
            0
        } else {
            n.min(self.visible.len() - 1)
        }
    }
}
