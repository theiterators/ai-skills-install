#!/usr/bin/env bash
set -euo pipefail

REPO="theiterators/ai-skills"
TMPDIR="${TMPDIR:-/tmp}/ai-skills-$$"
HOME_DIR="$HOME"
COMMAND="${1:-init}"

# ── Colors ──────────────────────────────────────────────────────────
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BG_IT='\033[48;2;238;127;49m'  # Iterators orange background
FG_IT='\033[38;2;238;127;49m' # Iterators orange foreground

ok()   { printf "  ${GREEN}[ok]${RESET} %s\n" "$1"; }
fail() { printf "  ${RED}[!!]${RESET} %s\n" "$1"; }
info() { printf "  ${CYAN}[+]${RESET} %s\n" "$1"; }
warn() { printf "  ${YELLOW}[!]${RESET} %s\n" "$1"; }
step() { printf "\n${BOLD}${FG_IT}▸ %s${RESET}\n" "$1"; }

# ── Arrow-key menu ──────────────────────────────────────────────────
# Usage: menu_select result_var "prompt" "option1" "option2" ...
# Returns the 0-based index of the selected option in the variable named by $1
menu_select() {
  local __result_var="$1"
  local prompt="$2"
  shift 2
  local options=("$@")
  local count=${#options[@]}
  local selected=0

  # Hide cursor
  printf '\033[?25l'

  # Print prompt
  printf "\n${BOLD}%s${RESET}\n" "$prompt"

  # Draw menu
  _draw_menu() {
    for i in "${!options[@]}"; do
      if [ "$i" -eq "$selected" ]; then
        printf "  ${BG_IT}${WHITE} ▸ %s ${RESET}\n" "${options[$i]}"
      else
        printf "    ${DIM}%s${RESET}\n" "${options[$i]}"
      fi
    done
  }

  _draw_menu

  while true; do
    # Read single char
    IFS= read -rsn1 key
    case "$key" in
      $'\x1b')
        # Read escape sequence
        read -rsn2 -t 1 seq
        case "$seq" in
          '[A') # Up
            ((selected > 0)) && ((selected--)) || true
            ;;
          '[B') # Down
            ((selected < count - 1)) && ((selected++)) || true
            ;;
        esac
        ;;
      '') # Enter
        break
        ;;
    esac
    # Move cursor up and redraw
    printf "\033[${count}A"
    _draw_menu
  done

  # Show cursor
  printf '\033[?25h'

  eval "$__result_var=$selected"
}

# ── Checkbox menu ───────────────────────────────────────────────────
# Usage: checkbox_select result_var "prompt" "option1" "option2" ...
# Returns comma-separated indices of selected items in the variable named by $1
checkbox_select() {
  local __result_var="$1"
  local prompt="$2"
  shift 2
  local options=("$@")
  local count=${#options[@]}
  local cursor=0

  # Initialize checked array (all unchecked)
  local checked=()
  for ((i=0; i<count; i++)); do
    checked+=("0")
  done

  printf '\033[?25l'
  printf "\n${BOLD}%s${RESET}\n" "$prompt"
  printf "${DIM}  (Space to toggle, Enter to confirm)${RESET}\n"

  _draw_checkboxes() {
    for i in "${!options[@]}"; do
      local mark=" "
      [ "${checked[$i]}" -eq 1 ] && mark="${GREEN}x${RESET}"
      if [ "$i" -eq "$cursor" ]; then
        printf "  ${WHITE}▸ [${mark}${WHITE}] %s${RESET}\n" "${options[$i]}"
      else
        printf "    [${mark}] ${DIM}%s${RESET}\n" "${options[$i]}"
      fi
    done
  }

  _draw_checkboxes

  while true; do
    IFS= read -rsn1 key
    case "$key" in
      $'\x1b')
        read -rsn2 -t 1 seq
        case "$seq" in
          '[A') ((cursor > 0)) && ((cursor--)) || true ;;
          '[B') ((cursor < count - 1)) && ((cursor++)) || true ;;
        esac
        ;;
      ' ')
        if [ "${checked[$cursor]}" -eq 1 ]; then
          checked[$cursor]=0
        else
          checked[$cursor]=1
        fi
        ;;
      '')
        break
        ;;
    esac
    printf "\033[${count}A"
    _draw_checkboxes
  done

  printf '\033[?25h'

  # Build result: comma-separated indices
  local result=""
  for i in "${!checked[@]}"; do
    if [ "${checked[$i]}" -eq 1 ]; then
      result="${result:+$result,}$i"
    fi
  done
  eval "$__result_var='$result'"
}

