````markdown
# npj — New Project Bootstrapper

`npj` is a Bash script that creates and initializes a new Git repository with your preferred defaults.  
It can also automatically create a bare remote repository (e.g., on your NAS) and push the new project to it.

---

## Features

- Initializes a new Git repo with:
  - `main` as the default branch
  - Preconfigured `.gitattributes` and `.gitignore`
  - README file with your description
  - MIT or Apache 2 license (or none)
  - Optional Git LFS setup
  - Pre-commit hook to block files over 100 MB
- Optionally creates a `develop` branch
- Optionally creates a **bare** remote repo and pushes your branches to it
- Works on **macOS** (Bash 3.2+) and modern Linux
- Provides common `.gitignore` templates (`c`, `macos`, `python`, `node`)

---

## Installation

1. Save the `npj` script somewhere on your `$PATH` (e.g., `~/bin/npj`):

   ```bash
   mkdir -p ~/bin
   mv npj ~/bin/
   chmod +x ~/bin/npj
````

2. (Optional) Add `~/bin` to your `$PATH` if not already there:

   ```bash
   echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
   source ~/.bashrc
   ```

3. (Optional) Set a default remote path so you don’t need to pass `--remote` every time:

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
| `--dir <path>`                   | Where to create the project (default: current directory).                |
| `--desc <text>`                  | Description to include in README.                                        |
| `--gitignore <csv>`              | Comma-separated `.gitignore` templates (`c`, `macos`, `python`, `node`). |
| `--license <mit\|apache2\|none>` | Choose license (default: `mit`).                                         |
| `--lfs`                          | Initialize Git LFS and track common binary types.                        |
| `--remote <user@host:/abs/path>` | Create a bare remote repo and push to it.                                |
| `--remote-name <name>`           | Remote name (default: `origin`).                                         |
| `--no-dev-branch`                | Skip creating a `develop` branch.                                        |
| `-h`, `--help`                   | Show script help.                                                        |

---

## Examples

**Local repo only:**

```bash
npj MyLib --dir ~/code --gitignore c,macos --desc "C utilities library"
```

**Local + remote (NAS):**

```bash
npj wash-dev \
  --dir ~/projects \
  --desc "Wash development tools" \
  --gitignore c,macos \
  --remote alex@porygon:/srv/nas3/projects
```

**Using default remote (with NPJ\_REMOTE\_DEFAULT set):**

```bash
npj GameArt --desc "Art assets for the game" --gitignore macos --lfs
```

**Skip `develop` branch creation:**

```bash
npj MyOneBranchProject --no-dev-branch
```

---

## Notes

* If running with `--remote`, ensure you have SSH access to the remote host.
* To avoid password prompts, set up SSH keys:

  ```bash
  ssh-keygen -t ed25519 -C "you@example.com"
  ssh-copy-id alex@porygon
  ```
* The script will abort if the target directory already contains a `.git/` folder.

