#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# add-asset.sh — Add a new GLB to the Moongleam viewer, compress it, and push.
#
# Usage:
#   ./add-asset.sh <path-to-glb> <category> [display-name]
#
# Categories:
#   characters  → models/
#   items       → models/items/
#   scraps      → models/scraps/
#   enemies     → models/enemies/
#   bosses      → models/bosses/
#
# Examples:
#   ./add-asset.sh ~/Downloads/new_character.glb characters
#   ./add-asset.sh ~/Downloads/item_shield.glb items "Shield"
# ──────────────────────────────────────────────────────────────────────────────

set -e

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
MODELS_DIR="$APP_DIR/models"
INDEX="$APP_DIR/index.html"

# ── Args ──────────────────────────────────────────────────────────────────────
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <path-to-glb> <category> [display-name]"
  echo "Categories: characters, items, scraps, enemies, bosses"
  exit 1
fi

SRC="$1"
CATEGORY="$2"
FILENAME="$(basename "$SRC")"

if [[ ! -f "$SRC" ]]; then
  echo "❌ File not found: $SRC"
  exit 1
fi

# ── Destination dir ───────────────────────────────────────────────────────────
case "$CATEGORY" in
  characters) DEST_DIR="$MODELS_DIR" ;          DIR_KEY="models" ;;
  items)      DEST_DIR="$MODELS_DIR/items" ;    DIR_KEY="models/items" ;;
  scraps)     DEST_DIR="$MODELS_DIR/scraps" ;   DIR_KEY="models/scraps" ;;
  enemies)    DEST_DIR="$MODELS_DIR/enemies" ;  DIR_KEY="models/enemies" ;;
  bosses)     DEST_DIR="$MODELS_DIR/bosses" ;   DIR_KEY="models/bosses" ;;
  *)
    echo "❌ Unknown category: $CATEGORY"
    echo "   Valid: characters, items, scraps, enemies, bosses"
    exit 1
    ;;
esac

DEST="$DEST_DIR/$FILENAME"

# ── 1. Copy ───────────────────────────────────────────────────────────────────
echo "📂 Copying $FILENAME → $DEST_DIR/"
mkdir -p "$DEST_DIR"
cp "$SRC" "$DEST"

# ── 2. Compress ───────────────────────────────────────────────────────────────
echo "🗜  Compressing..."
cd "$DEST_DIR"

BEFORE=$(du -sh "$FILENAME" | cut -f1)

npx --yes @gltf-transform/cli resize "$FILENAME" "$FILENAME" --width 1024 --height 1024 2>&1 | grep -E "info:|error:" || true
npx @gltf-transform/cli webp      "$FILENAME" "$FILENAME" 2>&1 | grep -E "info:|error:" || true
npx @gltf-transform/cli draco     "$FILENAME" "$FILENAME" 2>&1 | grep -E "info:|error:" || true

AFTER=$(du -sh "$FILENAME" | cut -f1)
echo "   $BEFORE → $AFTER"

cd "$APP_DIR"

# ── 3. Add to index.html ──────────────────────────────────────────────────────
echo "📝 Updating index.html..."

# Find the group by its dir key and insert the filename before the closing ]
# Looks for:  { label: '...', dir: 'models/items', ... files: [
#               ...existing files...
#             ]},
# and appends the new filename before the ]

SEARCH="dir: '$DIR_KEY'"

if grep -q "$FILENAME" "$INDEX"; then
  echo "   ⚠️  $FILENAME already in index.html — skipping."
else
  # Use python for reliable multi-line edit
  python3 - "$INDEX" "$SEARCH" "$FILENAME" <<'PYEOF'
import sys, re

index_path = sys.argv[1]
search_str = sys.argv[2]
filename   = sys.argv[3]

with open(index_path, 'r') as f:
    content = f.read()

# Find the group block containing the search string, then find its files array
# and append the new filename before the closing ]
pattern = re.compile(
    r"((\{[^}]*?" + re.escape(search_str) + r".*?files:\s*\[)(.*?)(\]))",
    re.DOTALL
)

def inserter(m):
    pre      = m.group(2)
    existing = m.group(3)
    close    = m.group(4)
    # Get indentation from last entry
    lines = existing.rstrip().split('\n')
    indent = '    '
    for line in reversed(lines):
        stripped = line.lstrip()
        if stripped.startswith("'"):
            indent = line[:len(line) - len(line.lstrip())]
            break
    new_entry = f"\n{indent}'{filename}',"
    return pre + existing.rstrip() + new_entry + '\n  ' + close

new_content, n = pattern.subn(inserter, content, count=1)
if n == 0:
    print(f"   ❌ Could not find group with '{search_str}' in index.html")
    sys.exit(1)

with open(index_path, 'w') as f:
    f.write(new_content)

print(f"   ✅ Added '{filename}' to {search_str} group")
PYEOF
fi

# ── 4. Git commit (no auto-push) ─────────────────────────────────────────────
echo "📦 Committing to git..."
cd "$APP_DIR"
git add -A
git commit -m "Add $FILENAME to $CATEGORY"

echo ""
echo "✅ Done! Asset staged and committed."
echo "   Run 'git push' from $APP_DIR to deploy to:"
echo "   https://shinobidarkaura.github.io/moongleam-viewer/"
