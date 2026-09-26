#!/bin/bash
# End-to-end run of the project-map pipeline on a throwaway "notes" CLI:
# decisions -> spec -> sliced build tickets -> one ticket worked red->green -> close with evidence.
# Artifact: $OUT/run.log plus the final .project-map tree copied to $OUT/final-map/.
# Regenerate: bash pipeline_e2e.sh <output-dir>
PM="python3 $(cd "$(dirname "$0")/.." && pwd)/project-map/scripts/project_map.py"
OUT=${1:-$(mktemp -d "${TMPDIR:-/tmp}/pipeline-artifact.XXXX")}; rm -rf "$OUT"; mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd); LOG="$OUT/run.log"
R=$(mktemp -d "${TMPDIR:-/tmp}/pipeline.XXXX"); cd "$R" && git init -q && git config user.email t@t && git config user.name t
pass=0; fail=0
step() { echo; echo "### $*" | tee -a "$LOG"; }
expect() { # expect <exit> <pattern-or-empty> <label>
  out=$($PM status 2>&1); code=$?; echo "$out" >> "$LOG"
  if [ "$code" = "$1" ] && { [ -z "$2" ] || grep -q -- "$2" <<<"$out"; }; then pass=$((pass+1)); echo "PASS $3" | tee -a "$LOG"
  else fail=$((fail+1)); echo "FAIL $3 (exit $code)" | tee -a "$LOG"; echo "$out" | sed 's/^/    /'; fi
}
ticket() { # id type status blocked claimed body
  printf -- "---\nid: %s\ntitle: %s\ntype: %s\nstatus: %s\nblocked_by: [%s]\nclaimed_by: %s\nsupersedes:\n---\n\n%s\n" \
    "$1" "Ticket $1" "$2" "$3" "$4" "$5" "$6" > ".project-map/tickets/$1-x.md"
}
index() { python3 - "$1" "$2" <<'EOF'
import sys; p='.project-map/MAP.md'; s=open(p).read()
s=s.replace('## Decisions so far\n', f'## Decisions so far\n\n- [{sys.argv[1]} Ticket](tickets/{sys.argv[1]}-x.md): {sys.argv[2]}\n',1)
open(p,'w').write(s)
EOF
}

step "1. Map, product code, and glossary as a living doc"
$PM init >/dev/null
mkdir -p src tests
cat > src/store.py <<'EOF'
import json, pathlib
PATH = pathlib.Path("notes.json")
def load(): return json.loads(PATH.read_text()) if PATH.exists() else []
def save(notes): PATH.write_text(json.dumps(notes))
EOF
cat > src/cli.py <<'EOF'
import sys; sys.path.insert(0, "src"); import store
cmd, *args = sys.argv[1:]
notes = store.load()
if cmd == "add": notes.append({"text": args[0]}); store.save(notes)
elif cmd == "list": print("\n".join(n["text"] for n in notes))
EOF
printf '# Glossary\n\n- **Note**: a line of text the user saves.\n' > CONTEXT.md
python3 - <<'EOF'
p='.project-map/MAP.md'; s=open(p).read()
s=s.replace('<!-- One or two lines: what reaching the end of the current effort looks like. Every session orients to it. -->',
            'Notes can be tagged and filtered by tag. Spec: [notes-tags](specs/notes-tags.md)')
s=s.rstrip('\n')+'\n| [CONTEXT.md](../CONTEXT.md) | `src/**` | |\n'
open(p,'w').write(s)
EOF
mkdir -p .project-map/specs
ticket T-001 decide closed "" "" $'## Question\n\nStore tags inside each note or in a separate index?\n\n## Resolution\n\nInside each note as a list; one file stays the only store. 2026-09-26'
ticket T-002 compare closed "" "" $'## Question\n\nFilter syntax: `list --tag x` or `list tag:x`?\n\n## Resolution\n\n`list --tag x`; rejected `tag:x` because it collides with note text. 2026-09-26'
index T-001 "tags live inside each note"; index T-002 "filter with list --tag"
cat > .project-map/specs/notes-tags.md <<'EOF'
# Spec: tagged notes (2026-09-26)

## Problem
Users cannot group notes.
## Solution
`add` takes `--tag`; `list --tag x` shows only matching notes.
## Decisions
- [T-001](../tickets/T-001-x.md), [T-002](../tickets/T-002-x.md)
## Test seam
One end-to-end seam: the `cli.py` command line.
## Out of scope
Renaming tags.
EOF
git add -A && git commit -qm "decisions and spec"
expect 0 "" "decisions indexed, spec linked from destination"

