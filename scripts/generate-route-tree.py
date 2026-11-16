#!/usr/bin/env python3
"""Generate an interactive HTML browser for Departure's routing map dump.

At launch, Debug builds log the adopted routing map as a box-drawn tree:

    [map] ✓ adopted routing map owner=17E4F428
    root
    ├─ global
    │  └─ cover.fade LockRoute → destination #1
    ├─ sheet SettingsRoute → destination #2
    │  └─ push ProfileRoute → destination #3 [declaration conflict]
    └─ branches
       ├─ branch #1 (Tab)
       │  └─ push DetailRoute → destination #4
       └─ branch #2 (Tab)

Routes under `global` can be presented from anywhere, so they are listed once
instead of under every route.

Feed this script a console log (file or stdin) containing that dump. It parses
the last dump in the input and writes one self-contained HTML file: no network,
no dependencies, Python 3.9 stdlib only.

Console prefixes (timestamps, subsystem tags) are tolerated: the tree's column
is taken from the `root` line and stripped from every line that follows.

Usage:

    generate-route-tree.py console.log     # from a saved Xcode console log
    generate-route-tree.py --clipboard     # from a dump copied out of the console
    pbpaste | generate-route-tree.py       # or any finite input on stdin

Writes $TMPDIR/departure-route-map.html (override with -o) and opens it.
"""
import argparse
import html
import json
import os
import re
import subprocess
import sys
import tempfile

MARKER = "adopted routing map"
BRANCH_GLYPHS = ("├─ ", "└─ ")
INDENT_GLYPHS = ("│  ", "   ")
# Departure appends diagnostics such as `[declaration conflict]` to a line, and
# prints `[missing destination]` or `[destination conflict]` in place of a number.
NOTES = re.compile(r"\s*\[([^\]]+)\]")
ROUTE_LINE = re.compile(r"^(?P<style>\S+) (?P<route>\S+) →(?: destination #(?P<dest>\d+))?$")
BRANCH_LINE = re.compile(r"^branch #(?P<index>\d+)(?: \((?P<tag>[^)]*)\))?$")
BRANCHES_LINE = re.compile(r"^branches(?P<concurrent> \(concurrent\))?$")


class DumpError(Exception):
    pass


def find_last_dump(lines):
    """Returns (header, tree lines with the console prefix stripped) for the last dump."""
    marker_indexes = [index for index, line in enumerate(lines) if MARKER in line]
    if not marker_indexes:
        raise DumpError(f"no '{MARKER}' line found in the input")

    start = marker_indexes[-1]
    header = lines[start]
    header = header[header.find("[map]"):].strip() if "[map]" in header else header.strip()
    root_index = next(
        (index for index in range(start + 1, len(lines)) if lines[index].rstrip().endswith("root")),
        None,
    )
    if root_index is None:
        raise DumpError("found the map header but no 'root' line after it")

    root_line = lines[root_index].rstrip()
    column = len(root_line) - len("root")
    tree = ["root"]
    for line in lines[root_index + 1:]:
        body = line.rstrip("\n")[column:]
        # Console copies can carry blank lines inside the dump.
        if not body.strip():
            continue
        if not body.startswith(BRANCH_GLYPHS + INDENT_GLYPHS):
            break
        tree.append(body.rstrip())
    return header, tree


def parse_depth(body):
    depth = 0
    while body[depth * 3:depth * 3 + 3] in INDENT_GLYPHS:
        depth += 1
    glyph = body[depth * 3:depth * 3 + 3]
    if glyph not in BRANCH_GLYPHS:
        raise DumpError(f"unexpected tree line: {body!r}")
    return depth + 1, body[depth * 3 + 3:]


def make_node(label):
    notes = NOTES.findall(label)
    base = NOTES.sub("", label).strip()
    node = {"notes": notes, "children": []}

    route_match = ROUTE_LINE.match(base)
    if route_match:
        dest = route_match["dest"]
        return {**node, "kind": "route", "style": route_match["style"], "route": route_match["route"],
                "dest": int(dest) if dest else None}

    branch_match = BRANCH_LINE.match(base)
    if branch_match:
        return {**node, "kind": "branch", "label": base, "index": int(branch_match["index"]), "tag": branch_match["tag"]}

    branches_match = BRANCHES_LINE.match(base)
    if branches_match:
        return {**node, "kind": "branches", "label": "branches", "concurrent": bool(branches_match["concurrent"])}

    if base == "global":
        return {**node, "kind": "global", "label": base}

    # A label made only of notes, such as `[branch outside container]`.
    return {**node, "kind": "group", "label": base or "; ".join(notes), "notes": notes if base else []}


def parse_tree(tree):
    root = {"kind": "root", "label": "root", "children": []}
    stack = [root]
    for body in tree[1:]:
        depth, label = parse_depth(body)
        if depth > len(stack):
            raise DumpError(f"tree skips a level at: {body!r}")
        del stack[depth:]
        node = make_node(label)
        stack[-1]["children"].append(node)
        stack.append(node)
    return root


