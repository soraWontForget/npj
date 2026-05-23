#!/usr/bin/env bash
# npj — create & initialize a new git project locally, optionally with a remote bare repo
#       and/or publish it to GitHub with gh
# usage:
#   npj <ProjectName> [options]
#   npj publish-existing [repo-path] --github <private|public> [options]
#
# examples:
#   npj MyLib --dir ~/code --gitignore c,macos --desc "C utils"
#   npj vpet --desc "virtual pet" --gitignore macos,python \
#       --remote username@host:/srv/nas3/projects
#   npj notes --github private
#   npj demo --remote username@host:/srv/nas3/projects --github public
#   npj publish-existing ~/code/MyApp --github private
#
# options:
#   --dir <path>            Where to create the project (default: $PWD)
#   --desc <text>           README description
#   --gitignore <csv>       Comma-separated templates: c,macos,python,node
#   --license <mit|apache2|none>  (default: mit)
#   --lfs                   Initialize Git LFS and track common binaries
#   --remote <user@host:/abs/path>   Create/push to bare repo on remote
#   --remote-name <name>    Remote name for --remote (default: origin)
#   --github <private|public>  Create a GitHub repo from this local scaffold and push to it
#   --github-remote-name <name> Remote name for GitHub repo
#                              (default: origin, or github when --remote is used)
#   --github-owner <owner> GitHub owner/org for publish-existing
#   --github-name <name> GitHub repo name for publish-existing
#   --github-desc <text>    GitHub repo description (default: value from --desc)
#   --push-all-branches     In publish-existing mode, push all local branches
#   --push-tags             In publish-existing mode, push tags after branches
#   --allow-dirty           In publish-existing mode, allow uncommitted local changes
#   --dry-run               Print publish-existing actions without creating or pushing
#   --no-dev-branch         Do not create 'develop' branch
#   -h|--help               Show this help
#
# env:
#   NPJ_REMOTE_DEFAULT      If set and --remote omitted, use this as default

set -euo pipefail

# ---------- helper functions ----------
die(){ echo "error: $*" >&2; exit 1; } # kill with kindness
lc(){ printf '%s' "${1-}" | tr '[:upper:]' '[:lower:]'; } # only lowercase letters
remote_exists(){ git remote get-url "$1" >/dev/null 2>&1; } # check if git remote exists

# usage: need_val <opt-name> <maybe-value>
need_val(){ # validate that an option value exists and is not another option
  local opt="$1"; local val="${2-}" # the ${var-} syntax prevents "unbound variable" error when $2 is missing
  if [[ -z "${val-}" || "${val}" == --* ]]; then # if value is empty or looks like another option, complain
    die "$opt requires a value. e.g. $opt /abs/path or $opt user@host:/abs/path" # kill with kindness
  fi
  printf '%s' "$val" # print the value for assignment
}

# Print usage information
usage(){
  cat <<'EOF' # redirecting a literal block to preserve formatting and $ signs
npj - create and initialize a new git project

Usage:
  npj <ProjectName> [options]
  npj publish-existing [repo-path] --github <private|public> [options]

Examples:
  npj MyLib --dir ~/code --gitignore c,macos --desc "C utils"
  npj vpet --desc "virtual pet" --gitignore macos,python \
      --remote username@host:/srv/nas3/projects
  npj notes --github private
  npj demo --remote username@host:/srv/nas3/projects --github public
  npj publish-existing ~/code/MyApp --github private
  npj publish-existing . --github public --github-owner my-org --push-tags

Options:
  --dir <path>             Where to create the project (default: $PWD)
                           With publish-existing, repo path to publish
  --desc <text>            README description
  --gitignore <csv>        Comma-separated templates: c,macos,python,node
  --license <mit|apache2|none>
                           Choose a license (default: mit)
  --lfs                    Initialize Git LFS and track common binaries
  --remote <user@host:/abs/path>
                           Create/push to a bare repo on an SSH remote
  --remote-name <name>     Remote name for --remote (default: origin)
  --github <private|public>
                           Create a GitHub repo from this local scaffold and push to it
  --github-remote-name <name>
                           Remote name for GitHub repo
                           (default: origin, or github when --remote is used)
  --github-owner <owner>   GitHub owner/org for publish-existing
  --github-name <name>     GitHub repo name for publish-existing
  --github-desc <text>     GitHub repo description (default: value from --desc)
  --push-all-branches      With publish-existing, push all local branches
  --push-tags              With publish-existing, push tags after branches
  --allow-dirty            With publish-existing, allow uncommitted local changes
  --dry-run                With publish-existing, print actions without running them
  --no-dev-branch          Do not create 'develop' branch
  -h, --help               Show this help

Environment:
  NPJ_REMOTE_DEFAULT       If set and --remote omitted, use this as default
EOF
}

