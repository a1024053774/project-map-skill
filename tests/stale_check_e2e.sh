#!/bin/bash
# Acceptance run for project_map.py against a throwaway git project.
PM="python3 $(cd "$(dirname "$0")/.." && pwd)/project-map/scripts/project_map.py"
T=$(mktemp -d "${TMPDIR:-/tmp}/pmtest.XXXX")
cd "$T" && git init -q && git config user.email t@t && git config user.name t
pass=0; fail=0
expect() { # expect <exit> <grep-pattern-or-empty> <label>
  out=$($PM status 2>&1); code=$?
  if [ "$code" = "$1" ] && { [ -z "$2" ] || grep -q -- "$2" <<<"$out"; }; then pass=$((pass+1)); echo "PASS $3"
  else fail=$((fail+1)); echo "FAIL $3 (exit $code)"; echo "$out" | sed 's/^/    /'; fi
}

mkdir .project-to-act
$PM init >/dev/null 2>&1 && { echo "FAIL init should refuse with another ledger"; fail=$((fail+1)); } || { echo "PASS init refuses second ledger"; pass=$((pass+1)); }
rmdir .project-to-act
$PM init >/dev/null

mkdir -p src && echo 'v1' > src/app.py && echo '# App' > README.md
python3 - <<'EOF'
p='.project-map/MAP.md'; s=open(p).read()
s=s.replace('<!-- One or two lines: what reaching the end of the current effort looks like. Every session orients to it. -->','Ship v1 CLI.')
s=s.rstrip('\n')+'\n| [README.md](../README.md) | `src/**` | |\n'
open(p,'w').write(s)
EOF
ticket() { # id type status blocked claimed resolution
cat > .project-map/tickets/$1-x.md <<EOF
---
id: $1
title: Ticket $1
type: $2
status: $3
blocked_by: [$4]
claimed_by: $5
supersedes:
---

## Question

q

## Resolution

$6
EOF
}
ticket T-001 decide open "" "" ""
ticket T-002 compare open "T-001" "" ""
ticket T-003 build open "" "me" ""
printf -- "\n## Acceptance\n\n- [ ] builds\n" >> .project-map/tickets/T-003-x.md
git add -A && git commit -qm init
expect 0 "T-001 \[decide\]" "clean map, T-001 on frontier"
$PM status | grep -q "T-002" && { echo "FAIL blocked T-002 on frontier"; fail=$((fail+1)); } || { echo "PASS blocked and claimed tickets excluded from frontier"; pass=$((pass+1)); }

echo 'v2' > src/app.py; git commit -qam "code only"
expect 1 "README.md: covered files changed" "known-bad: code commit without doc edit is stale"

sed -i '' "s/| \`src\/\*\*\` | |/| \`src\/**\` | $(git rev-parse --short HEAD) |/" .project-map/MAP.md; git commit -qam verify
expect 0 "" "Verified commit acknowledges no-op change"

echo 'v3' > src/app.py; echo '# App v3' > README.md; git commit -qam "code and doc together"
expect 0 "" "code and doc in the same commit is fresh"

echo 'v4' > src/app.py
expect 1 "without a doc edit: src/app.py" "known-bad: dirty code without doc edit (path reported intact)"
echo '# App v4' > README.md
expect 0 "" "dirty code with doc edit is fresh"
git commit -qam v4

sed -i '' 's/`src\/\*\*`/`scr\/**`/' .project-map/MAP.md
expect 1 "match no files" "known-bad: covers typo is caught, not silently fresh"
git checkout -q .project-map/MAP.md

ticket T-001 decide closed "" "" "Chose A. Evidence: benchmark.md"
expect 1 "closed decision missing from 'Decisions so far'" "closed decision must be indexed"
python3 - <<'EOF'
p='.project-map/MAP.md'; s=open(p).read()
s=s.replace('## Decisions so far\n','## Decisions so far\n\n- [T-001 Ticket](tickets/T-001-x.md): chose A\n')
open(p,'w').write(s)
EOF
expect 0 "T-002 \[compare\]" "indexed decision unblocks T-002"

ticket T-002 compare closed "T-001" "" "<filled when closing: the answer>"
expect 1 "closed without a Resolution" "known-bad: template placeholder is not a resolution"
ticket T-002 compare open "T-001" "" ""

ticket T-004 decide open "T-099" "" ""
expect 1 "blocked_by unknown ticket T-099" "unknown blocker reported"
rm .project-map/tickets/T-004-x.md

for i in $(seq 1 150); do echo "- filler $i" >> .project-map/MAP.md; done
expect 1 "over the 150-line budget" "map budget enforced"
git checkout -q .project-map/MAP.md
python3 - <<'EOF'
p='.project-map/MAP.md'; s=open(p).read()
s=s.replace('## Decisions so far\n','## Decisions so far\n\n- [T-001 Ticket](tickets/T-001-x.md): chose A\n')
open(p,'w').write(s)
EOF

# Non-git mode: mtime comparison
N=$(mktemp -d "${TMPDIR:-/tmp}/pmtest-nogit.XXXX"); cp -R .project-map src README.md "$N"/; cd "$N"
sed -i '' 's/| `src\/\*\*` | [0-9a-f]* |/| `src\/**` | |/' .project-map/MAP.md
touch -t 202601010000 README.md; touch -t 202602010000 src/app.py
expect 1 "covered files modified after the doc" "no-git: newer code than doc is stale"
touch README.md
expect 0 "" "no-git: doc touched after code is fresh"

echo "== $pass passed, $fail failed"
rm -rf "$T" "$N"
[ "$fail" = 0 ]
