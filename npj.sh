#!/usr/bin/env bash
# npj — create & initialize a new git project locally, optionally with a remote bare repo
# usage:
#   npj <ProjectName> [options]
#
# examples:
#   npj MyLib --dir ~/code --gitignore c,macos --desc "C utils"
#   npj vpet --desc "virtual pet" --gitignore macos,python \
#       --remote alex@porygon:/srv/nas3/projects
#
# options:
#   --dir <path>            Where to create the project (default: $PWD)
#   --desc <text>           README description
#   --gitignore <csv>       Comma-separated templates: c,macos,python,node
#   --license <mit|apache2|none>  (default: mit)
#   --lfs                   Initialize Git LFS and track common binaries
#   --remote <user@host:/abs/path>   Create/push to bare repo on remote
#   --remote-name <name>    Remote name (default: origin)
#   --no-dev-branch         Do not create 'develop' branch
#   -h|--help               Show this help
#
# env:
#   NPJ_REMOTE_DEFAULT      If set and --remote omitted, use this as default

set -euo pipefail

# ---------- helpers ----------
die(){ echo "error: $*" >&2; exit 1; }
lc(){ printf '%s' "${1-}" | tr '[:upper:]' '[:lower:]'; }
need_val(){
  # usage: need_val <opt-name> <maybe-value>
  local opt="$1"; local val="${2-}"
  if [[ -z "${val-}" || "${val}" == --* ]]; then
    die "$opt requires a value. e.g. $opt /abs/path or $opt user@host:/abs/path"
  fi
  printf '%s' "$val"
}

# ---------- defaults ----------
DIR="$PWD"
DESC=""
GITIGNORE_TEMPLATES=""
LICENSE="mit"
USE_LFS=0
REMOTE_BASE=""
REMOTE_NAME="origin"
MAKE_DEV_BRANCH=1

# ---------- args ----------
[[ ${1:-} ]] || die "project name required. Try: npj MyProject [options]"
NAME="$1"; shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)         DIR="$(need_val --dir "${2-}")"; shift 2;;
    --desc)        DESC="$(need_val --desc "${2-}")"; shift 2;;
    --gitignore)   GITIGNORE_TEMPLATES="$(need_val --gitignore "${2-}")"; shift 2;;
    --license)     LICENSE="$(lc "$(need_val --license "${2-}")")"; shift 2;;
    --lfs)         USE_LFS=1; shift;;
    --remote)      REMOTE_BASE="$(need_val --remote "${2-}")"; shift 2;;
    --remote-name) REMOTE_NAME="$(need_val --remote-name "${2-}")"; shift 2;;
    --no-dev-branch) MAKE_DEV_BRANCH=0; shift;;
    -h|--help) sed -n '1,120p' "$0"; exit 0;;
    *) die "unknown option: $1";;
  esac
done

# Default remote if flag omitted but env is set
if [[ -z "$REMOTE_BASE" && -n "${NPJ_REMOTE_DEFAULT-}" ]]; then
  REMOTE_BASE="$NPJ_REMOTE_DEFAULT"
fi

# ---------- paths ----------
PROJECT_DIR="${DIR%/}/${NAME}"

# ---------- safety checks ----------
if [[ -e "$PROJECT_DIR/.git" ]]; then
  die "target already a git repo: $PROJECT_DIR (remove .git or choose another --dir)"
fi

mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# ---------- init repo ----------
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
You can get the full text at: https://www.apache.org/licenses/LICENSE-2.0.txt
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
.eggs/
build/
dist/
E
    node)
      cat <<'E';;
# Node
node_modules/
dist/
npm-debug.log*
yarn-error.log*
.pnpm-store/
E
    *)
      echo "# $1 (template not found — add your own)";;
  esac
}

: > .gitignore
lowered_templates="$(lc "$GITIGNORE_TEMPLATES")"
IFS=',' read -r -a TEMPL <<< "$lowered_templates"
for t in "${TEMPL[@]:-}"; do
  [[ -n "$t" ]] && new_ignore "$t" >> .gitignore
done

# Optional Git LFS
if [[ $USE_LFS -eq 1 ]]; then
  if command -v git-lfs >/dev/null 2>&1; then
    git lfs install --local >/dev/null 2>&1 || true
    git lfs track "*.psd" "*.zip" "*.mp4" "*.wav" "*.pdf" >/dev/null 2>&1 || true
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
      human="$(command -v numfmt >/dev/null 2>&1 && numfmt --to=iec "$size" || echo "$size bytes")"
      echo "✖ Blocked: $f is >100MB ($human)" >&2
      exit 1
    fi
  fi
done
EOF
chmod +x "$HOOKS_DIR/pre-commit"

# Initial commit
git add .
git commit -m "chore: project scaffold for ${NAME}" >/dev/null

# Optional develop branch
if [[ $MAKE_DEV_BRANCH -eq 1 ]]; then
  git branch develop >/dev/null
fi

# ---------- optional remote bare repo ----------
if [[ -n "$REMOTE_BASE" ]]; then
  # Validate user@host:/abs/path format
  case "$REMOTE_BASE" in
    *:/*) : ;; # ok
    *) die "--remote must be in the form user@host:/absolute/path";;
  esac
  REMOTE_HOST="${REMOTE_BASE%%:*}"     # alex@porygon
  REMOTE_BASE_DIR="${REMOTE_BASE#*:}"  # /srv/nas3/projects
  REMOTE_REPO_DIR="${REMOTE_BASE_DIR%/}/${NAME}.git"

  echo ">> Creating remote bare repo: ${REMOTE_HOST}:${REMOTE_REPO_DIR}"
  # Create base dir; init bare (prefer main if supported; fall back otherwise)
  ssh "$REMOTE_HOST" "mkdir -p '$REMOTE_BASE_DIR' && { git init --bare --initial-branch=main '$REMOTE_REPO_DIR' 2>/dev/null || git init --bare '$REMOTE_REPO_DIR'; }" >/dev/null

  git remote add "$REMOTE_NAME" "${REMOTE_HOST}:${REMOTE_REPO_DIR}"
  git push -u "$REMOTE_NAME" main >/dev/null
  if [[ $MAKE_DEV_BRANCH -eq 1 ]]; then
    git push -u "$REMOTE_NAME" develop >/dev/null
  fi
fi

echo "✅ Created project at: $PROJECT_DIR"
git status --short --branch

