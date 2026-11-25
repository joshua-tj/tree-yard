#!/bin/bash
# Makes a throwaway worktree pool for demo videos, so a recording never touches real work.
#
#   make-demo-pool.sh <dir>
#
# Creates <dir>/pool with four slots (two busy, one behind main, one free) and a treeyard.json
# whose "dev stack" is a tiny local web server, so Run, Stop, services and Install all work.
set -euo pipefail

DIR="${1:?usage: make-demo-pool.sh <dir>}"
mkdir -p "$DIR"
DIR="$(cd "$DIR" && pwd)"
rm -rf "$DIR/pool" "$DIR/origin.git" "$DIR/main"

git init -q --bare "$DIR/origin.git"
git clone -q "$DIR/origin.git" "$DIR/main" 2>/dev/null
cd "$DIR/main"
git config user.name "Demo" && git config user.email "demo@example.com"
mkdir -p src
echo "# demo app" > README.md
echo "export const greeting = 'hello'" > src/app.js
git add -A && git commit -qm "Start the demo app"
git branch -M main && git push -q origin main

mkdir -p "$DIR/pool"
branches=(add-search-bar fix-login-redirect update-docs)
for n in 1 2 3; do
  mkdir "$DIR/pool/$n"
  git worktree add -q -b "${branches[$((n - 1))]}" "$DIR/pool/$n/app"
done
# Slot 4 is free: a detached checkout of main.
mkdir "$DIR/pool/4" && git worktree add -q --detach "$DIR/pool/4/app" main

# Slot 1: a commit of its own and some uncommitted work.
cd "$DIR/pool/1/app"
git config user.name "Demo" && git config user.email "demo@example.com"
echo "export const search = () => []" > src/search.js
git add -A && git commit -qm "Add search"
echo "// todo: debounce" >> src/search.js && echo "notes" > notes.md

# Main moves on, so slots 2 and 3 are behind.
cd "$DIR/main"
echo "export const version = 2" > src/version.js
git add -A && git commit -qm "Bump the version" && git push -q origin main
for n in 1 2 3 4; do git -C "$DIR/pool/$n/app" fetch -q origin; done

cat > "$DIR/pool/treeyard.json" <<'JSON'
{
  "start": "python3 -m http.server 41{slot}0 & python3 -m http.server 41{slot}1 & wait",
  "port": "41{slot}0",
  "install": "sleep 4",
  "services": [
    { "name": "web", "port": "41{slot}0" },
    { "name": "api", "port": "41{slot}1" }
  ]
}
JSON

echo "$DIR/pool"
