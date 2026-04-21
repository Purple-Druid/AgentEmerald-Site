#!/usr/bin/env sh
# install.sh — AgentEmerald installer
#
# Supports: macOS, Linux (Debian/Ubuntu, Fedora/RHEL, Arch), and
#           Windows via Git Bash or WSL.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Purple-Druid/AgentEmerald/main/install.sh | sh
#
# Or with options:
#   curl -fsSL .../install.sh | sh -s -- --dir ~/.local/bin --no-gh
#
# Options:
#   --dir <path>        Install agem to this directory (default: ~/bin)
#   --no-gh             Skip GitHub CLI check/install
#   --no-node           Skip Node.js check/install
#   --version <tag>     Install a specific release tag (default: latest)
#   --clean-install     Remove any existing installation before installing
#   --help              Show this message

set -e

# ── Use ~/tmp for all temp files (avoids /tmp space issues) ──────────
AGEM_TMPDIR="${HOME}/tmp"
mkdir -p "$AGEM_TMPDIR"
export TMPDIR="$AGEM_TMPDIR"

# ── ANSI colours (disabled if not a tty) ─────────────────────────────
if [ -t 1 ]; then
  BOLD="\033[1m"; DIM="\033[2m"; RED="\033[31m"; GREEN="\033[32m"
  YELLOW="\033[33m"; CYAN="\033[36m"; RESET="\033[0m"
else
  BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; CYAN=""; RESET=""
fi

info()    { printf "${CYAN}  →${RESET} %s\n" "$*"; }
success() { printf "${GREEN}  ✓${RESET} %s\n" "$*"; }
warn()    { printf "${YELLOW}  ⚠${RESET} %s\n" "$*"; }
error()   { printf "${RED}  ✗${RESET} %s\n" "$*" >&2; }
die()     { error "$*"; exit 1; }
banner()  { printf "\n${BOLD}%s${RESET}\n" "$*"; }

# ── Defaults ──────────────────────────────────────────────────────────
INSTALL_DIR="${HOME}/bin"
SKIP_GH=0
SKIP_NODE=0
VERSION="latest"
CLEAN_INSTALL=0
REPO="Purple-Druid/AgentEmerald"
MIN_NODE_MAJOR=20

# ── Argument parsing ──────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)            INSTALL_DIR="$2"; shift 2 ;;
    --no-gh)          SKIP_GH=1;        shift   ;;
    --no-node)        SKIP_NODE=1;      shift   ;;
    --version)        VERSION="$2";     shift 2 ;;
    --clean-install)  CLEAN_INSTALL=1;  shift   ;;
    --help|-h)
      sed -n '3,21p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) die "Unknown option: $1 (run with --help for usage)" ;;
  esac
done

# ── Platform detection ────────────────────────────────────────────────
OS="unknown"
ARCH="$(uname -m 2>/dev/null || echo unknown)"
case "$(uname -s 2>/dev/null)" in
  Darwin)                    OS="macos"   ;;
  Linux)                     OS="linux"   ;;
  MINGW*|MSYS*|CYGWIN*)     OS="windows" ;;
  *)
    # WSL reports Linux but WSLENV is set
    if [ -n "${WSL_DISTRO_NAME:-}" ] || [ -f /proc/version ] && grep -qi "microsoft" /proc/version 2>/dev/null; then
      OS="linux"  # treat WSL as Linux
    fi
    ;;
esac

PKG_MANAGER="none"
if [ "$OS" = "linux" ]; then
  if   command -v apt-get >/dev/null 2>&1; then PKG_MANAGER="apt"
  elif command -v dnf     >/dev/null 2>&1; then PKG_MANAGER="dnf"
  elif command -v yum     >/dev/null 2>&1; then PKG_MANAGER="yum"
  elif command -v pacman  >/dev/null 2>&1; then PKG_MANAGER="pacman"
  elif command -v zypper  >/dev/null 2>&1; then PKG_MANAGER="zypper"
  elif command -v brew    >/dev/null 2>&1; then PKG_MANAGER="brew"
  fi