# ── Banner ──────────────────────────────────────────────────────────
banner() {
  echo ""
  printf "${BOLD}${FG_IT}"
  echo "  ╔══════════════════════════════════════════╗"
  echo "  ║     Iterators AI Skills Installer        ║"
  echo "  ╚══════════════════════════════════════════╝"
  printf "${RESET}"
  echo ""
}

# ── Core functions ──────────────────────────────────────────────────
clone_repo() {
  local err
  if command -v gh &>/dev/null; then
    if ! err=$(gh repo clone "$REPO" "$TMPDIR" -- --depth=1 -q 2>&1); then
      fail "Failed to clone via gh: $err"
      rm -rf "$TMPDIR"
      exit 1
    fi
  elif command -v git &>/dev/null; then
    if ! err=$(git clone --depth=1 -q "git@github.com:${REPO}.git" "$TMPDIR" 2>&1); then
      fail "Failed to clone via git: $err"
      rm -rf "$TMPDIR"
      exit 1
    fi
  else
    printf "  ${RED}ERROR:${RESET} gh or git is required.\n"
    printf "  Install gh: ${CYAN}https://cli.github.com${RESET}\n"
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

  chmod +x "$tool_dir/scripts/"*.sh 2>/dev/null || true

  info "$tool_name: skills -> $tool_dir/skills/"
  info "$tool_name: references -> $tool_dir/references/"
  info "$tool_name: scripts -> $tool_dir/scripts/"
}

ask_yn() {
  local prompt="$1"
  local default="${2:-n}"
  local hint="y/N"
  [ "$default" = "y" ] && hint="Y/n"
  printf "${BOLD}%s${RESET} ${DIM}(%s):${RESET} " "$prompt" "$hint"
  read -r answer
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[Yy] ]]
}

resolve_scope() {
  local scope="$1"
  if [ "$scope" = "project" ]; then
    BASE_DIR="$(pwd)"
    IT_DIR="$BASE_DIR/.iterators"
  else
    BASE_DIR="$HOME_DIR"
    IT_DIR="$HOME_DIR/.iterators"
  fi
  VERSION_FILE="$IT_DIR/ai-skills-version.json"
}

tool_dir_for() {
  local tool="$1"
  case "$tool" in
    claude)  echo "$BASE_DIR/.claude" ;;
    copilot) echo "$BASE_DIR/.github" ;;
    cursor)  echo "$BASE_DIR/.cursor" ;;
    codex)   echo "$BASE_DIR/.agents" ;;
  esac
}

tool_key_at() {
  local idx="$1"
  case "$idx" in
    0) echo "claude" ;;
    1) echo "copilot" ;;
    2) echo "cursor" ;;
    3) echo "codex" ;;
  esac
}

tool_name_at() {
  local idx="$1"
  case "$idx" in
    0) echo "Claude Code" ;;
    1) echo "GitHub Copilot" ;;
    2) echo "Cursor" ;;
    3) echo "Codex" ;;
  esac
}

write_version_marker() {
  local tools="$1"
  local scope="$2"
  mkdir -p "$IT_DIR"
  cat > "$VERSION_FILE" <<EOF
{
  "version": "$(grep '"version"' "$TMPDIR/package.json" 2>/dev/null | head -1 | sed 's/.*: *"//;s/".*//' || echo "unknown")",
  "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "tools": "$tools",
  "scope": "$scope"
}
EOF
}

detect_scope() {
  local project_vf="$(pwd)/.iterators/ai-skills-version.json"
  local global_vf="$HOME_DIR/.iterators/ai-skills-version.json"

  if [ -f "$project_vf" ]; then
    resolve_scope "project"
    return 0
  elif [ -f "$global_vf" ]; then
    resolve_scope "global"
    return 0
  fi
  return 1
}

