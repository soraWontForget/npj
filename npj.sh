#!/usr/bin/env bash
# newproj — create & initialize a new git project locally, optionally with a remote bare repo
# usage:
#   newproj MyProject \
#     --dir ~/code              # where to create the project (default: $PWD)
#     --desc "Short description"\
#     --gitignore c,macos       # comma list of templates
#     --license mit             # mit|apache2|none (default: mit)
#     --lfs                     # initialize Git LFS
#     --remote user@porygon:/srv/nas3/projects   # base path on remote host
#     --remote-name origin      # default: origin
#     --no-dev-branch           # skip creating 'develop'
set -euo pipefail

# ---------- defaults ----------
DIR="$PWD"
DESC=""
GITIGNORE_TEMPLATES=""
LICENSE="mit"
USE_LFS=0
REMOTE_BASE=""
REMOTE_NAME="origin"
MAKE_DEV_BRANCH=1

die(){ echo "error: $*" >&2; exit 1; }

# ---------- args ----------
[[ ${1:-} ]] || die "project name required. Try: newproj MyProject [options]"
NAME="$1"; shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) DIR="$2"; shift 2;;
    --desc) DESC="$2"; shift 2;;
    --gitignore) GITIGNORE_TEMPLATES="$2"; shift 2;;
    --license) LICENSE="${2,,}"; shift 2;;
    --lfs) USE_LFS=1; shift;;
    --remote) REMOTE_BASE="$2"; shift 2;;
    --remote-name) REMOTE_NAME="$2"; shift 2;;
    --no-dev-branch) MAKE_DEV_BRANCH=0; shift;;
    -h|--help)
      sed -n '1,40p' "$0"; exit 0;;
    *) die "unknown option: $1";;
  esac
done

# ---------- paths ----------
PROJECT_DIR="${DIR%/}/${NAME}"
REMOTE_REPO_PATH=""
if [[ -n "$REMOTE_BASE" ]]; then
  # normalize remote path like user@host:/abs/path
  if [[ "$REMOTE_BASE" != *:* ]]; then die "--remote must be user@host:/abs/path"; fi
  REMOTE_REPO_PATH="${REMOTE_BASE%/}/${NAME}.git"
fi

# ---------- create local structure ----------
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

git init --initial-branch=main >/dev/null

# .gitattributes (sane defaults)
cat > .gitattributes <<'EOF'
* text=auto eol=lf
*.sh text eol=lf
*.bat text eol=crlf
*.ps1 text eol=crlf
*.png binary
*.jpg binary
*.zip binary
*.pdf binary
EOF

# README
cat > README.md <<EOF
# $NAME

${DESC}

## Setup

\`\`\`bash
git clone <REPO_URL>
\`\`\`
EOF

# LICENSE
case "$LICENSE" in
  mit)
    YEAR=$(date +%Y)
    AUTHOR="${GIT_AUTHOR_NAME:-${USER:-Your Name}}"
    cat > LICENSE <<EOF
MIT License

Copyright (c) $YEAR $AUTHOR

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
    ;;
  apache2)
    cat > LICENSE <<'EOF'
Apache License 2.0
You can get the full text from https://www.apache.org/licenses/LICENSE-2.0.txt
EOF
    ;;
  none) : ;;
  *) die "unknown --license $LICENSE (use mit|apache2|none)";;
esac

# .gitignore (simple templating)
new_ignore(){
  case "$1" in
    c)
      cat <<'E';;
# C/C++
*.o
*.a
*.so
*.out
build/
dist/
E
    macos)
      cat <<'E';;
# macOS
.DS_Store
.AppleDouble
.Spotlight-V100
.Trashes
E
    python)
      cat <<'E';;
# Python
__pycache__/
*.pyc
.venv/
.env
E
    node)
      cat <<'E';;
# Node
node_modules/
dist/
npm-debug.log*
yarn-error.log*
E
    *)
      echo "# $1 (template not found — add your own)";;
  esac
}
IFS=',' read -r -a TEMPL <<< "${GITIGNORE_TEMPLATES,,}"
: > .gitignore
for t in "${TEMPL[@]}"; do [[ -n "$t" ]] && new_ignore "$t" >> .gitignore; done

# Optional Git LFS
if [[ $USE_LFS -eq 1 ]]; then
  if command -v git-lfs >/dev/null; then
    git lfs install --local
    # Common patterns — tweak as needed
    git lfs track "*.psd" "*.zip" "*.mp4" "*.wav" "*.pdf" >/dev/null || true
    echo ".gitattributes" >> .gitignore
  else
    echo "warn: git-lfs not found, skipping LFS init" >&2
  fi
fi

# Pre-commit: block >100MB (prevents accidental huge blobs)
HOOKS_DIR=".git/hooks"
mkdir -p "$HOOKS_DIR"
cat > "$HOOKS_DIR/pre-commit" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
max=104857600 # 100MB
files=$(git diff --cached --name-only --diff-filter=AM)
for f in $files; do
  if [[ -f "$f" ]]; then
    size=$(wc -c < "$f")
    if (( size > max )); then
      echo "✖ Blocked: $f is >100MB ($(numfmt --to=iec "$size" 2>/dev/null || echo $size bytes))" >&2
      exit 1
    fi
  fi
done
EOF
chmod +x "$HOOKS_DIR/pre-commit"

# Initial commit
git add .
git commit -m "chore: project scaffold for ${NAME}"

# Optional develop branch
if [[ $MAKE_DEV_BRANCH -eq 1 ]]; then
  git branch develop
fi

# ---------- optional remote bare repo ----------
if [[ -n "$REMOTE_REPO_PATH" ]]; then
  echo ">> Creating remote bare repo: $REMOTE_REPO_PATH"
  ssh "${REMOTE_BASE%%:*}" "mkdir -p '${REMOTE_REPO_PATH%/*}' && git init --bare '${REMOTE_REPO_PATH}'" >/dev/null

  # (Optional) loosen safe.directory if your server uses shared dirs; uncomment if needed:
  # git config --global --add safe.directory "$(ssh "${REMOTE_BASE%%:*}" "readlink -f '${REMOTE_REPO_PATH}'")"

  git remote add "$REMOTE_NAME" "$REMOTE_REPO_PATH"
  git push -u "$REMOTE_NAME" main
  if [[ $MAKE_DEV_BRANCH -eq 1 ]]; then
    git push -u "$REMOTE_NAME" develop
  fi
fi

echo "✅ Created project at: $PROJECT_DIR"
git status --short --branch