elif [ "$OS" = "macos" ]; then
  if command -v brew >/dev/null 2>&1; then PKG_MANAGER="brew"; fi
fi

# ── Helpers ───────────────────────────────────────────────────────────
need_sudo() {
  [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && echo "sudo" || echo ""
}

node_major_version() {
  node --version 2>/dev/null | sed 's/v//' | cut -d. -f1
}

check_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# ── Node.js check / install ───────────────────────────────────────────
banner "Checking Node.js"

install_node() {
  info "Installing Node.js via $([ "$OS" = "macos" ] && echo "Homebrew" || echo "$PKG_MANAGER")…"
  case "$PKG_MANAGER" in
    brew)
      brew install node
      ;;
    apt)
      SUDO="$(need_sudo)"
      # Use NodeSource LTS repo for a recent version
      curl -fsSL https://deb.nodesource.com/setup_lts.x | $SUDO bash -
      $SUDO apt-get install -y nodejs
      ;;
    dnf)
      SUDO="$(need_sudo)"
      curl -fsSL https://rpm.nodesource.com/setup_lts.x | $SUDO bash -
      $SUDO dnf install -y nodejs
      ;;
    yum)
      SUDO="$(need_sudo)"
      curl -fsSL https://rpm.nodesource.com/setup_lts.x | $SUDO bash -
      $SUDO yum install -y nodejs
      ;;
    pacman)
      SUDO="$(need_sudo)"
      $SUDO pacman -Sy --noconfirm nodejs npm
      ;;
    zypper)
      SUDO="$(need_sudo)"
      $SUDO zypper install -y nodejs npm
      ;;
    *)
      warn "Cannot auto-install Node.js on this platform."
      warn "Please install Node.js ≥ ${MIN_NODE_MAJOR} from https://nodejs.org then re-run this script."
      exit 1
      ;;
  esac
}

if [ "$SKIP_NODE" -eq 0 ]; then
  if check_cmd node; then
    CURRENT_MAJOR="$(node_major_version)"
    if [ "${CURRENT_MAJOR:-0}" -lt "$MIN_NODE_MAJOR" ]; then
      warn "Node.js ${CURRENT_MAJOR} found but ≥ ${MIN_NODE_MAJOR} is required."
      install_node
    else
      success "Node.js v$(node --version | sed 's/v//') (≥ ${MIN_NODE_MAJOR} ✓)"
    fi
  else
    warn "Node.js not found."
    install_node
  fi
else
  info "Skipping Node.js check (--no-node)"
fi

# ── pnpm check / install ──────────────────────────────────────────────
banner "Checking pnpm"

if ! check_cmd pnpm; then
  info "Installing pnpm…"
  if check_cmd npm; then
    npm install -g pnpm
  elif check_cmd corepack; then
    corepack enable pnpm
  else
    curl -fsSL https://get.pnpm.io/install.sh | sh
    # Reload PATH for the rest of this script
    export PNPM_HOME="${HOME}/.local/share/pnpm"
    export PATH="${PNPM_HOME}:${PATH}"
  fi
fi

if check_cmd pnpm; then
  success "pnpm $(pnpm --version)"
else
  die "pnpm installation failed. Install manually: https://pnpm.io/installation"
fi

# ── GitHub CLI check / install ────────────────────────────────────────
banner "Checking GitHub CLI"