# ---------- default environment variables ----------
DIR="$PWD"
MODE="create"
PUBLISH_PATH=""
DESC=""
GITIGNORE_TEMPLATES=""
LICENSE="mit"
USE_LFS=0
REMOTE_BASE=""
REMOTE_NAME="origin"
MAKE_DEV_BRANCH=1
GITHUB_VISIBILITY=""
GITHUB_REMOTE_NAME=""
GITHUB_DESC=""
GITHUB_OWNER=""
GITHUB_REPO_NAME=""
PUSH_ALL_BRANCHES=0
PUSH_TAGS=0
ALLOW_DIRTY=0
DRY_RUN=0

# run a command or print it if dry-run
run_or_echo(){
  if [[ $DRY_RUN -eq 1 ]]; then # if dry-run, print the command instead of running it
    printf 'dry-run:'
    printf ' %q' "$@"
    printf '\n'
  else # if not dry-run, run the command normally
    "$@"
  fi
}

# In publish-existing mode, validate that gh CLI is installed and authenticated (required for GitHub repo creation and pushing)
require_github_cli(){
  if [[ $DRY_RUN -eq 1 ]]; then # in dry-run, skip actual checks since we won't run gh commands anyway
    return 0
  fi
  # Check if gh CLI is installed, kill with kindness if not
  command -v gh >/dev/null 2>&1 || die "gh CLI not found. Install GitHub CLI first."

  # Check if gh CLI is authenticated, kill with kindness if not
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated. Run: gh auth login"
}

