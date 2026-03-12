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
2. Asks which tools to install for (Claude Code, GitHub Copilot, Cursor)
3. Copies skills, references, and scripts to the selected tool directories
4. Saves version marker to `~/.iterators/ai-skills-version.json`
5. Cleans up the temporary clone