if [ "$SKIP_GH" -eq 0 ]; then
  if ! check_cmd gh; then
    info "Installing GitHub CLI…"
    case "$PKG_MANAGER" in
      brew)    brew install gh ;;
      apt)
        SUDO="$(need_sudo)"
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
          | $SUDO dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
          | $SUDO tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        $SUDO apt-get update && $SUDO apt-get install -y gh
        ;;
      dnf)     $(need_sudo) dnf install -y 'dnf-command(config-manager)' && \
               $(need_sudo) dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo && \
               $(need_sudo) dnf install -y gh ;;
      pacman)  $(need_sudo) pacman -Sy --noconfirm github-cli ;;
      *)
        warn "Cannot auto-install GitHub CLI on this platform."
        warn "Install from https://cli.github.com then run: gh auth login"
        SKIP_GH=1
        ;;
    esac
  fi

  if check_cmd gh; then
    success "gh $(gh --version | head -1 | awk '{print $3}')"
    if ! gh auth status >/dev/null 2>&1; then
      warn "GitHub CLI is installed but not authenticated."
      info "Run this after installation: ${BOLD}gh auth login${RESET}"
    else
      success "GitHub CLI authenticated ✓"
    fi
  fi
else
  info "Skipping GitHub CLI check (--no-gh)"
fi

# ── Clean install ────────────────────────────────────────────────────

clean_existing_install() {
  banner "Cleaning existing installation"

  # Files and directories written by previous installs
  CLEAN_TARGETS="
    ${INSTALL_DIR}/agem
    ${INSTALL_DIR}/agem.js
    ${INSTALL_DIR}/package.json
    ${INSTALL_DIR}/node_modules/@github/copilot
    ${INSTALL_DIR}/node_modules/better-sqlite3
    ${INSTALL_DIR}/node_modules/bindings
    ${INSTALL_DIR}/node_modules/file-uri-to-path
    ${HOME}/.agem
  "

  REMOVED=0
  for target in $CLEAN_TARGETS; do
    target="$(echo "$target" | tr -d ' ')"
    if [ -e "$target" ] || [ -L "$target" ]; then
      info "Removing: $target"
      rm -rf "$target"
      REMOVED=$((REMOVED + 1))
    fi
  done

  # Remove @github dir if now empty
  GH_DIR="${INSTALL_DIR}/node_modules/@github"
  if [ -d "$GH_DIR" ] && [ -z "$(ls -A "$GH_DIR" 2>/dev/null)" ]; then
    rmdir "$GH_DIR"
  fi
  NM_DIR="${INSTALL_DIR}/node_modules"
  if [ -d "$NM_DIR" ] && [ -z "$(ls -A "$NM_DIR" 2>/dev/null)" ]; then
    rmdir "$NM_DIR"
  fi

  if [ "$REMOVED" -eq 0 ]; then
    info "No existing installation found in ${INSTALL_DIR}"
  else
    success "Removed $REMOVED item(s) from ${INSTALL_DIR}"
  fi
}

if [ "$CLEAN_INSTALL" -eq 1 ]; then
  clean_existing_install
fi

# ── Fetch AgentEmerald release ────────────────────────────────────────
banner "Installing AgentEmerald"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if [ "$VERSION" = "latest" ]; then
  info "Fetching latest release info…"
  # Try gh first (avoids rate limits), fall back to curl
  if check_cmd gh && gh auth status >/dev/null 2>&1; then
    VERSION="$(gh release view --repo "$REPO" --json tagName -q .tagName 2>/dev/null || echo "")"
  fi
  if [ -z "$VERSION" ]; then
    VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
      | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')"
  fi
  if [ -z "$VERSION" ]; then
    warn "Could not determine latest release. Falling back to cloning main branch."
    VERSION="main"
  fi
fi

info "Installing version: ${BOLD}${VERSION}${RESET}"

# Check if git is available for cloning (preferred, handles symlinks correctly)
if check_cmd git; then
  info "Cloning repository…"
  git clone --depth 1 \
    $([ "$VERSION" != "main" ] && echo "--branch ${VERSION}") \
    "https://github.com/${REPO}.git" \
    "${WORK_DIR}/AgentEmerald" 2>&1 | grep -v "^Cloning into" || true
  REPO_DIR="${WORK_DIR}/AgentEmerald"
else
  die "git is required but not found. Please install git and re-run."
fi

info "Installing dependencies (this may take a minute)…"
cd "$REPO_DIR"
pnpm install --frozen-lockfile 2>&1 | tail -3