# ── Commands ────────────────────────────────────────────────────────
cmd_init() {
  banner

  # Scope selection
  local scope_idx
  menu_select scope_idx "Where do you want to install skills?" \
    "Globally      — into ~/  (available in all projects)" \
    "Per-project   — into current directory ($(pwd))"

  local scope
  case "$scope_idx" in
    1) scope="project" ;;
    *) scope="global" ;;
  esac

  resolve_scope "$scope"

  step "Downloading latest skills..."
  clone_repo
  printf "  ${GREEN}Done.${RESET}\n"

  # Tool selection via checkboxes
  local tool_selection
  checkbox_select tool_selection "Which tools do you use?" \
    "Claude Code" \
    "GitHub Copilot" \
    "Cursor" \
    "Codex"

  if [ -z "$tool_selection" ]; then
    echo ""
    printf "  ${YELLOW}No tools selected. Nothing to install.${RESET}\n"
    rm -rf "$TMPDIR"
    return
  fi

  step "Installing skills..."
  local selected=""
  IFS=',' read -ra sel_indices <<< "$tool_selection"
  for idx in "${sel_indices[@]}"; do
    local key
    key="$(tool_key_at "$idx")"
    local name
    name="$(tool_name_at "$idx")"
    copy_to_tool "$name" "$(tool_dir_for "$key")"
    selected="${selected:+$selected,}$key"
  done

  write_version_marker "$selected" "$scope"

  # Jira credentials
  step "Jira credentials"
  local cred_dir="$HOME_DIR/.iterators"
  local env_file="$cred_dir/.env"
  if [ -f "$env_file" ] && grep -q "JIRA_EMAIL" "$env_file" 2>/dev/null && grep -q "JIRA_API_TOKEN" "$env_file" 2>/dev/null; then
    ok "Already configured in ~/.iterators/.env"
  elif ask_yn "Set up Jira credentials now?"; then
    mkdir -p "$cred_dir"
    echo ""
    printf "  ${BOLD}Your Jira email:${RESET} "
    read -r jira_email
    echo ""
    printf "  Get your token at: ${CYAN}https://id.atlassian.com/manage-profile/security/api-tokens${RESET}\n"
    echo ""
    printf "  ${BOLD}Paste your Jira API token:${RESET} "
    read -r jira_token
    if [ -n "$jira_email" ] && [ -n "$jira_token" ]; then
      echo "JIRA_EMAIL=$jira_email" > "$env_file"
      echo "JIRA_API_TOKEN=$jira_token" >> "$env_file"
      chmod 600 "$env_file"
      ok "Credentials saved to ~/.iterators/.env"
    else
      warn "Skipped — you can set it later with /it-setup"
    fi
  fi

  # Summary
  echo ""
  printf "${BOLD}${FG_IT}"
  echo "  ╔══════════════════════════════════════════╗"
  echo "  ║              All done!                   ║"
  echo "  ╚══════════════════════════════════════════╝"
  printf "${RESET}"
  echo ""
  printf "  ${BOLD}Scope:${RESET} %s\n" "$scope"
  printf "  ${BOLD}Tools:${RESET} %s\n" "$selected"

  if [ "$scope" = "project" ]; then
    echo ""
    printf "  ${YELLOW}NOTE:${RESET} Skills installed into ${BOLD}$(pwd)${RESET}\n"
    printf "  You need to run this installer from your project directory.\n"
    printf "  To update, run this script with ${CYAN}update${RESET} from the same directory.\n"
    printf "  Consider adding the installed directories to ${DIM}.gitignore${RESET} or committing them.\n"
  fi

  echo ""
  printf "  Next: run ${CYAN}/it-setup${RESET} in your project to configure Jira.\n"
  echo ""

  rm -rf "$TMPDIR"
}

