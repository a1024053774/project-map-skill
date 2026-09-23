#!/usr/bin/env python3
"""Check a project map, list its frontier, and flag living docs that are stale against the code."""

from __future__ import annotations

import argparse
import datetime as dt
import re
import shutil
import subprocess
import sys
from pathlib import Path

MAP_BUDGET = 150
SECTIONS = ("Destination", "Notes", "Decisions so far", "Not yet specified", "Out of scope", "Living docs")
TYPES = {"decide", "compare", "prototype", "research", "task", "build"}
STATUSES = {"open", "closed", "superseded", "out-of-scope"}
RESOLVED = {"closed", "superseded"}
FIELDS = ("id", "title", "type", "status", "blocked_by", "claimed_by", "supersedes")
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
TEMPLATES = Path(__file__).resolve().parent.parent / "assets" / "templates"
OTHER_LEDGERS = (".project-to-act", "PROJECT_LEDGER.md")


def split_sections(text: str) -> dict[str, str]:
    found: dict[str, str] = {}
    current = None
    for line in re.sub(r"<!--.*?-->", "", text, flags=re.S).splitlines():
        if line.startswith("## "):
            current = line[3:].strip()
            found[current] = ""
        elif current is not None:
            found[current] += line + "\n"
    return found


def link_targets(text: str) -> list[str]:
    return [t.split("#", 1)[0] for t in LINK.findall(text) if not re.match(r"[a-z]+:", t) and not t.startswith("#")]