# Publish an existing local repo to GitHub, with options for repo name, owner, description, and which branches/tags to push
publish_existing_to_github(){
  # Validate GitHub options, ensuring visibility is set and valid, and that unsupported options are not used. Kill with kindness if any checks fail.
  [[ -n "$GITHUB_VISIBILITY" ]] || die "publish-existing requires --github private|public"

  # Remote options are not supported in publish-existing to avoid confusion and complexity; users should set up remotes manually after publishing if needed
  [[ -z "$REMOTE_BASE" ]] || die "publish-existing does not support --remote; use --github-remote-name for the GitHub remote"

  # If a path was provided as an argument, use it; otherwise default to current directory. Validate that the path is a git repo with commits and a non-detached HEAD.
  # Kill with kindness if check fails.
  [[ -n "$PUBLISH_PATH" ]] || PUBLISH_PATH="$DIR"

  # Validate that the publish path exists and is a directory. Kill with kindness if not.
  [[ -d "$PUBLISH_PATH" ]] || die "publish-existing path is not a directory: $PUBLISH_PATH"

  # Change to the publish path and validate that it's inside a git repository. Kill with kindness if not. Then change to the repo root for consistent git commands.
  cd "$PUBLISH_PATH"
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "publish-existing path is not inside a git repo: $PUBLISH_PATH"
  cd "$repo_root"

  # Validate that the repo has commits (i.e. HEAD is valid). Kill with kindness if not, since GitHub cannot create a repo from an empty git history.
  git rev-parse --verify HEAD >/dev/null 2>&1 || die "existing repo has no commits to publish"

  # Validate that the HEAD is not detached, since publishing from a detached HEAD can lead to confusion and unintended consequences. Kill with kindness if check fails.
  local branch
  branch="$(git branch --show-current)"
  [[ -n "$branch" ]] || die "cannot publish from a detached HEAD; check out a branch first"

  # If the working tree has uncommitted changes and --allow-dirty is not set, kill with kindness and ask the user to commit/stash changes or use --allow-dirty to proceed anyway.
  # This prevents accidentally publishing a repo with unintended local changes.
  if [[ $ALLOW_DIRTY -eq 0 && -n "$(git status --porcelain)" ]]; then
    die "working tree has uncommitted changes. Commit/stash them or pass --allow-dirty to publish committed history anyway."
  fi

  # If the GitHub repo name is not provided, default to the basename of the repo root directory. This provides a sensible default name for the GitHub repo based on the local project.
  if [[ -z "$GITHUB_REPO_NAME" ]]; then
    GITHUB_REPO_NAME="$(basename "$repo_root")"
  fi

  # If the GitHub remote name is not provided, default to "github" if "origin" already exists (to avoid clobbering an existing origin), or "origin" otherwise.
  # This provides a sensible default remote name for the GitHub repo while avoiding conflicts with an existing origin remote.
  if [[ -z "$GITHUB_REMOTE_NAME" ]]; then
    if remote_exists origin; then
      GITHUB_REMOTE_NAME="github"
    else
      GITHUB_REMOTE_NAME="origin"
    fi
  fi

  # Validate that the GitHub remote does not already exist. Kill with kindness if it does.
  if remote_exists "$GITHUB_REMOTE_NAME"; then
    die "remote already exists: $GITHUB_REMOTE_NAME. Choose another --github-remote-name."
  fi

  # Construct the full GitHub repo name, including owner if provided. If the user provided a repo name without an owner but did provide a GitHub owner, prepend the owner to the repo name.
  # This allows for flexible naming while ensuring the repo is created under the correct owner/org.
  local github_repo="$GITHUB_REPO_NAME"
  if [[ -n "$GITHUB_OWNER" && "$github_repo" != */* ]]; then
    github_repo="${GITHUB_OWNER}/${github_repo}"
  fi

  # Create the GitHub repo using gh CLI, specifying the source as the current directory and the remote name. Include the description if provided.
  # Then push the current branch (and optionally all branches and tags) to the new GitHub remote. Use run_or_echo to respect dry-run mode. Finally, print a success message with the GitHub remote URL and the current git status.
  echo ">> Publishing existing repo: $repo_root"
  echo ">> Creating GitHub repo: ${github_repo} (${GITHUB_VISIBILITY})"

  # Construct the gh repo create command with the appropriate arguments based on the provided options. Use an array to handle optional arguments cleanly.
  # Then run the command using run_or_echo to respect dry-run mode.
  local gh_args
  gh_args=(repo create "$github_repo" "--$GITHUB_VISIBILITY" --source=. --remote="$GITHUB_REMOTE_NAME")
  if [[ -n "$GITHUB_DESC" ]]; then
    gh_args+=(--description "$GITHUB_DESC")
  fi
  run_or_echo gh "${gh_args[@]}"

  # Push to the new GitHub remote. If --push-all-branches is set, push all branches; otherwise, push only the current branch.
  # If --push-tags is set, push tags after pushing branches. Use run_or_echo to respect dry-run mode.
  if [[ $PUSH_ALL_BRANCHES -eq 1 ]]; then
    run_or_echo git push -u "$GITHUB_REMOTE_NAME" --all
  else
    run_or_echo git push -u "$GITHUB_REMOTE_NAME" "$branch"
  fi

  # If the user requested to push tags, push them to the GitHub remote. This allows users to include their tag history in the published repo if desired.
  if [[ $PUSH_TAGS -eq 1 ]]; then
    run_or_echo git push "$GITHUB_REMOTE_NAME" --tags
  fi

  # Print a success message indicating that the existing repo has been published, along with the GitHub remote URL and the current git status.
  #This provides confirmation to the user that the publish operation was successful and shows the new remote configuration.
  echo "✅ Published existing repo: $repo_root"
  echo "   GitHub remote: $GITHUB_REMOTE_NAME -> $(git remote get-url "$GITHUB_REMOTE_NAME" 2>/dev/null || echo "<created after dry-run>")"
  git status --short --branch
}

# ---------- args ----------
# The first argument is either the project name or the "publish-existing" command.
# Handle those cases separately since publish-existing has a different meaning for the first argument and different required/optional flags.
case "${1-}" in 
  "") die "project name required. Try: npj MyProject [options]" ;;
  -h|--help) usage; exit 0 ;;
  publish-existing)
    MODE="publish-existing"
    shift
    if [[ $# -gt 0 && "${1-}" != --* ]]; then
      PUBLISH_PATH="$1"
      shift
    fi
    NAME=""
    ;;
  *)
    NAME="$1"
    shift
    ;;
esac

# Parse the remaining arguments in a loop, handling each supported flag and its value.
# Use need_val to validate that flags that require values are provided with valid values.
# Set the appropriate variables based on the flags.
while [[ $# -gt 0 ]]; do # loop over remaining arguments
  case "$1" in # handle each supported flag
    --dir)
      if [[ "$MODE" == "publish-existing" ]]; then
        PUBLISH_PATH="$(need_val --dir "${2-}")"
      else
        DIR="$(need_val --dir "${2-}")"
      fi
      shift 2
      ;;
    --desc)        DESC="$(need_val --desc "${2-}")"; shift 2;;
    --gitignore)   GITIGNORE_TEMPLATES="$(need_val --gitignore "${2-}")"; shift 2;;
    --license)     LICENSE="$(lc "$(need_val --license "${2-}")")"; shift 2;;
    --lfs)         USE_LFS=1; shift;;
    --remote)      REMOTE_BASE="$(need_val --remote "${2-}")"; shift 2;;
    --remote-name) REMOTE_NAME="$(need_val --remote-name "${2-}")"; shift 2;;
    --github)
      GITHUB_VISIBILITY="$(lc "$(need_val --github "${2-}")")"
      case "$GITHUB_VISIBILITY" in
        private|public) : ;;
        *) die "--github must be either private or public" ;;
      esac
      shift 2
      ;;
    --github-remote-name) GITHUB_REMOTE_NAME="$(need_val --github-remote-name "${2-}")"; shift 2;;
    --github-owner) GITHUB_OWNER="$(need_val --github-owner "${2-}")"; shift 2;;
    --github-name) GITHUB_REPO_NAME="$(need_val --github-name "${2-}")"; shift 2;;
    --github-desc)   GITHUB_DESC="$(need_val --github-desc "${2-}")"; shift 2;;
    --push-all-branches) PUSH_ALL_BRANCHES=1; shift;;
    --push-tags) PUSH_TAGS=1; shift;;
    --allow-dirty) ALLOW_DIRTY=1; shift;;
    --dry-run) DRY_RUN=1; shift;;
    --no-dev-branch) MAKE_DEV_BRANCH=0; shift;;
    -h|--help) usage; exit 0;;
    *) die "unknown option: $1";;
  esac
done

# Default remote if flag omitted but env is set
if [[ "$MODE" == "create" && -z "$REMOTE_BASE" && -n "${NPJ_REMOTE_DEFAULT-}" ]]; then
  REMOTE_BASE="$NPJ_REMOTE_DEFAULT"
fi

# Default GitHub description to README description if not provided explicitly.
# This ensures the GitHub repo has a description even if the user only provided one description for both README and GitHub.
if [[ -z "$GITHUB_DESC" ]]; then
  GITHUB_DESC="$DESC"
fi

# In publish-existing mode, require GitHub CLI and run the publish function, then exit.
# The publish function will handle all the necessary steps to create the GitHub repo and push the existing local repo to it, respecting options like which branches/tags to push and whether to allow dirty state.
if [[ "$MODE" == "publish-existing" ]]; then
  require_github_cli
  publish_existing_to_github
  exit 0
fi

# In publish-existing mode, the GitHub-related options have specific meanings and some options are not supported.
# Validate that unsupported options are not used and that required options are provided. Kill with kindness if any checks fail.
if [[ -n "$GITHUB_OWNER" || -n "$GITHUB_REPO_NAME" || $PUSH_ALL_BRANCHES -eq 1 || $PUSH_TAGS -eq 1 || $ALLOW_DIRTY -eq 1 || $DRY_RUN -eq 1 ]]; then
  die "--github-owner, --github-name, --push-all-branches, --push-tags, --allow-dirty, and --dry-run are only supported with publish-existing"
fi

# If the GitHub remote name is not provided, default to "github" if "origin" already exists (to avoid clobbering an existing origin), or "origin" otherwise.
# This provides a sensible default remote name for the GitHub repo while avoiding conflicts with an existing origin remote.
if [[ -n "$GITHUB_VISIBILITY" && -z "$GITHUB_REMOTE_NAME" ]]; then
  if [[ -n "$REMOTE_BASE" ]]; then
    GITHUB_REMOTE_NAME="github"
  else
    GITHUB_REMOTE_NAME="origin"
  fi
fi

# ---------- paths ----------
PROJECT_DIR="${DIR%/}/${NAME}" # ensure no trailing slash and append project name

# ---------- safety checks ----------
# Validate that the project directory does not already exist as a git repository. Kill with kindness if it does, since we don't want to accidentally overwrite an existing repo.
if [[ -e "$PROJECT_DIR/.git" ]]; then
  die "target already a git repo: $PROJECT_DIR (remove .git or choose another --dir)"
fi

# If both a GitHub repo and a remote repo are being created, ensure they do not have the same remote name to avoid confusion and conflicts. Kill with kindness if they do.
if [[ -n "$GITHUB_VISIBILITY" && -n "$REMOTE_BASE" && "$GITHUB_REMOTE_NAME" == "$REMOTE_NAME" ]]; then
  die "--github-remote-name must differ from --remote-name when using both remotes"
fi

# If a GitHub repo is being created, ensure the GitHub CLI is installed and authenticated before proceeding, since it's required for repo creation and pushing.
# Kill with kindness if checks fail.
if [[ -n "$GITHUB_VISIBILITY" ]]; then
  require_github_cli
fi

# ---------- create project ----------
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# ---------- init repo ----------
git init --initial-branch=main >/dev/null # prefer main, but fall back to default if not supported (older git versions)

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

# For README file, use the provided description or a default message if no description is given.
# This ensures the README has some content even if the user did not provide a description.
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

: > .gitignore # redirect "nothing" to .gitignore to create or clear it
lowered_templates="$(lc "$GITIGNORE_TEMPLATES")" # convert to lowercase for case-insensitive matching
IFS=',' read -r -a TEMPL <<< "$lowered_templates" # split by comma into array

# loop over templates; if any, and append the corresponding ignore patterns to .gitignore
for t in "${TEMPL[@]:-}"; do
  [[ -n "$t" ]] && new_ignore "$t" >> .gitignore
done

# Optional Git LFS. Git LFS is great for handling large binary files, and this option initializes it and sets up tracking for common binary types.
# If git-lfs is not installed, it will print a warning but continue without LFS support.
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
git add . # add all the files in the directory that were just created.
git commit -m "chore: project scaffold for ${NAME}" >/dev/null # create initial commit with a standard message. Do it silently to avoid cluttering output, since the user will see a final status at the end.

# Optional develop branch
if [[ $MAKE_DEV_BRANCH -eq 1 ]]; then
  git branch develop >/dev/null
fi

# ---------- optional remote bare repo ----------
if [[ -n "$REMOTE_BASE" ]]; then
  # Validate user@host:/abs/path format. Kill with kindness if it doesn't match, since we need a valid format to proceed with creating the remote repo.
  case "$REMOTE_BASE" in
    *:/*) : ;; # ok
    *) die "--remote must be in the form user@host:/absolute/path";;
  esac
  REMOTE_HOST="${REMOTE_BASE%%:*}"     # username@host
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

# ---------- optional GitHub repo via gh ----------
# if the user requested a GitHub repo, create it using the gh CLI and push the local scaffold to it.
# This provides an easy way to get a new GitHub repo set up with the initial project files and commits.
if [[ -n "$GITHUB_VISIBILITY" ]]; then 
  echo ">> Creating GitHub repo: ${NAME} (${GITHUB_VISIBILITY})"

  gh_args=(repo create "$NAME" "--$GITHUB_VISIBILITY" --source=. --remote="$GITHUB_REMOTE_NAME")
  if [[ -n "$GITHUB_DESC" ]]; then
    gh_args+=(--description "$GITHUB_DESC")
  fi
  gh "${gh_args[@]}" >/dev/null

  git push -u "$GITHUB_REMOTE_NAME" main >/dev/null
  if [[ $MAKE_DEV_BRANCH -eq 1 ]]; then
    git push -u "$GITHUB_REMOTE_NAME" develop >/dev/null
  fi
fi

# ---------- success and done! ----------
echo "✅ Created project at: $PROJECT_DIR"
if [[ -n "$REMOTE_BASE" ]]; then
  echo "   SSH remote:    $REMOTE_NAME -> ${REMOTE_HOST}:${REMOTE_REPO_DIR}"
fi
if [[ -n "$GITHUB_VISIBILITY" ]]; then
  echo "   GitHub remote: $GITHUB_REMOTE_NAME -> $(git remote get-url "$GITHUB_REMOTE_NAME" 2>/dev/null || echo "<created>")"
fi
git status --short --branch
