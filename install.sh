#!/usr/bin/env bash
set -euo pipefail

REPO="theiterators/ai-skills"
TMPDIR="${TMPDIR:-/tmp}/ai-skills-$$"
HOME_DIR="$HOME"
COMMAND="${1:-init}"
IT_DIR="$HOME_DIR/.iterators"
VERSION_FILE="$IT_DIR/ai-skills-version.json"

banner() {
  echo ""
  echo "============================================"
  echo "  Iterators AI Skills Installer"
  echo "============================================"
  echo ""
}

clone_repo() {
  if command -v gh &>/dev/null; then
    gh repo clone "$REPO" "$TMPDIR" -- --depth=1 -q 2>/dev/null
  elif command -v git &>/dev/null; then
    git clone --depth=1 -q "git@github.com:${REPO}.git" "$TMPDIR" 2>/dev/null
  else
    echo "ERROR: gh or git is required."
    echo "  Install gh: https://cli.github.com"
    exit 1
  fi
}

copy_to_tool() {
  local tool_name="$1"
  local tool_dir="$2"

  mkdir -p "$tool_dir/skills" "$tool_dir/references" "$tool_dir/scripts"
  cp -R "$TMPDIR/skills/"* "$tool_dir/skills/"
  cp -R "$TMPDIR/references/"* "$tool_dir/references/"
  cp -R "$TMPDIR/scripts/"* "$tool_dir/scripts/"

  # Make scripts executable
  chmod +x "$tool_dir/scripts/"*.sh 2>/dev/null || true

  echo "  [+] $tool_name: skills -> $tool_dir/skills/"
  echo "  [+] $tool_name: references -> $tool_dir/references/"
  echo "  [+] $tool_name: scripts -> $tool_dir/scripts/"
}

ask_yn() {
  local prompt="$1"
  local default="${2:-n}"
  printf "%s (y/n) [%s]: " "$prompt" "$default"
  read -r answer
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy] ]]
}

write_version_marker() {
  local tools="$1"
  mkdir -p "$IT_DIR"
  cat > "$VERSION_FILE" <<EOF
{
  "version": "$(grep '"version"' "$TMPDIR/package.json" 2>/dev/null | head -1 | sed 's/.*: *"//;s/".*//' || echo "unknown")",
  "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "tools": "$tools"
}
EOF
}

cmd_init() {
  banner
  echo "Downloading latest skills..."
  clone_repo
  echo ""

  local selected=""

  if ask_yn "Install for Claude Code?" "n"; then
    copy_to_tool "Claude Code" "$HOME_DIR/.claude"
    selected="${selected:+$selected,}claude"
  fi
  echo ""

  if ask_yn "Install for GitHub Copilot?" "n"; then
    copy_to_tool "GitHub Copilot" "$HOME_DIR/.github/copilot"
    selected="${selected:+$selected,}copilot"
  fi
  echo ""

  if ask_yn "Install for Cursor?" "n"; then
    copy_to_tool "Cursor" "$HOME_DIR/.cursor"
    selected="${selected:+$selected,}cursor"
  fi

  if [ -z "$selected" ]; then
    echo ""
    echo "No tools selected. Nothing to install."
    rm -rf "$TMPDIR"
    return
  fi

  write_version_marker "$selected"

  # Offer Jira token setup
  echo ""
  if [ -f "$IT_DIR/.env" ] && grep -q "JIRA_API_TOKEN" "$IT_DIR/.env" 2>/dev/null; then
    echo "Jira token: already configured in ~/.iterators/.env"
  elif ask_yn "Set up Jira API token now?" "n"; then
    echo ""
    echo "  Get your token at: https://id.atlassian.com/manage-profile/security/api-tokens"
    echo ""
    printf "  Paste your Jira API token: "
    read -r token
    if [ -n "$token" ]; then
      mkdir -p "$IT_DIR"
      echo "JIRA_API_TOKEN=$token" > "$IT_DIR/.env"
      chmod 600 "$IT_DIR/.env"
      echo "  [+] Token saved to ~/.iterators/.env"
    else
      echo "  Skipped — you can set it later with /it-setup"
    fi
  fi

  echo ""
  echo "--- Done! ---"
  echo "Tools: $selected"
  echo ""
  echo "Next: run /it-setup in your project to configure Jira."

  rm -rf "$TMPDIR"
}

cmd_update() {
  banner

  if [ ! -f "$VERSION_FILE" ]; then
    echo "No previous installation found. Run 'init' first."
    exit 1
  fi

  local tools
  tools="$(grep '"tools"' "$VERSION_FILE" | sed 's/.*: *"//;s/".*//')"
  echo "Previous tools: $tools"
  echo "Downloading latest skills..."
  clone_repo
  echo ""

  IFS=',' read -ra tool_list <<< "$tools"
  for tool in "${tool_list[@]}"; do
    case "$tool" in
      claude)  copy_to_tool "Claude Code" "$HOME_DIR/.claude" ;;
      copilot) copy_to_tool "GitHub Copilot" "$HOME_DIR/.github/copilot" ;;
      cursor)  copy_to_tool "Cursor" "$HOME_DIR/.cursor" ;;
      *)       echo "  [!] Unknown tool: $tool, skipping." ;;
    esac
  done

  write_version_marker "$tools"
  echo ""
  echo "--- Updated! ---"

  rm -rf "$TMPDIR"
}

cmd_doctor() {
  banner

  local issues=0

  echo "Checking skills..."
  for skill in it-brainstorming it-start-task it-code-review it-setup; do
    local skill_dir="$HOME_DIR/.claude/skills/$skill"
    if [ -d "$skill_dir" ]; then
      echo "  [ok] $skill"
    else
      echo "  [!!] $skill — not found at $skill_dir"
      ((issues++)) || true
    fi
  done

  echo ""
  echo "Checking jira.sh..."
  local jira_path="$HOME_DIR/.claude/scripts/jira.sh"
  if [ -f "$jira_path" ] && [ -x "$jira_path" ]; then
    echo "  [ok] $jira_path (executable)"
  elif [ -f "$jira_path" ]; then
    echo "  [!!] $jira_path exists but is NOT executable"
    ((issues++)) || true
  else
    echo "  [!!] $jira_path — not found"
    ((issues++)) || true
  fi

  echo ""
  echo "Checking Jira token..."
  if [ -n "${JIRA_API_TOKEN:-}" ]; then
    echo "  [ok] JIRA_API_TOKEN is set (environment)"
  elif [ -f "$IT_DIR/.env" ] && grep -q "JIRA_API_TOKEN" "$IT_DIR/.env" 2>/dev/null; then
    echo "  [ok] JIRA_API_TOKEN found in ~/.iterators/.env"
  else
    echo "  [!!] JIRA_API_TOKEN not found"
    echo "       Run install.sh init or /it-setup to configure"
    ((issues++)) || true
  fi

  echo ""
  echo "Version marker..."
  if [ -f "$VERSION_FILE" ]; then
    cat "$VERSION_FILE"
  else
    echo "  [!!] No version marker found"
    ((issues++)) || true
  fi

  echo ""
  if [ "$issues" -eq 0 ]; then
    echo "All checks passed!"
  else
    echo "Found $issues issue(s). Run install.sh to fix."
  fi
}

case "$COMMAND" in
  init)   cmd_init ;;
  update) cmd_update ;;
  doctor) cmd_doctor ;;
  *)
    echo "Unknown command: $COMMAND"
    echo "Usage: install.sh [init|update|doctor]"
    exit 1
    ;;
esac