def read_input(path, from_clipboard):
    if from_clipboard:
        return subprocess.run(["pbpaste"], check=True, capture_output=True, text=True).stdout
    if path in (None, "-"):
        if sys.stdin.isatty():
            raise DumpError("pass a log file, --clipboard, or pipe the console output on stdin")
        return sys.stdin.read()
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def render(root, header):
    payload = json.dumps({"header": header, "tree": root}, ensure_ascii=False)
    # `</` inside the JSON must not terminate the inline script.
    payload = payload.replace("</", "<\\/")
    return TEMPLATE.replace("__TITLE__", html.escape(header)).replace("__DATA__", payload)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("log", nargs="?", help="console log containing the dump; '-' or omitted reads stdin")
    parser.add_argument("--clipboard", action="store_true", help="read the dump from the macOS clipboard")
    parser.add_argument("-o", "--output", help="HTML file to write (default: a temporary file)")
    parser.add_argument("--no-open", action="store_true", help="don't open the result in the browser")
    args = parser.parse_args()

    try:
        text = read_input(args.log, args.clipboard)
        header, tree = find_last_dump(text.splitlines())
        root = parse_tree(tree)
    except (DumpError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(f"{os.path.basename(sys.argv[0])}: {error}")

    output = args.output or os.path.join(tempfile.gettempdir(), "departure-route-map.html")
    with open(output, "w", encoding="utf-8") as handle:
        handle.write(render(root, header))
    print(output)

    if not args.no_open:
        subprocess.run(["open", output], check=False)


TEMPLATE = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Route Map</title>
<style>
:root {
  --bg: #f5f5f7; --panel: #ffffff; --raised: #ffffff; --text: #1d1d1f; --muted: #6e6e73; --faint: #a1a1a6;
  --line: #e3e3e8; --hover: #f0f0f4; --selected: #e7edff; --selected-line: #b9c9ff; --accent: #3a63d8;
  --shadow: 0 1px 2px rgba(0,0,0,.05), 0 2px 8px rgba(0,0,0,.04);
  --push: #23845a; --sheet: #3a63d8; --cover: #9b3fb5; --fade: #c2611e; --other: #6e6e73;
  --warn: #c4302b; --global: #c2611e; --branch: #0f8a8a; --group: #6e6e73;
  --mono: ui-monospace, SFMono-Regular, Menlo, monospace;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #111113; --panel: #19191c; --raised: #222226; --text: #ededf0; --muted: #9c9ca4; --faint: #6a6a72;
    --line: #2c2c31; --hover: #26262b; --selected: #1f2b4d; --selected-line: #3d5bb0; --accent: #8eabff;
    --shadow: 0 1px 2px rgba(0,0,0,.4);
    --push: #63cf97; --sheet: #8eabff; --cover: #d58cf0; --fade: #f2a165; --other: #9c9ca4;
    --warn: #ff7b72; --global: #f2a165; --branch: #4fd0cf; --group: #9c9ca4;
  }
}
* { box-sizing: border-box; }
html, body { height: 100%; }
body { margin: 0; display: flex; flex-direction: column; background: var(--bg); color: var(--text); font: 13px/1.4 -apple-system, BlinkMacSystemFont, system-ui, sans-serif; overflow: hidden; }
button { font: inherit; color: inherit; }
svg { display: block; flex: none; }
span[class^="kind-"] { display: inline-flex; align-items: center; }

.kind-push { color: var(--push); } .kind-sheet { color: var(--sheet); } .kind-cover { color: var(--cover); }
.kind-fade { color: var(--fade); } .kind-other { color: var(--other); } .kind-global { color: var(--global); } .kind-warn { color: var(--warn); }
.kind-branch { color: var(--branch); } .kind-group { color: var(--group); }