cmd_update() {
  banner

  if ! detect_scope; then
    printf "  ${RED}No previous installation found.${RESET}\n"
    printf "  Run ${CYAN}install.sh${RESET} (init) first, or cd into a project with a per-project install.\n"
    exit 1
  fi

  local scope
  scope="$(grep '"scope"' "$VERSION_FILE" 2>/dev/null | sed 's/.*: *"//;s/".*//' || echo "global")"

  local tools
  tools="$(grep '"tools"' "$VERSION_FILE" | sed 's/.*: *"//;s/".*//')"

  printf "  ${BOLD}Scope:${RESET} %s\n" "$scope"
  printf "  ${BOLD}Previous tools:${RESET} %s\n" "$tools"

  step "Downloading latest skills..."
  clone_repo
  printf "  ${GREEN}Done.${RESET}\n"

  step "Updating..."
  IFS=',' read -ra tool_list <<< "$tools"
  for tool in "${tool_list[@]}"; do
    local dir
    dir="$(tool_dir_for "$tool")"
    if [ -n "$dir" ]; then
      case "$tool" in
        claude)  copy_to_tool "Claude Code" "$dir" ;;
        copilot) copy_to_tool "GitHub Copilot" "$dir" ;;
        cursor)  copy_to_tool "Cursor" "$dir" ;;
        codex)   copy_to_tool "Codex" "$dir" ;;
        *)       warn "Unknown tool: $tool, skipping." ;;
      esac
    else
      warn "Unknown tool: $tool, skipping."
    fi
  done

  write_version_marker "$tools" "$scope"

  echo ""
  printf "${BOLD}${FG_IT}"
  echo "  ╔══════════════════════════════════════════╗"
  echo "  ║              Updated!                    ║"
  echo "  ╚══════════════════════════════════════════╝"
  printf "${RESET}\n"

  rm -rf "$TMPDIR"
}

cmd_doctor() {
  banner

  local issues=0

  if ! detect_scope; then
    printf "  ${RED}No installation found${RESET} (checked current directory and global).\n"
    printf "  Run ${CYAN}install.sh${RESET} first.\n"
    exit 1
  fi

  local scope
  scope="$(grep '"scope"' "$VERSION_FILE" 2>/dev/null | sed 's/.*: *"//;s/".*//' || echo "global")"
  printf "  ${BOLD}Scope:${RESET} %s  ${DIM}(base: %s)${RESET}\n" "$scope" "$BASE_DIR"

  step "Checking skills..."
  for skill in it-brainstorming it-start-task it-code-review it-setup; do
    local skill_dir="$BASE_DIR/.claude/skills/$skill"
    if [ -d "$skill_dir" ]; then
      ok "$skill"
    else
      fail "$skill — not found at $skill_dir"
      ((issues++)) || true
    fi
  done

  step "Checking jira.sh..."
  local jira_path="$BASE_DIR/.claude/scripts/jira.sh"
  if [ -f "$jira_path" ] && [ -x "$jira_path" ]; then
    ok "$jira_path (executable)"
  elif [ -f "$jira_path" ]; then
    fail "$jira_path exists but is NOT executable"
    ((issues++)) || true
  else
    fail "$jira_path — not found"
    ((issues++)) || true
  fi

  step "Checking Jira credentials..."
  local env_file="$HOME_DIR/.iterators/.env"
  if [ -f "$env_file" ] && grep -q "JIRA_EMAIL" "$env_file" 2>/dev/null; then
    ok "JIRA_EMAIL found in ~/.iterators/.env"
  else
    fail "JIRA_EMAIL not found"
    ((issues++)) || true
  fi
  if [ -f "$env_file" ] && grep -q "JIRA_API_TOKEN" "$env_file" 2>/dev/null; then
    ok "JIRA_API_TOKEN found in ~/.iterators/.env"
  else
    fail "JIRA_API_TOKEN not found"
    ((issues++)) || true
  fi

  step "Version marker..."
  if [ -f "$VERSION_FILE" ]; then
    printf "  ${DIM}"
    cat "$VERSION_FILE"
    printf "${RESET}\n"
  else
    fail "No version marker found"
    ((issues++)) || true
  fi

  echo ""
  if [ "$issues" -eq 0 ]; then
    printf "  ${GREEN}${BOLD}All checks passed!${RESET}\n"
  else
    printf "  ${RED}${BOLD}Found %d issue(s).${RESET} Run ${CYAN}install.sh${RESET} to fix.\n" "$issues"
  fi
  echo ""
}

# ── Main ────────────────────────────────────────────────────────────
case "$COMMAND" in
  init)   cmd_init ;;
  update) cmd_update ;;
  doctor) cmd_doctor ;;
  *)
    printf "${RED}Unknown command:${RESET} %s\n" "$COMMAND"
    printf "Usage: ${CYAN}install.sh${RESET} [init|update|doctor]\n"
    exit 1
    ;;
esac