step "2. Slice into build tickets with blocking edges"
ticket T-003 build open "" "" $'## What to build\n\nPrefactor: notes become objects with a tags list; old string-only notes still load.\n\n## Acceptance\n\n- [ ] existing notes still list\n- [ ] new notes carry an empty tags list'
ticket T-004 build open "T-003" "" $'## What to build\n\n`add --tag x` stores the tag and `list --tag x` filters by it.\n\n## Acceptance\n\n- [ ] a tagged note is listed under its tag\n- [ ] an untagged note is not listed under that tag\n- [ ] plain `list` still shows every note'
ticket T-005 build open "T-004" "" $'## What to build\n\n`list --tag x` accepts several tags (AND).\n\n## Acceptance\n\n- [ ] only notes carrying all given tags are listed'
expect 0 "T-003 \[build\]" "frontier starts at the prefactor ticket"
$PM status | grep -q "T-004 \[build\]" && { echo "FAIL T-004 on frontier while blocked" | tee -a "$LOG"; fail=$((fail+1)); } || { echo "PASS blocked slices stay off the frontier" | tee -a "$LOG"; pass=$((pass+1)); }

step "3. Known-bad: a build ticket without acceptance criteria"
ticket T-006 build open "" "" $'## What to build\n\nExport notes.'
expect 1 "T-006.*[Aa]cceptance" "build ticket without Acceptance is rejected"
ticket T-006 build open "" "" $'## What to build\n\nExport notes.\n\n## Acceptance\n\n<one checkbox per observable outcome>'
expect 1 "T-006.*[Aa]cceptance" "placeholder-only Acceptance is rejected"
rm .project-map/tickets/T-006-x.md

step "4. Work T-003 (prefactor) and close it"
sed -i '' 's/notes.append({"text": args\[0\]})/notes.append({"text": args[0], "tags": []})/' src/cli.py
ticket T-003 build closed "" "" $'## What to build\n\nPrefactor.\n\n## Acceptance\n\n- [X] existing notes still list\n- [x] new notes carry an empty tags list\n\n## Resolution\n\nDone; checked with `python3 src/cli.py list`. 2026-09-26'
printf -- '- **Tag**: a label attached to a note; a note can carry several.\n' >> CONTEXT.md
git add -A && git commit -qm "T-003 prefactor"
expect 0 "T-004 \[build\]" "closing T-003 (uppercase [X] counts) moves the frontier to T-004"

step "5. Work T-004 red -> green through the real CLI"
cat > tests/e2e_tags.sh <<'EOF'
#!/bin/bash
# Medium scenario: mixed tagged/untagged notes, two tags, plain list unaffected.
rm -f notes.json
python3 src/cli.py add "buy milk" --tag home
python3 src/cli.py add "ship release" --tag work
python3 src/cli.py add "call mum"
got_home=$(python3 src/cli.py list --tag home); got_all=$(python3 src/cli.py list | wc -l | tr -d ' ')
[ "$got_home" = "buy milk" ] && [ "$got_all" = "3" ]
EOF
bash tests/e2e_tags.sh >/dev/null 2>&1 && { echo "FAIL e2e passed before implementation" | tee -a "$LOG"; fail=$((fail+1)); } || { echo "PASS e2e is red before implementation" | tee -a "$LOG"; pass=$((pass+1)); }
cat > src/cli.py <<'EOF'
import sys; sys.path.insert(0, "src"); import store
cmd, *args = sys.argv[1:]
tag = args[args.index("--tag") + 1] if "--tag" in args else None
notes = store.load()
if cmd == "add": notes.append({"text": args[0], "tags": [tag] if tag else []}); store.save(notes)
elif cmd == "list": print("\n".join(n["text"] for n in notes if tag is None or tag in n.get("tags", [])))
EOF
bash tests/e2e_tags.sh > "$OUT/e2e_tags.out" 2>&1 && { echo "PASS e2e is green after implementation" | tee -a "$LOG"; pass=$((pass+1)); } || { echo "FAIL e2e still red" | tee -a "$LOG"; fail=$((fail+1)); }
cp notes.json "$OUT/e2e_notes.json"

step "6. Known-bad: close T-004 with an unchecked criterion"
ticket T-004 build closed "T-003" "" $'## What to build\n\nTags.\n\n## Acceptance\n\n- [x] a tagged note is listed under its tag\n- [ ] an untagged note is not listed under that tag\n- [x] plain `list` still shows every note\n\n## Resolution\n\nDone. Evidence: tests/e2e_tags.sh'
expect 1 "T-004.*unchecked" "closing with an unchecked acceptance box is rejected"

step "7. Close T-004 properly; the glossary is stale until updated"
ticket T-004 build closed "T-003" "" $'## What to build\n\nTags.\n\n## Acceptance\n\n- [x] a tagged note is listed under its tag\n- [x] an untagged note is not listed under that tag\n- [x] plain `list` still shows every note\n\n## Resolution\n\nDone. Evidence: `bash tests/e2e_tags.sh` exit 0, output in e2e_tags.out. 2026-09-26'
git add -A && git commit -qm "T-004 tags"
expect 1 "CONTEXT.md: covered files changed" "code changed without a glossary review is flagged stale"
printf -- '- **Tag filter**: `list --tag x` shows only notes carrying tag x.\n' >> CONTEXT.md
git commit -qam "glossary: tag filter"
expect 0 "T-005 \[build\]" "glossary updated; frontier moves to T-005"

cp -R .project-map "$OUT/final-map"; cp CONTEXT.md "$OUT/final-map/"
echo; echo "== $pass passed, $fail failed" | tee -a "$LOG"
rm -rf "$R"
[ "$fail" = 0 ]