def parse_ticket(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---" or "---" not in [l.strip() for l in lines[1:]]:
        return {"_error": "missing frontmatter"}
    end = [l.strip() for l in lines[1:]].index("---") + 1
    ticket: dict = {}
    for line in lines[1:end]:
        key, sep, value = line.partition(":")
        if not sep:
            continue
        value = value.strip()
        if value.startswith("[") and value.endswith("]"):
            ticket[key.strip()] = [v.strip() for v in value[1:-1].split(",") if v.strip()]
        else:
            ticket[key.strip()] = value
    ticket["_body"] = split_sections("\n".join(lines[end + 1 :]))
    return ticket


def load_tickets(map_dir: Path, problems: list[str]) -> dict[str, dict]:
    tickets: dict[str, dict] = {}
    for path in sorted((map_dir / "tickets").glob("*.md")):
        name = f"tickets/{path.name}"
        ticket = parse_ticket(path)
        if "_error" in ticket:
            problems.append(f"{name}: {ticket['_error']}")
            continue
        missing = [f for f in FIELDS if f not in ticket]
        if missing:
            problems.append(f"{name}: missing fields {', '.join(missing)}")
            continue
        tid = ticket["id"]
        if not path.name.startswith(tid + "-") and path.stem != tid:
            problems.append(f"{name}: file name does not start with its id {tid}")
        if tid in tickets:
            problems.append(f"{name}: duplicate id {tid}")
        if ticket["type"] not in TYPES:
            problems.append(f"{name}: unknown type {ticket['type']!r}")
        if ticket["status"] not in STATUSES:
            problems.append(f"{name}: unknown status {ticket['status']!r}")
        if not isinstance(ticket["blocked_by"], list):
            ticket["blocked_by"] = [ticket["blocked_by"]] if ticket["blocked_by"] else []
        ticket["_file"] = name
        tickets[tid] = ticket
    return tickets


def check_map(root: Path) -> tuple[list[str], str, dict[str, dict]]:
    problems: list[str] = []
    map_dir = root / ".project-map"
    map_path = map_dir / "MAP.md"
    if not map_path.is_file():
        return [f"{map_path} not found; run init"], "", {}
    text = map_path.read_text(encoding="utf-8")
    line_count = len(text.splitlines())
    if line_count > MAP_BUDGET:
        problems.append(f"MAP.md has {line_count} lines, over the {MAP_BUDGET}-line budget; move detail into tickets or docs")
    sections = split_sections(text)
    for name in SECTIONS:
        if name not in sections:
            problems.append(f"MAP.md: missing section '## {name}'")
    for target in link_targets("".join(sections.values())):
        if target and not (map_dir / target).exists():
            problems.append(f"MAP.md: broken link {target}")

    tickets = load_tickets(map_dir, problems)
    decided = {(map_dir / t).resolve() for t in link_targets(sections.get("Decisions so far", ""))}
    for tid, t in tickets.items():
        name, listed = t["_file"], (map_dir / t["_file"]).resolve() in decided
        for dep in t["blocked_by"]:
            if dep not in tickets:
                problems.append(f"{name}: blocked_by unknown ticket {dep}")
            elif tickets[dep]["status"] == "out-of-scope" and t["status"] == "open":
                problems.append(f"{name}: blocked by out-of-scope ticket {dep}")
        if t["supersedes"] and t["supersedes"] not in tickets:
            problems.append(f"{name}: supersedes unknown ticket {t['supersedes']}")
        resolution = t["_body"].get("Resolution", "").strip()
        if t["status"] == "closed" and (not resolution or re.fullmatch(r"<[^\n]*>", resolution)):
            problems.append(f"{name}: closed without a Resolution")
        if t["status"] == "closed" and t["type"] != "build" and not listed:
            problems.append(f"{name}: closed decision missing from 'Decisions so far'")
        if t["status"] == "open" and listed:
            problems.append(f"{name}: open ticket listed in 'Decisions so far'")
    return problems, text, tickets


def living_docs(text: str) -> list[tuple[str, list[str], str]]:
    rows = []
    for line in split_sections(text).get("Living docs", "").splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 3 or cells[0] in ("Doc", "") or set(cells[0]) <= set("-: "):
            continue
        targets = link_targets(cells[0])
        rows.append((targets[0] if targets else cells[0], re.findall(r"`([^`]+)`", cells[1]), cells[2]))
    return rows


def git(root: Path, *args: str) -> str | None:
    result = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def stale_git(root: Path, doc: str, covers: list[str], verified: str) -> tuple[str | None, str | None]:
    """Return (problem, stale_reason) for one living doc in a git work tree."""
    specs = [f":(glob){c}" for c in covers]
    if not git(root, "ls-files", "--cached", "--others", "--exclude-standard", "--", *specs):
        return f"living doc {doc}: covers {', '.join(covers)} match no files", None
    base = git(root, "log", "-1", "--format=%H", "--", doc) or None
    if verified:
        commit = git(root, "rev-parse", "--verify", "--quiet", f"{verified}^{{commit}}")
        if not commit:
            return f"living doc {doc}: Verified commit {verified} not found", None
        if base is None or git(root, "merge-base", "--is-ancestor", base, commit) is not None:
            base = commit
    exclude = f":(exclude){doc}"
    if base:
        changed = git(root, "log", "--format=", "--name-only", f"{base}..HEAD", "--", *specs, exclude) or ""
        files = sorted(set(filter(None, changed.splitlines())))
        if files:
            return None, f"covered files changed after {base[:7]}: {', '.join(files[:5])}{' ...' if len(files) > 5 else ''}"
    dirty = git(root, "status", "--porcelain", "--", *specs, exclude) or ""
    if dirty and not git(root, "status", "--porcelain", "--", doc):
        files = [line[3:] for line in dirty.splitlines()]
        return None, f"uncommitted changes to covered files without a doc edit: {', '.join(files[:5])}"
    return None, None


def stale_mtime(root: Path, doc: str, covers: list[str], verified: str) -> tuple[str | None, str | None]:
    files = [p for c in covers for p in root.glob(c) if p.is_file() and p != root / doc]
    if not files:
        return f"living doc {doc}: covers {', '.join(covers)} match no files", None
    reviewed = (root / doc).stat().st_mtime
    if verified:
        try:
            reviewed = max(reviewed, dt.datetime.fromisoformat(verified).timestamp())
        except ValueError:
            return f"living doc {doc}: Verified must be a date (YYYY-MM-DD) without git", None
    newer = sorted(str(p.relative_to(root)) for p in files if p.stat().st_mtime > reviewed)
    return (None, f"covered files modified after the doc: {', '.join(newer[:5])}") if newer else (None, None)


def check_docs(root: Path, text: str) -> tuple[list[str], list[str]]:
    problems, stale = [], []
    use_git = git(root, "rev-parse", "--is-inside-work-tree") == "true"
    for link, covers, verified in living_docs(text):
        doc_path = (root / ".project-map" / link).resolve()
        try:
            doc = doc_path.relative_to(root.resolve()).as_posix()
        except ValueError:
            problems.append(f"living doc {link}: outside the project root")
            continue
        if not doc_path.is_file():
            problems.append(f"living doc {doc}: file not found")
            continue
        if not covers:
            problems.append(f"living doc {doc}: no covers paths")
            continue
        problem, reason = (stale_git if use_git else stale_mtime)(root, doc, covers, verified)
        if problem:
            problems.append(problem)
        if reason:
            stale.append(f"{doc}: {reason}")
    return problems, stale


def frontier(tickets: dict[str, dict]) -> list[dict]:
    def resolved(dep: str) -> bool:
        return dep in tickets and tickets[dep]["status"] in RESOLVED

    return [
        t for t in tickets.values()
        if t["status"] == "open" and not t["claimed_by"] and all(resolved(d) for d in t["blocked_by"])
    ]


def cmd_status(root: Path) -> int:
    problems, text, tickets = check_map(root)
    stale: list[str] = []
    if text:
        doc_problems, stale = check_docs(root, text)
        problems += doc_problems
    for title, items in (("Problems", problems), ("Stale living docs", stale)):
        print(f"{title} ({len(items)}):")
        for item in items:
            print(f"  - {item}")
    front = frontier(tickets)
    print(f"Frontier ({len(front)}):")
    for t in front:
        print(f"  - {t['id']} [{t['type']}] {t['title']}")
    claimed = [t for t in tickets.values() if t["status"] == "open" and t["claimed_by"]]
    if claimed:
        print(f"Claimed ({len(claimed)}):")
        for t in claimed:
            print(f"  - {t['id']} {t['title']} (by {t['claimed_by']})")
    return 1 if problems or stale else 0


def cmd_init(root: Path) -> int:
    map_dir = root / ".project-map"
    if map_dir.exists():
        print(f"{map_dir} already exists", file=sys.stderr)
        return 1
    others = [name for name in OTHER_LEDGERS if (root / name).exists()]
    if others:
        print(f"another ledger exists ({', '.join(others)}); choose the canonical one first", file=sys.stderr)
        return 1
    (map_dir / "tickets").mkdir(parents=True)
    shutil.copyfile(TEMPLATES / "MAP.md", map_dir / "MAP.md")
    print(f"created {map_dir / 'MAP.md'} and {map_dir / 'tickets'}/")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", nargs="?", default="status", choices=("status", "init"))
    parser.add_argument("--root", type=Path, default=Path.cwd(), help="project root (default: current directory)")
    args = parser.parse_args()
    root = args.root.expanduser().resolve()
    return cmd_init(root) if args.command == "init" else cmd_status(root)


if __name__ == "__main__":
    raise SystemExit(main())