header { flex: none; display: flex; align-items: center; gap: 16px; padding: 10px 18px; background: var(--panel); border-bottom: 1px solid var(--line); }
header h1 { margin: 0; font-size: 15px; font-weight: 650; letter-spacing: -.01em; }
header .meta { color: var(--faint); font-family: var(--mono); font-size: 11px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.legend { display: flex; gap: 12px; margin-left: auto; color: var(--muted); font-size: 12px; }
.legend span { display: inline-flex; align-items: center; gap: 4px; }
.legend b { font-weight: 500; color: var(--muted); }

.search { position: relative; width: min(340px, 40vw); flex: none; }
.search input { width: 100%; font: inherit; padding: 7px 12px 7px 30px; border-radius: 8px; border: 1px solid var(--line); background: var(--bg); color: var(--text); outline: none; }
.search input:focus { border-color: var(--selected-line); background: var(--raised); }
.search .glass { position: absolute; left: 10px; top: 50%; transform: translateY(-50%); color: var(--faint); pointer-events: none; }
.search kbd { position: absolute; right: 8px; top: 50%; transform: translateY(-50%); }
.results { position: absolute; top: calc(100% + 6px); left: 0; right: 0; max-height: 60vh; overflow: auto; background: var(--raised); border: 1px solid var(--line); border-radius: 10px; box-shadow: 0 12px 32px rgba(0,0,0,.18); padding: 4px; z-index: 10; }
.results[hidden] { display: none; }
.result { display: grid; grid-template-columns: 18px 1fr auto; gap: 2px 8px; align-items: center; width: 100%; text-align: left; border: 0; background: none; padding: 7px 8px; border-radius: 7px; cursor: pointer; }
.result.active, .result:hover { background: var(--selected); }
.result .where { grid-column: 2 / 4; color: var(--faint); font-size: 11px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.result .times { color: var(--muted); font-size: 11px; }
.result mark { background: none; color: var(--accent); font-weight: 650; }
.no-results { padding: 10px; color: var(--muted); }
kbd { font-family: var(--mono); font-size: 10px; color: var(--muted); border: 1px solid var(--line); border-bottom-width: 2px; border-radius: 4px; padding: 0 5px; background: var(--panel); }

.crumbs { flex: none; display: flex; align-items: center; gap: 2px; padding: 8px 18px; overflow-x: auto; white-space: nowrap; border-bottom: 1px solid var(--line); background: var(--panel); }
.crumb { border: 0; background: none; padding: 3px 7px; border-radius: 6px; cursor: pointer; color: var(--muted); display: inline-flex; align-items: center; gap: 5px; }
.crumb:hover { background: var(--hover); color: var(--text); }
.crumb:last-child { color: var(--text); font-weight: 600; }
.crumb-sep { color: var(--faint); }

#columns { flex: 1 1 auto; min-height: 120px; display: flex; overflow-x: auto; overflow-y: hidden; }
#columns.animated { scroll-behavior: smooth; }
.column { flex: none; width: 272px; display: flex; flex-direction: column; border-right: 1px solid var(--line); min-height: 0; }
.column-head { flex: none; display: flex; align-items: baseline; justify-content: space-between; padding: 12px 14px 6px; }
.column-title { font-size: 11px; font-weight: 650; text-transform: uppercase; letter-spacing: .06em; color: var(--muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.column-count { font-size: 11px; color: var(--faint); }
.column-list { flex: 1 1 auto; overflow-y: auto; padding: 2px 8px 16px; display: flex; flex-direction: column; gap: 3px; }

.card { display: flex; align-items: center; gap: 10px; width: 100%; text-align: left; padding: 8px 10px; border-radius: 9px; border: 1px solid transparent; background: none; cursor: pointer; }
.card:hover { background: var(--hover); }
.card.selected { background: var(--selected); border-color: var(--selected-line); }
.card.on-path { background: var(--hover); }
.card .icon { flex: none; width: 28px; height: 28px; border-radius: 7px; display: grid; place-items: center; background: color-mix(in srgb, currentColor 13%, transparent); }
.card .text { flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; }
.card .title { color: var(--text); font-weight: 560; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.card .sub { color: var(--muted); font-size: 11px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.card .uses { flex: none; font-size: 10px; color: var(--muted); border: 1px solid var(--line); border-radius: 999px; padding: 0 6px; }
.card .count { flex: none; font-size: 11px; color: var(--muted); font-variant-numeric: tabular-nums; }
.card .chev { flex: none; color: var(--faint); font-size: 16px; line-height: 1; margin-left: -4px; }
.leaf { display: grid; place-items: center; width: 240px; }
.leaf-note { display: flex; flex-direction: column; align-items: center; gap: 6px; color: var(--muted); text-align: center; padding: 20px; max-width: 100%; }
.leaf-note svg { width: 28px; height: 28px; }
.leaf-note strong { color: var(--text); overflow-wrap: anywhere; }

.splitter { flex: none; height: 6px; cursor: row-resize; background: var(--line); opacity: .5; }
.splitter:hover { opacity: 1; }
#focus { flex: none; height: 44vh; min-height: 140px; overflow: auto; background: var(--panel); padding: 18px 22px 28px; }
.focus-head { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
.focus-head h2 { margin: 0; font-size: 20px; font-weight: 680; letter-spacing: -.02em; }
.focus-head h2 .suffix { color: var(--faint); font-weight: 500; }
.focus-head .dest { color: var(--faint); font-family: var(--mono); font-size: 12px; }
.pill { display: inline-flex; align-items: center; gap: 5px; padding: 2px 9px 2px 7px; border-radius: 999px; font-size: 12px; font-weight: 550; background: color-mix(in srgb, currentColor 13%, transparent); }
.facts { display: flex; gap: 10px; flex-wrap: wrap; margin: 14px 0 18px; }
.fact { background: var(--bg); border-radius: 10px; padding: 8px 14px; min-width: 110px; }
.fact b { display: block; font-size: 18px; font-weight: 650; font-variant-numeric: tabular-nums; }
.fact span { color: var(--muted); font-size: 11px; }
.section-title { font-size: 11px; font-weight: 650; text-transform: uppercase; letter-spacing: .06em; color: var(--muted); margin: 20px 0 8px; }

.graph-wrap { overflow-x: auto; padding-bottom: 6px; }
.graph-captions { display: grid; color: var(--faint); font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: .06em; margin-bottom: 6px; }
.graph { position: relative; }
.graph > svg { position: absolute; inset: 0; overflow: visible; }
.edge { fill: none; stroke: currentColor; stroke-width: 1.6; opacity: .55; }
.gnode { position: absolute; display: flex; align-items: center; gap: 7px; height: 30px; padding: 0 10px; border-radius: 8px; border: 1px solid var(--line); background: var(--raised); box-shadow: var(--shadow); cursor: pointer; white-space: nowrap; overflow: hidden; }
.gnode:hover { border-color: var(--selected-line); }
.gnode .label { color: var(--text); overflow: hidden; text-overflow: ellipsis; }
.gnode.center { height: 38px; border: 1.5px solid var(--selected-line); background: var(--selected); font-weight: 650; cursor: default; }
.gnode.more { color: var(--muted); cursor: default; box-shadow: none; border-style: dashed; justify-content: center; }
.gnode.empty { color: var(--faint); cursor: default; box-shadow: none; border-style: dashed; justify-content: center; background: none; }

.paths { display: flex; flex-direction: column; gap: 4px; }
.path { display: flex; flex-wrap: wrap; align-items: center; gap: 3px; padding: 6px 10px; border-radius: 8px; border: 0; background: var(--bg); text-align: left; cursor: pointer; color: var(--muted); font-size: 12px; }
.path:hover { background: var(--hover); }
.path.current { outline: 1.5px solid var(--selected-line); }
.path b { color: var(--text); font-weight: 550; }
.chips { display: flex; flex-wrap: wrap; gap: 6px; }
.chip { display: inline-flex; align-items: center; gap: 6px; border: 1px solid var(--line); background: var(--raised); border-radius: 999px; padding: 4px 10px 4px 8px; cursor: pointer; }
.chip:hover { border-color: var(--selected-line); }
.chip .n { color: var(--muted); font-size: 11px; }
.hint { color: var(--muted); margin-top: 22px; line-height: 2; }

@media (max-width: 760px) {
  .legend, header .meta { display: none; }
  .search { width: auto; flex: 1; }
  .column { width: 240px; }
}
</style>
</head>
<body>
<header>
  <h1>Route Map</h1>
  <div class="search">
    <svg class="glass" viewBox="0 0 16 16" width="14" height="14"><circle cx="7" cy="7" r="4.5" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="m10.5 10.5 3 3" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>
    <input id="search" type="search" placeholder="Jump to a route" autocomplete="off" spellcheck="false">
    <kbd>/</kbd>
    <div id="results" class="results" hidden></div>
  </div>
  <span class="meta">__TITLE__</span>
  <div class="legend" id="legend"></div>
</header>
<nav class="crumbs" id="crumbs"></nav>
<section id="columns"></section>
<div class="splitter" id="splitter" title="Drag to resize"></div>
<section id="focus"></section>
<script>
const DATA = __DATA__;
const $ = selector => document.querySelector(selector);
const esc = value => String(value).replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const el = (tag, className) => { const node = document.createElement(tag); if (className) node.className = className; return node; };

const ICONS = {
  push: '<path d="M2.5 8h10M9 4.5 12.5 8 9 11.5" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>',
  sheet: '<rect x="3" y="1.75" width="10" height="12.5" rx="2" fill="none" stroke="currentColor" stroke-width="1.3"/><rect x="3" y="8" width="10" height="6.25" rx="1.5" fill="currentColor"/>',
  cover: '<rect x="3" y="1.75" width="10" height="12.5" rx="2" fill="currentColor"/>',
  fade: '<rect x="3" y="1.75" width="10" height="12.5" rx="2" fill="currentColor" opacity=".3"/><rect x="3" y="1.75" width="10" height="12.5" rx="2" fill="none" stroke="currentColor" stroke-width="1.3"/>',
  other: '<circle cx="8" cy="8" r="4" fill="currentColor"/>',
  global: '<circle cx="8" cy="8" r="6" fill="none" stroke="currentColor" stroke-width="1.3"/><path d="M2 8h12M8 2c-2.2 2.2-2.2 9.8 0 12M8 2c2.2 2.2 2.2 9.8 0 12" fill="none" stroke="currentColor" stroke-width="1.2"/>',
  branch: '<rect x="1.75" y="5" width="12.5" height="9" rx="1.5" fill="none" stroke="currentColor" stroke-width="1.3"/><path d="M1.75 7V3.5A1.5 1.5 0 0 1 3.25 2H6.5l1.2 3" fill="none" stroke="currentColor" stroke-width="1.3"/>',
  group: '<rect x="2" y="2" width="5" height="5" rx="1.2" fill="currentColor"/><rect x="9" y="2" width="5" height="5" rx="1.2" fill="currentColor"/><rect x="2" y="9" width="5" height="5" rx="1.2" fill="currentColor"/><rect x="9" y="9" width="5" height="5" rx="1.2" fill="currentColor"/>',
};
const icon = (key, size = 16) => `<svg viewBox="0 0 16 16" width="${size}" height="${size}" aria-hidden="true">${ICONS[key] || ICONS.other}</svg>`;
const STYLES = {
  push: { key: "push", label: "Push" },
  sheet: { key: "sheet", label: "Sheet" },
  "cover.slide": { key: "cover", label: "Cover" },
  "cover.fade": { key: "fade", label: "Fading cover" },
  replace: { key: "other", label: "Replace" },
};
const styleOf = style => STYLES[style] || { key: "other", label: style };

const nodes = [];
const byDest = new Map();
const byRoute = new Map();
(function index(node, parent, depth) {
  node.id = nodes.length;
  node.parent = parent;
  node.depth = depth;
  nodes.push(node);
  if (node.kind === "route") {
    // Routes without a destination number are grouped by type instead.
    node.key = node.dest ?? `?${node.route}`;
    if (!byDest.has(node.key)) byDest.set(node.key, []);
    byDest.get(node.key).push(node);
    if (!byRoute.has(node.route)) byRoute.set(node.route, []);
    byRoute.get(node.route).push(node);
  }
  node.children.forEach(child => index(child, node, depth + 1));
  node.routeCount = node.children.reduce((sum, child) => sum + child.routeCount + (child.kind === "route" ? 1 : 0), 0);
})(DATA.tree, null, 0);

const kindKey = node => node.kind === "route" ? styleOf(node.style).key : node.kind === "branches" ? "group" : node.kind;
const destLabel = node => node.dest == null ? "no destination" : `#${node.dest}`;
const notesText = node => node.notes.length ? ` · ⚠ ${node.notes.join(", ")}` : "";
const capitalize = text => text.charAt(0).toUpperCase() + text.slice(1);
function title(node) {
  switch (node.kind) {
    case "route": return node.route.replace(/Route$/, "");
    case "branch": return `Branch ${node.index}`;
    case "branches": return "Branches";
    case "root": return "Map";
    default: return capitalize(node.label);
  }
}
function subtitle(node) {
  switch (node.kind) {
    case "route": {
      const uses = byDest.get(node.key).length;
      return `${styleOf(node.style).label} · ${destLabel(node)}` + (uses > 1 ? ` · ${uses}×` : "") + notesText(node);
    }
    case "global": return `Presentable from any route · ${node.routeCount}` + notesText(node);
    case "branch": return (node.tag ? `${node.tag} · ` : "") + (node.children.length ? `${node.children.length} entry routes` : "No routes") + notesText(node);
    case "branches": return `${node.children.length} branches` + (node.concurrent ? " · concurrent" : "") + notesText(node);
    default: return node.children.length ? `${node.children.length} children` : "";
  }
}
const titleHTML = node => node.kind === "route" && node.route.endsWith("Route")
  ? `${esc(title(node))}<span class="suffix">Route</span>` : esc(title(node));
const rank = node => node.kind === "global" ? 0 : node.kind === "branch" || node.kind === "branches" ? 1 : 2;
const ordered = node => [...node.children].sort((a, b) => rank(a) - rank(b));
const pathTo = node => { const ids = []; for (let n = node; n && n.parent; n = n.parent) ids.unshift(n.id); return ids; };

let path = [];

function setPath(next) {
  path = next;
  render();
  history.replaceState(null, "", next.length ? `#n${next[next.length - 1]}` : location.pathname + location.search);
}

function render() { renderCrumbs(); renderColumns(); renderFocus(); }

function renderCrumbs() {
  const host = $("#crumbs");
  host.replaceChildren();
  const items = [nodes[0], ...path.map(id => nodes[id])];
  items.forEach((node, i) => {
    if (i) host.append(Object.assign(el("span", "crumb-sep"), { textContent: "›" }));
    const crumb = el("button", "crumb");
    crumb.innerHTML = (i ? `<span class="kind-${kindKey(node)}">${icon(kindKey(node), 12)}</span>` : "") + esc(title(node));
    crumb.addEventListener("click", () => setPath(path.slice(0, i)));
    host.append(crumb);
  });
}

function card(node, column) {
  const selected = node.id === path[column];
  const current = selected && column === path.length - 1;
  const button = el("button", `card kind-${kindKey(node)}${current ? " selected" : selected ? " on-path" : ""}`);
  button.type = "button";
  button.innerHTML = `<span class="icon">${icon(kindKey(node))}</span>
    <span class="text"><span class="title">${esc(title(node))}</span><span class="sub">${esc(subtitle(node))}</span></span>
    ${node.children.length ? `<span class="count">${node.children.length}</span><span class="chev">›</span>` : ""}`;
  button.addEventListener("click", () => setPath([...path.slice(0, column), node.id]));
  return button;
}

function renderColumns() {
  const host = $("#columns");
  host.replaceChildren();
  const parents = [nodes[0], ...path.map(id => nodes[id])];
  parents.forEach((parent, column) => {
    if (!parent.children.length) return;
    const section = el("section", "column");
    section.innerHTML = `<div class="column-head"><span class="column-title">${column ? esc(title(parent)) : "Root"}</span><span class="column-count">${parent.children.length}</span></div>`;
    const list = el("div", "column-list");
    ordered(parent).forEach(child => list.append(card(child, column)));
    section.append(list);
    host.append(section);
  });
  const last = path.length ? nodes[path[path.length - 1]] : null;
  if (last && !last.children.length) {
    const leaf = el("section", "column leaf");
    leaf.innerHTML = `<div class="leaf-note kind-${kindKey(last)}">${icon(kindKey(last), 28)}<strong>${esc(title(last))}</strong><span>presents nothing further</span></div>`;
    host.append(leaf);
  }
  requestAnimationFrame(() => {
    host.querySelectorAll(".column-list").forEach(list => {
      const active = list.querySelector(".selected, .on-path");
      if (!active) return;
      const top = active.offsetTop - list.offsetTop;
      if (top < list.scrollTop || top + active.offsetHeight > list.scrollTop + list.clientHeight) {
        list.scrollTop = top - list.clientHeight / 3;
      }
    });
    host.scrollLeft = host.scrollWidth;
    host.classList.add("animated");
  });
}

function edge(x1, y1, x2, y2, key) {
  const mid = (x1 + x2) / 2;
  return `<path class="edge kind-${key}" d="M${x1} ${y1} C${mid} ${y1} ${mid} ${y2} ${x2} ${y2}"/>`;
}

function graph(parents, center, children) {
  const W = 210, GAP = 96, ROW = 40, MAX = 12;
  const clip = list => list.length > MAX ? [...list.slice(0, MAX - 1), { more: list.length - MAX + 1 }] : list;
  const left = clip(parents), right = clip(children.length ? children : [{ empty: "Nothing" }]);
  const width = 3 * W + 2 * GAP;
  const height = Math.max(left.length, right.length, 1) * ROW;
  const rowY = (i, count) => (height - count * ROW) / 2 + i * ROW + ROW / 2;
  const cx = W + GAP, rx = 2 * (W + GAP), cy = height / 2;

  const wrap = el("div", "graph-wrap");
  const captions = el("div", "graph-captions");
  captions.style.gridTemplateColumns = `${W}px ${GAP}px ${W}px ${GAP}px ${W}px`;
  captions.style.width = `${width}px`;
  captions.innerHTML = `<span>Presented from</span><span></span><span style="text-align:center">This route</span><span></span><span>Presents</span>`;
  const box = el("div", "graph");
  box.style.width = `${width}px`;
  box.style.height = `${height}px`;
  let svg = `<svg width="${width}" height="${height}">`;
  left.forEach((item, i) => { if (!item.more) svg += edge(W, rowY(i, left.length), cx, cy, item.edge); });
  right.forEach((item, i) => { if (!item.more && !item.empty) svg += edge(cx + W, cy, rx, rowY(i, right.length), item.edge); });
  box.innerHTML = svg + "</svg>";

  const place = (item, x, y, extra = "") => {
    const node = el("button", `gnode ${extra}`);
    node.type = "button";
    node.style.left = `${x}px`;
    node.style.width = `${W}px`;
    if (item.more || item.empty) {
      node.classList.add(item.more ? "more" : "empty");
      node.textContent = item.more ? `+${item.more} more` : item.empty;
    } else {
      node.innerHTML = `<span class="kind-${item.key}">${icon(item.key, 14)}</span><span class="label">${esc(item.label)}</span>`;
      node.title = item.hint || item.label;
      if (item.target) node.addEventListener("click", () => setPath(pathTo(item.target)));
    }
    box.append(node);
    node.style.top = `${y - node.offsetHeight / 2}px`;
    return node;
  };
  wrap.append(captions, box);
  // Nodes are placed after insertion so their height is known for vertical centring.
  queueMicrotask(() => {
    left.forEach((item, i) => place(item, 0, rowY(i, left.length)));
    place(center, cx, cy, "center");
    right.forEach((item, i) => place(item, rx, rowY(i, right.length)));
  });
  return wrap;
}

function fact(value, label) { return `<div class="fact"><b>${esc(value)}</b><span>${esc(label)}</span></div>`; }

function crumbHTML(node) {
  return pathTo(node).map(id => nodes[id]).map((n, i, all) =>
    `${i ? '<span class="crumb-sep">›</span>' : ""}<span class="kind-${kindKey(n)}">${icon(kindKey(n), 11)}</span>${i === all.length - 1 ? `<b>${esc(title(n))}</b>` : esc(title(n))}`
  ).join(" ");
}

function renderFocus() {
  const host = $("#focus");
  host.replaceChildren();
  const node = path.length ? nodes[path[path.length - 1]] : null;
  if (!node || node.kind !== "route") return renderOverview(host, node);

  const occurrences = byDest.get(node.key);
  const parents = new Map();
  occurrences.forEach(occurrence => {
    const parent = occurrence.parent;
    const key = parent.kind === "route" ? `d${parent.key}` : `n${parent.id}`;
    if (!parents.has(key)) {
      parents.set(key, { label: title(parent), key: kindKey(parent), edge: styleOf(occurrence.style).key, target: parent, hint: pathTo(parent).map(id => title(nodes[id])).join(" › ") });
    }
  });
  const children = node.children.map(child => ({ label: title(child), key: kindKey(child), edge: styleOf(child.style).key, target: child }));
  const styles = [...new Set(occurrences.map(o => o.style))];

  const head = el("div", "focus-head");
  head.innerHTML = `${styles.map(s => `<span class="pill kind-${styleOf(s).key}">${icon(styleOf(s).key, 13)}${esc(styleOf(s).label)}</span>`).join("")}
    <h2>${titleHTML(node)}</h2><span class="dest">${node.dest == null ? "no destination" : `destination #${node.dest}`}</span>`
    + [...new Set(occurrences.flatMap(o => o.notes))].map(n => `<span class="pill kind-warn">⚠ ${esc(n)}</span>`).join("")
    + (occurrences.some(o => pathTo(o).some(id => nodes[id].kind === "global")) ? `<span class="pill kind-global">${icon("global", 13)}Presentable from any route</span>` : "");
  const facts = el("div", "facts");
  facts.innerHTML = fact(occurrences.length, occurrences.length === 1 ? "appearance" : "appearances")
    + fact(parents.size, "presented from") + fact(node.children.length, "presents") + fact(node.depth - 1, "levels deep");
  host.append(head, facts, graph([...parents.values()], { label: title(node), key: kindKey(node) }, children));

  host.append(Object.assign(el("div", "section-title"), { textContent: `Every way to reach it (${occurrences.length})` }));
  const list = el("div", "paths");
  occurrences.forEach(occurrence => {
    const row = el("button", `path${occurrence === node ? " current" : ""}`);
    row.innerHTML = crumbHTML(occurrence);
    row.addEventListener("click", () => setPath(pathTo(occurrence)));
    list.append(row);
  });
  host.append(list);
}

function renderOverview(host, node) {
  const scope = node || nodes[0];
  const inside = [];
  (function collect(n) { n.children.forEach(child => { if (child.kind === "route") inside.push(child); collect(child); }); })(scope);
  const destinations = new Set(inside.map(n => n.key));
  const types = new Set(inside.map(n => n.route));

  const head = el("div", "focus-head");
  head.innerHTML = node
    ? `<span class="pill kind-${kindKey(node)}">${icon(kindKey(node), 13)}${esc(capitalize(node.kind))}</span><h2>${esc(title(node))}</h2>`
    : `<h2>Routing map</h2><span class="dest">${esc(DATA.header)}</span>`;
  const facts = el("div", "facts");
  facts.innerHTML = fact(types.size, "route types") + fact(destinations.size, "destinations") + fact(inside.length, "placements in the tree")
    + fact(Math.max(0, ...inside.map(n => n.depth - scope.depth)), "levels deep");
  host.append(head, facts);

  const counts = new Map();
  inside.forEach(n => counts.set(n.key, (counts.get(n.key) || 0) + 1));
  const reused = [...counts.entries()].filter(([, count]) => count > 1).sort((a, b) => b[1] - a[1]).slice(0, 18);
  if (reused.length) {
    host.append(Object.assign(el("div", "section-title"), { textContent: "Most reused here" }));
    const chips = el("div", "chips");
    reused.forEach(([dest, count]) => {
      const first = inside.find(n => n.key === dest);
      const chip = el("button", "chip");
      chip.innerHTML = `<span class="kind-${kindKey(first)}">${icon(kindKey(first), 13)}</span>${esc(title(first))}<span class="n">${count}×</span>`;
      chip.addEventListener("click", () => setPath(pathTo(first)));
      chips.append(chip);
    });
    host.append(chips);
  }
  const hint = el("div", "hint");
  hint.innerHTML = "Pick a card to open what it presents. <kbd>↑</kbd> <kbd>↓</kbd> move, <kbd>→</kbd> opens, <kbd>←</kbd> goes back, <kbd>/</kbd> jumps to any route.";
  host.append(hint);
}

// Jump-to search
const routeIndex = [...byRoute.entries()].map(([route, occurrences]) => ({
  route, occurrences, best: occurrences.reduce((a, b) => (b.depth < a.depth ? b : a)),
}));
let results = [];
let activeResult = 0;

function renderResults() {
  const host = $("#results");
  const query = $("#search").value.trim().toLowerCase();
  if (!query) { host.hidden = true; return; }
  results = routeIndex
    .map(entry => ({ entry, at: entry.route.toLowerCase().indexOf(query) }))
    .filter(r => r.at >= 0)
    .sort((a, b) => a.at - b.at || a.entry.route.length - b.entry.route.length)
    .slice(0, 40);
  activeResult = Math.min(activeResult, Math.max(0, results.length - 1));
  host.replaceChildren();
  if (!results.length) host.innerHTML = '<div class="no-results">No matching routes</div>';
  results.forEach(({ entry, at }, i) => {
    const name = entry.route;
    const row = el("button", `result${i === activeResult ? " active" : ""}`);
    row.innerHTML = `<span class="kind-${kindKey(entry.best)}">${icon(kindKey(entry.best))}</span>
      <span>${esc(name.slice(0, at))}<mark>${esc(name.slice(at, at + query.length))}</mark>${esc(name.slice(at + query.length))}</span>
      <span class="times">${entry.occurrences.length}×</span>
      <span class="where">${esc(pathTo(entry.best.parent).map(id => title(nodes[id])).join(" › "))}</span>`;
    row.addEventListener("mousedown", event => { event.preventDefault(); choose(i); });
    host.append(row);
  });
  host.hidden = false;
  host.querySelector(".active")?.scrollIntoView({ block: "nearest" });
}

function choose(i) {
  const pick = results[i];
  if (!pick) return;
  $("#search").value = "";
  $("#results").hidden = true;
  $("#search").blur();
  setPath(pathTo(pick.entry.best));
}

$("#search").addEventListener("input", () => { activeResult = 0; renderResults(); });
$("#search").addEventListener("blur", () => { $("#results").hidden = true; });
$("#search").addEventListener("focus", renderResults);
$("#search").addEventListener("keydown", event => {
  if (event.key === "ArrowDown" || event.key === "ArrowUp") {
    event.preventDefault();
    activeResult = Math.max(0, Math.min(results.length - 1, activeResult + (event.key === "ArrowDown" ? 1 : -1)));
    renderResults();
  } else if (event.key === "Enter") {
    choose(activeResult);
  } else if (event.key === "Escape") {
    $("#search").value = "";
    $("#search").blur();
  }
});

document.addEventListener("keydown", event => {
  if (document.activeElement === $("#search")) return;
  if (event.key === "/" || (event.key === "k" && (event.metaKey || event.ctrlKey))) {
    event.preventDefault();
    $("#search").focus();
    return;
  }
  const column = path.length - 1;
  const siblings = ordered(column < 0 ? nodes[0] : column ? nodes[path[column - 1]] : nodes[0]);
  const current = column < 0 ? null : nodes[path[column]];
  let next = null;
  if (event.key === "ArrowDown" || event.key === "ArrowUp") {
    const i = current ? siblings.indexOf(current) : -1;
    const target = siblings[Math.max(0, Math.min(siblings.length - 1, i + (event.key === "ArrowDown" ? 1 : -1)))];
    if (target) next = [...path.slice(0, Math.max(column, 0)), target.id];
  } else if (event.key === "ArrowRight" && current?.children.length) {
    next = [...path, ordered(current)[0].id];
  } else if (event.key === "ArrowLeft" && path.length) {
    next = path.slice(0, -1);
  }
  if (next) { event.preventDefault(); setPath(next); }
});

// Drag the splitter to trade column space for the focus panel.
$("#splitter").addEventListener("pointerdown", event => {
  const startY = event.clientY, startHeight = $("#focus").offsetHeight;
  const move = e => { $("#focus").style.height = `${Math.max(140, Math.min(window.innerHeight - 220, startHeight - (e.clientY - startY)))}px`; };
  const up = () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); };
  window.addEventListener("pointermove", move);
  window.addEventListener("pointerup", up);
});

$("#legend").innerHTML = [...new Set(nodes.filter(n => n.kind === "route").map(n => n.style))]
  .map(style => `<span><span class="kind-${styleOf(style).key}">${icon(styleOf(style).key, 13)}</span><b>${esc(styleOf(style).label)}</b></span>`).join("");

const fromHash = /^#n(\d+)$/.exec(location.hash);
path = fromHash && nodes[+fromHash[1]] && +fromHash[1] > 0 ? pathTo(nodes[+fromHash[1]]) : [];
render();
</script>
</body>
</html>
"""


if __name__ == "__main__":
    main()