# Build native deps (better-sqlite3 requires a compile step that pnpm skips by default)
info "Building native dependencies…"
pnpm rebuild better-sqlite3 2>&1 | tail -3 || warn "better-sqlite3 native build failed — gateway SQLite persistence will be unavailable"

info "Building…"
pnpm run build 2>&1 | tail -3

info "Bundling…"
pnpm run bundle 2>&1 | tail -3

# ── Install binary ────────────────────────────────────────────────────
banner "Installing binary"

mkdir -p "$INSTALL_DIR"

# Copy bundle
cp "${REPO_DIR}/dist/agem.js" "${INSTALL_DIR}/agem.js"
chmod 755 "${INSTALL_DIR}/agem.js"

# Write package.json so Node treats the bundle as ESM without re-parsing
printf '{"type":"module"}\n' > "${INSTALL_DIR}/package.json"

# ── Native package helper ──────────────────────────────────────────────
# Copy a package from the project's pnpm store into $INSTALL_DIR/node_modules.
# We copy (not symlink) native packages because the `bindings` resolver walks
# up from __dirname; a symlink would misdirect the walk away from $INSTALL_DIR.

copy_package() {
  PKG_NAME="$1"   # e.g. "better-sqlite3" or "@github/copilot"
  PKG_SRC="$2"    # absolute path to the package root

  DEST_DIR="${INSTALL_DIR}/node_modules/${PKG_NAME}"
  DEST_PARENT="$(dirname "$DEST_DIR")"

  mkdir -p "$DEST_PARENT"
  if [ -e "$DEST_DIR" ]; then
    rm -rf "$DEST_DIR"
  fi
  cp -r "$PKG_SRC" "$DEST_DIR"
  info "Installed: node_modules/${PKG_NAME}"
}

# Find a package in the pnpm store
find_pnpm_pkg() {
  PKG="$1"  # e.g. "better-sqlite3"
  PNPM_STORE="${REPO_DIR}/node_modules/.pnpm"
  SAFE="${PKG##*/}"  # strip scope prefix for matching
  # Try exact match first, then prefix match
  find "$PNPM_STORE" -maxdepth 1 -type d -name "${SAFE}@*" | head -1
}

# ── @github/copilot (symlink — no native code) ─────────────────────────
COPILOT_SRC="${REPO_DIR}/node_modules/@github/copilot"
COPILOT_DEST_DIR="${INSTALL_DIR}/node_modules/@github"
mkdir -p "$COPILOT_DEST_DIR"
if [ -e "${COPILOT_DEST_DIR}/copilot" ]; then
  rm -rf "${COPILOT_DEST_DIR}/copilot"
fi
cp -r "$COPILOT_SRC" "${COPILOT_DEST_DIR}/copilot"
info "Installed: node_modules/@github/copilot"

# ── better-sqlite3 (native — must be a full copy) ─────────────────────
SQLITE_DIR="$(find_pnpm_pkg "better-sqlite3")"
if [ -n "$SQLITE_DIR" ]; then
  SQLITE_PKG="${SQLITE_DIR}/node_modules/better-sqlite3"
  if [ -d "$SQLITE_PKG" ]; then
    copy_package "better-sqlite3" "$SQLITE_PKG"
  fi
fi

# ── bindings (runtime dep of better-sqlite3) ──────────────────────────
BINDINGS_DIR="$(find_pnpm_pkg "bindings")"
if [ -n "$BINDINGS_DIR" ]; then
  BINDINGS_PKG="${BINDINGS_DIR}/node_modules/bindings"
  if [ -d "$BINDINGS_PKG" ]; then
    copy_package "bindings" "$BINDINGS_PKG"
  fi
fi

# ── file-uri-to-path (dep of bindings) ────────────────────────────────
FURI_DIR="$(find_pnpm_pkg "file-uri-to-path")"
if [ -n "$FURI_DIR" ]; then
  FURI_PKG="${FURI_DIR}/node_modules/file-uri-to-path"
  if [ -d "$FURI_PKG" ]; then
    copy_package "file-uri-to-path" "$FURI_PKG"
  fi
