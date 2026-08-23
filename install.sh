#!/usr/bin/env bash
#
# Agentic-First SDLC — manual installer.
#
# The plugin marketplace is the recommended path (see README). Use this script only when
# you want the files copied directly into a repo without the plugin system — for example
# to fork and modify the skills, or in an environment where plugins are unavailable.
#
#   ./install.sh                  install into ./.claude (project scope)
#   ./install.sh --user           install into ~/.claude (all your projects)
#   ./install.sh --target DIR     install into DIR/.claude
#   ./install.sh --force          overwrite existing files without prompting
#   ./install.sh --uninstall      remove previously installed files
#
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/plugins/agentic-sdlc"
TARGET_ROOT="$PWD"
FORCE=0
UNINSTALL=0

SKILLS=(agentic-sdlc config-bootstrap spec-writer spec-judge verify-gate ship-release github-pr)
AGENTS=(prototyper backend-dev frontend-dev qa-engineer verifier)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)      TARGET_ROOT="$HOME"; shift ;;
    --target)    TARGET_ROOT="${2:?--target needs a directory}"; shift 2 ;;
    --force)     FORCE=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help)   sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

DEST="$TARGET_ROOT/.claude"

if [[ ! -d "$SRC" ]]; then
  echo "error: cannot find plugin source at $SRC" >&2
  echo "Run this script from inside a checkout of the agentic-first-sdlc repository." >&2
  exit 1
fi

if [[ $UNINSTALL -eq 1 ]]; then
  echo "Removing Agentic-First SDLC from $DEST"
  for s in "${SKILLS[@]}"; do rm -rf "$DEST/skills/$s"; done
  for a in "${AGENTS[@]}"; do rm -f  "$DEST/agents/$a.md"; done
  rm -rf "$DEST/skills/_agentic-sdlc-reference"
  echo "Done. agentic.config.yaml and /agent-handoffs were left untouched."
  exit 0
fi

echo "Installing Agentic-First SDLC into $DEST"

# Refuse to clobber silently.
if [[ $FORCE -eq 0 ]]; then
  conflicts=()
  for s in "${SKILLS[@]}"; do [[ -e "$DEST/skills/$s" ]] && conflicts+=("skills/$s"); done
  for a in "${AGENTS[@]}"; do [[ -e "$DEST/agents/$a.md" ]] && conflicts+=("agents/$a.md"); done
  if [[ ${#conflicts[@]} -gt 0 ]]; then
    echo
    echo "The following already exist and would be overwritten:"
    printf '  %s\n' "${conflicts[@]}"
    echo
    read -r -p "Overwrite them? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted. Nothing was changed."; exit 1; }
  fi
fi

mkdir -p "$DEST/skills" "$DEST/agents"

# Skills keep their directory form so supporting files travel with them.
for s in "${SKILLS[@]}"; do
  rm -rf "$DEST/skills/$s"
  cp -R "$SRC/skills/$s" "$DEST/skills/$s"
  echo "  skill   $s"
done

for a in "${AGENTS[@]}"; do
  cp "$SRC/agents/$a.md" "$DEST/agents/$a.md"
  echo "  agent   $a"
done

# Skills reference ../../reference/*.md relative to their own directory. Under .claude/skills/
# that resolves to .claude/reference/, so place the shared reference files there.
mkdir -p "$DEST/reference"
cp "$SRC"/reference/*.md "$DEST/reference/"
echo "  reference files → $DEST/reference/"

cat <<EOF

Installed: ${#SKILLS[@]} skills, ${#AGENTS[@]} agents.

Next steps:
  1. Start Claude Code in this repo and run:  /agentic-sdlc
     (or ask it to "bootstrap the verification config")
  2. The Config Agent will interrogate you and write agentic.config.yaml.
     Nothing else in the pipeline runs until that exists.
  3. Optional: copy templates/CLAUDE.md into your repo root.

To update later, re-run this script from a fresh checkout with --force.
For automatic updates instead, use the plugin marketplace path — see README.md.
EOF
