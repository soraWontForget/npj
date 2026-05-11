# npj - New Project Bootstrapper

`npj` is a Bash script that creates and initializes a new Git repository with your preferred defaults.
It can also create a bare remote repository, publish the project to GitHub, and push the initial branches.

---

## Features

- Initializes a new Git repo with `main` as the default branch
- Creates a README with your project description
- Adds preconfigured `.gitattributes` and `.gitignore` files
- Adds an MIT or Apache 2 license, or no license
- Optionally initializes Git LFS for common binary assets
- Adds a pre-commit hook to block files over 100 MB
- Optionally creates a `develop` branch
- Optionally creates a bare SSH remote repo and pushes your branches to it
- Optionally creates a GitHub repo with `gh` and pushes your branches to it
- Works on macOS with Bash 3.2+ and modern Linux
- Provides common `.gitignore` templates: `c`, `macos`, `python`, `node`

---

## Installation

1. Save the `npj` script somewhere on your `$PATH`, such as `~/bin/npj`:

   ```bash
   mkdir -p ~/bin
   mv npj.sh ~/bin/npj
   chmod +x ~/bin/npj
   ```

2. Add `~/bin` to your `$PATH` if it is not already there:

   ```bash
   echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
   source ~/.bashrc
   ```

3. Optional: install and authenticate the GitHub CLI if you want to use `--github`:

   ```bash
   brew install gh
   gh auth login
   ```

4. Optional: set a default SSH remote path so you do not need to pass `--remote` every time:

   ```bash
   echo 'export NPJ_REMOTE_DEFAULT="alex@porygon:/srv/nas3/projects"' >> ~/.bashrc
   ```

---

## Usage

```bash
npj <ProjectName> [options]
```

### Options

| Option                           | Description                                                              |
| -------------------------------- | ------------------------------------------------------------------------ |
| `--dir <path>`                   | Where to create the project. Default: current directory.                 |
| `--desc <text>`                  | Description to include in README.                                        |
| `--gitignore <csv>`              | Comma-separated `.gitignore` templates: `c`, `macos`, `python`, `node`.  |
| `--license <mit\|apache2\|none>` | Choose license. Default: `mit`.                                          |
| `--lfs`                          | Initialize Git LFS and track common binary types.                        |
| `--remote <user@host:/abs/path>` | Create a bare SSH remote repo and push to it.                            |
| `--remote-name <name>`           | Remote name for `--remote`. Default: `origin`.                           |
| `--github <private\|public>`     | Create a GitHub repo and push to it.                                     |
| `--github-remote-name <name>`    | Remote name for the GitHub repo. Default: `origin`, or `github` when `--remote` is also used. |
| `--github-desc <text>`           | GitHub repo description. Default: value from `--desc`.                   |
| `--no-dev-branch`                | Skip creating a `develop` branch.                                        |
| `-h`, `--help`                   | Show script help.                                                        |

---

## Examples

**Local repo only:**

```bash
npj MyLib --dir ~/code --gitignore c,macos --desc "C utilities library"
```

**Publish to GitHub:**

```bash
npj NotesApp --desc "Personal notes app" --gitignore node --github private
```

**Publish a public GitHub repo with a custom GitHub description:**

```bash
npj TinyTool \
  --desc "Local development helper" \
  --github public \
  --github-desc "Small helper tools for local development"
```

**Local + bare SSH remote, such as a NAS:**

```bash
npj wash-dev \
  --dir ~/projects \
  --desc "Wash development tools" \
  --gitignore c,macos \
  --remote alex@porygon:/srv/nas3/projects
```

**Local + bare SSH remote + GitHub:**

```bash
npj GameArt \
  --desc "Art assets for the game" \
  --gitignore macos \
  --lfs \
  --remote alex@porygon:/srv/nas3/projects \
  --github private
```

**Using default SSH remote with `NPJ_REMOTE_DEFAULT` set:**

```bash
npj GameArt --desc "Art assets for the game" --gitignore macos --lfs
```

**Skip `develop` branch creation:**

```bash
npj MyOneBranchProject --no-dev-branch
```

---

## Notes

- With only `--github`, the GitHub remote defaults to `origin`.
- With both `--remote` and `--github`, the SSH remote defaults to `origin` and the GitHub remote defaults to `github`.
- `--github` publishes to the account authenticated with `gh auth login`.
- If `NPJ_REMOTE_DEFAULT` is set and you also pass `--github`, `npj` creates both remotes unless you unset `NPJ_REMOTE_DEFAULT` for that command.
- If running with `--remote`, ensure you have SSH access to the remote host.
- The script aborts if the target directory already contains a `.git/` folder.
