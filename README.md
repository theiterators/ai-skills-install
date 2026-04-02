# Iterators AI Skills — Installer

Public installer for [theiterators/ai-skills](https://github.com/theiterators/ai-skills) (private repo).

## Install

**macOS / Linux:**
```bash
bash <(curl -sL https://raw.githubusercontent.com/theiterators/ai-skills-install/main/install.sh)
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/theiterators/ai-skills-install/main/install.ps1 | iex
```

## Update / Doctor

```bash
bash <(curl -sL https://raw.githubusercontent.com/theiterators/ai-skills-install/main/install.sh) update
bash <(curl -sL https://raw.githubusercontent.com/theiterators/ai-skills-install/main/install.sh) doctor
```

## How it works

1. Downloads the private `theiterators/ai-skills` repo via `gh` or `git` (SSH)
2. Asks **global or per-project** installation scope
   - **Global** — installs to `~/` (available in all projects)
   - **Per-project** — installs to the current directory (versioned with the repo)
3. Asks which tools to install for (Claude Code, GitHub Copilot, Cursor, Codex)
4. Copies skills, references, and scripts to the selected tool directories:
   - Claude Code → `.claude/`
   - GitHub Copilot → `.github/`
   - Cursor → `.cursor/`
   - Codex → `.agents/`
5. Saves version marker to `.iterators/ai-skills-version.json` (in home dir or project dir)
6. Cleans up the temporary clone

For per-project installs, run `update` and `doctor` from the project directory — the installer auto-detects scope from the version marker.