fi

# ── Onboarding presets (node-react, python, rust) ────────────────────
# Copy the presets/ tree so `/selfhost quickstart <preset>` works from the
# bundled binary. We copy rather than symlink so the install is self-contained.
if [ -d "${REPO_DIR}/presets" ]; then
  PRESETS_DEST="${INSTALL_DIR}/presets"
  rm -rf "$PRESETS_DEST"
  cp -r "${REPO_DIR}/presets" "$PRESETS_DEST"
  info "Installed: presets/"
fi

# Write launcher wrapper
cat > "${INSTALL_DIR}/agem" << 'WRAPPER'
#!/bin/sh
exec node "$(dirname "$0")/agem.js" "$@"
WRAPPER
chmod 755 "${INSTALL_DIR}/agem"

success "agem installed to ${INSTALL_DIR}"

# ── PATH check ────────────────────────────────────────────────────────
banner "Finalising"

path_contains() {
  case ":${PATH}:" in
    *":$1:"*) return 0 ;;
    *)        return 1 ;;
  esac
}

if ! path_contains "$INSTALL_DIR"; then
  warn "${INSTALL_DIR} is not in your PATH."
  printf "\n"
  info "Add this to your shell profile (${BOLD}~/.bashrc${RESET}, ${BOLD}~/.zshrc${RESET}, etc.):"
  printf "\n  ${CYAN}export PATH=\"\$HOME/bin:\$PATH\"${RESET}\n\n"
  info "Then reload: ${BOLD}source ~/.bashrc${RESET}  (or open a new terminal)"
else
  success "${INSTALL_DIR} is already in PATH ✓"
fi

# ── First-run setup ───────────────────────────────────────────────────
banner "First-run setup"

if [ ! -f "${HOME}/.agem/config.json" ]; then
  info "No config found — launching interactive setup wizard..."
  info "This will configure your LLM provider, execution mode, and optional chat channel integrations."
  printf "\n"
  "${INSTALL_DIR}/agem" || true
else
  info "Existing config found at ${HOME}/.agem/config.json — skipping setup."
  info "Run ${BOLD}/onboard${RESET} inside agem to re-run setup at any time."
fi

# ── Done ──────────────────────────────────────────────────────
printf "\n${BOLD}${GREEN}Agent Emerald is installed!${RESET}\n\n"

if ! gh auth status >/dev/null 2>&1 && [ "$SKIP_GH" -eq 0 ]; then
  printf "  ${YELLOW}1.${RESET} Authenticate with GitHub:  ${BOLD}gh auth login${RESET}\n"
  printf "  ${YELLOW}2.${RESET} Launch the TUI:            ${BOLD}agem${RESET}\n"
else
  printf "  ${GREEN}→${RESET} Launch the TUI:  ${BOLD}agem${RESET}\n"
fi

printf "\n  ${BOLD}Next steps${RESET}\n"
printf "    ${CYAN}/selfhost quickstart${RESET}           ${DIM}list built-in presets${RESET}\n"
printf "    ${CYAN}/selfhost quickstart node-react${RESET}${DIM}  seed config + instructions${RESET}\n"
printf "    ${CYAN}/provider${RESET}                       ${DIM}switch LLM backend (copilot, models, openai, anthropic, ollama, lmstudio)${RESET}\n"
printf "    ${CYAN}agem gateway start${RESET}              ${DIM}run headless daemon (WebSocket + HTTP)${RESET}\n"
printf "\n  ${BOLD}Execution modes${RESET}  ${DIM}(set via --mode or config.json)${RESET}\n"
printf "    ${DIM}auto-approve${RESET}  all tools run without confirmation\n"
printf "    ${DIM}normal${RESET}        write / shell tools require approval (default in configs)\n"
printf "    ${DIM}read-only${RESET}     blocks write / shell tools entirely\n"

printf "\n  ${DIM}Docs: https://github.com/${REPO}#readme${RESET}\n\n"
