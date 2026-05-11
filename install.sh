#!/usr/bin/env bash
# Chiron daemon installer.
#
# Installs the chiron binary for your OS + arch. Downloads the latest
# release tarball from this repo, verifies its SHA256 against the
# release's `checksums.txt`, then drops the binary at /usr/local/bin
# (or ~/.local/bin if /usr/local/bin is not writable).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/constantinostrada/chiron-releases/main/install.sh | bash
#
# After installation:
#   chiron setup --code <CHIR-XXXX> --server <https://your-manager>
#   chiron start
#
# Optional: install Ollama to enable local semantic search over your
# accumulated knowledge:
#   brew install ollama && ollama pull nomic-embed-text
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
REPO="constantinostrada/chiron-releases"
GITHUB_API="https://api.github.com/repos/$REPO"
GITHUB_DL="https://github.com/$REPO/releases/download"

# Colors (disabled when not a terminal)
if [ -t 1 ] || [ -t 2 ]; then
  BOLD='\033[1m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  RED='\033[0;31m'
  CYAN='\033[0;36m'
  DIM='\033[2m'
  RESET='\033[0m'
else
  BOLD='' GREEN='' YELLOW='' RED='' CYAN='' DIM='' RESET=''
fi

info()  { printf "${BOLD}${CYAN}==>${RESET} %s\n" "$*"; }
ok()    { printf "${BOLD}${GREEN}✓${RESET} %s\n" "$*"; }
warn()  { printf "${BOLD}${YELLOW}⚠${RESET} %s\n" "$*" >&2; }
fail()  { printf "${BOLD}${RED}✗${RESET} %s\n" "$*" >&2; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Detect platform
# ---------------------------------------------------------------------------
detect_platform() {
  # OS / ARCH are exposed globally (not `local`) so downstream helpers like
  # install_ollama_now() can branch on $OS without re-detecting. Under
  # `set -u` an unset $OS in the Ollama path triggers an "unbound variable"
  # fatal — we hit that before this fix.
  case "$(uname -s)" in
    Darwin) OS="darwin" ;;
    Linux)  OS="linux" ;;
    MINGW*|MSYS*|CYGWIN*)
      fail "Windows is not yet supported by this installer. Download chiron-windows-x64.zip from
   https://github.com/$REPO/releases/latest manually for now." ;;
    *)
      fail "Unsupported OS: $(uname -s)" ;;
  esac

  case "$(uname -m)" in
    x86_64|amd64) ARCH="x64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *)
      fail "Unsupported architecture: $(uname -m). Chiron supports x64 and arm64." ;;
  esac

  PLATFORM="${OS}-${ARCH}"
}

# ---------------------------------------------------------------------------
# Resolve the latest release tag
# ---------------------------------------------------------------------------
fetch_latest_tag() {
  # Follow the redirect from /releases/latest — gives us the tag without
  # needing GitHub API auth (anonymous API calls have 60/hour rate limit).
  local redirect
  redirect=$(curl -sI "https://github.com/$REPO/releases/latest" 2>/dev/null \
    | grep -i '^location:' \
    | sed 's/.*tag\///' \
    | tr -d '\r\n')
  if [ -z "$redirect" ]; then
    fail "Could not resolve the latest release tag from
   https://github.com/$REPO/releases/latest
Check your network connection or the repo URL."
  fi
  TAG="$redirect"
}

# ---------------------------------------------------------------------------
# Download binary tarball + checksum, verify, extract
# ---------------------------------------------------------------------------
download_and_verify() {
  local tarball="chiron-${PLATFORM}.tar.gz"
  local tarball_url="$GITHUB_DL/$TAG/$tarball"
  local checksums_url="$GITHUB_DL/$TAG/checksums.txt"

  TMP_DIR="$(mktemp -d)"
  trap "rm -rf '$TMP_DIR'" EXIT

  info "Downloading $tarball ..."
  if ! curl -fsSL "$tarball_url" -o "$TMP_DIR/$tarball"; then
    fail "Failed to download $tarball_url. Maybe this release does not have a binary
for your platform (${PLATFORM})?"
  fi

  info "Downloading checksums.txt ..."
  if ! curl -fsSL "$checksums_url" -o "$TMP_DIR/checksums.txt"; then
    warn "Could not download checksums.txt — skipping integrity verification."
  else
    info "Verifying SHA-256 ..."
    # Pull just the line for our tarball, hand it to shasum -c with --strict
    # so any malformed entry is rejected. shasum -c expects "<hash>  <file>"
    # format which is what `shasum -a 256` emits.
    if ! ( cd "$TMP_DIR" && grep " $tarball\$" checksums.txt | shasum -a 256 -c --strict >/dev/null 2>&1 ); then
      fail "Checksum verification failed for $tarball. Do not run the downloaded binary —
the file may be corrupted or tampered."
    fi
    ok "Checksum OK"
  fi

  info "Extracting ..."
  ( cd "$TMP_DIR" && tar xzf "$tarball" )
  BINARY_PATH="$TMP_DIR/chiron-${PLATFORM}"
  [ -f "$BINARY_PATH" ] || fail "Extracted tarball did not contain chiron-${PLATFORM}"
  chmod +x "$BINARY_PATH"
}

# ---------------------------------------------------------------------------
# Install to /usr/local/bin (or ~/.local/bin fallback)
# ---------------------------------------------------------------------------
install_binary() {
  local target=""

  if [ -w "/usr/local/bin" ]; then
    target="/usr/local/bin/chiron"
    mv "$BINARY_PATH" "$target"
  elif command_exists sudo; then
    # Pre-announce: the next line will trigger sudo's password prompt. Without
    # this warning, the password input appears unexpectedly mid-install which
    # is confusing and looks like a hang. The pre-announce gives the user a
    # second to recognize it's coming.
    printf "\n${BOLD}${YELLOW}⚠${RESET}  ${BOLD}sudo password required${RESET} to install chiron to ${CYAN}/usr/local/bin${RESET}.\n"
    printf "   ${DIM}(Skip sudo by re-running as a user with /usr/local/bin write access,\n"
    printf "    or chiron will fall back to ${CYAN}~/.local/bin${RESET}${DIM} on the next attempt.)${RESET}\n\n"
    if sudo mv "$BINARY_PATH" "/usr/local/bin/chiron"; then
      target="/usr/local/bin/chiron"
    fi
  fi

  if [ -z "$target" ]; then
    target="$HOME/.local/bin/chiron"
    mkdir -p "$HOME/.local/bin"
    mv "$BINARY_PATH" "$target"
    if ! echo "$PATH" | tr ':' '\n' | grep -q "^$HOME/.local/bin\$"; then
      warn "$HOME/.local/bin is not on your PATH. Add this to your shell config:"
      printf "    ${CYAN}export PATH=\"\$HOME/.local/bin:\$PATH\"${RESET}\n"
    fi
  fi

  INSTALL_PATH="$target"
}

# ---------------------------------------------------------------------------
# Ollama detection + optional install
#
# Chiron's daemon optionally uses Ollama (running locally) to add vector
# embeddings on top of keyword search. The daemon auto-detects Ollama at
# runtime and gracefully falls back to BM25 if it's not reachable — but
# from the installer's perspective we can shorten the path-to-value by
# detecting the user's current state and prompting only when useful.
#
# The four states we react to:
#
#   ready                 — Ollama up + nomic-embed-text pulled. Nothing to do.
#   running_no_model      — Ollama up but model missing. Offer to pull it.
#   installed_not_running — Binary on PATH but server not responding. Hint
#                           the start command instead of re-installing.
#   missing               — No Ollama at all. Offer to install via the
#                           platform-native installer (brew on macOS,
#                           ollama.com script on Linux).
#
# Two env vars short-circuit the interactive prompts (for CI / scripted runs):
#   OLLAMA=skip   → never prompt, never install. Daemon will run BM25-only.
#   OLLAMA=yes    → assume yes to every prompt (install + pull if needed).
# ---------------------------------------------------------------------------

OLLAMA_MODEL="${OLLAMA_MODEL:-nomic-embed-text}"
OLLAMA_HOST="${OLLAMA_HOST:-http://localhost:11434}"

detect_ollama_state() {
  if ! command_exists ollama; then
    OLLAMA_STATE="missing"
    return
  fi
  # Binary present — check whether the daemon HTTP API responds. 2-second
  # timeout is enough to distinguish "not running" from "starting up".
  if ! curl -sf -m 2 "$OLLAMA_HOST/api/tags" >/dev/null 2>&1; then
    OLLAMA_STATE="installed_not_running"
    return
  fi
  # Server is up — check whether our preferred model is present. Match
  # both bare name and `:tag` variants (e.g. `nomic-embed-text:latest`).
  local tags
  tags=$(curl -sf -m 2 "$OLLAMA_HOST/api/tags" 2>/dev/null || echo "")
  if printf '%s' "$tags" | grep -q "\"name\":\"${OLLAMA_MODEL}"; then
    OLLAMA_STATE="ready"
  else
    OLLAMA_STATE="running_no_model"
  fi
}

# Y/N prompt that reads from the controlling terminal (works under
# `curl | bash` because stdin is the pipe, not the keyboard). Honors
# the OLLAMA env var to short-circuit interactive runs.
#
#   $1 = prompt text
#   $2 = default ("y" or "n") — what Enter alone means
#
# Sets OLLAMA_REPLY to "yes" or "no".
prompt_yn() {
  local prompt="$1"
  local default="$2"
  local hint
  case "$default" in
    y|Y) hint="[Y/n]" ;;
    *)   hint="[y/N]" ;;
  esac

  if [ "${OLLAMA:-}" = "skip" ] || [ "${OLLAMA:-}" = "no" ]; then
    OLLAMA_REPLY="no"
    return
  fi
  if [ "${OLLAMA:-}" = "yes" ]; then
    OLLAMA_REPLY="yes"
    return
  fi

  if [ ! -e /dev/tty ]; then
    # Non-interactive (e.g. piped without a controlling terminal). Use
    # the default to keep the install moving rather than hanging.
    OLLAMA_REPLY=$([ "$default" = "y" ] || [ "$default" = "Y" ] && echo "yes" || echo "no")
    return
  fi

  printf "  %s %s " "$prompt" "$hint"
  local answer
  read -r answer < /dev/tty || answer=""
  case "$answer" in
    y|Y|yes) OLLAMA_REPLY="yes" ;;
    "")      OLLAMA_REPLY=$([ "$default" = "y" ] || [ "$default" = "Y" ] && echo "yes" || echo "no") ;;
    *)       OLLAMA_REPLY="no" ;;
  esac
}

install_ollama_now() {
  case "$OS" in
    darwin)
      if ! command_exists brew; then
        warn "Homebrew not found. Install Ollama manually from https://ollama.com,
   then run: ollama pull ${OLLAMA_MODEL}"
        return 1
      fi
      info "Installing Ollama via Homebrew (this may take a minute)..."
      brew install ollama >/dev/null 2>&1 || {
        warn "brew install ollama failed. Install manually from https://ollama.com."
        return 1
      }
      # brew installs a `brew services` agent but doesn't start it.
      brew services start ollama >/dev/null 2>&1 || true
      # Give the server a moment to come up before pulling.
      sleep 2
      ;;
    linux)
      info "Installing Ollama via the official script (https://ollama.com/install.sh)..."
      if ! curl -fsSL https://ollama.com/install.sh | sh; then
        warn "Ollama install script failed. Install manually from https://ollama.com."
        return 1
      fi
      ;;
    *)
      warn "Unsupported OS for automatic Ollama install. Install manually from https://ollama.com."
      return 1
      ;;
  esac
  ok "Ollama installed"
  return 0
}

start_ollama_service() {
  case "$OS" in
    darwin)
      if command_exists brew; then
        info "Starting Ollama via \`brew services start ollama\`..."
        if brew services start ollama >/dev/null 2>&1; then
          # Service registration succeeds quickly; the actual server takes a
          # moment. Wait up to ~5s for the API to respond before giving up.
          local attempts=0
          while [ $attempts -lt 10 ]; do
            if curl -sf "${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
              return 0
            fi
            sleep 0.5
            attempts=$((attempts + 1))
          done
          warn "Service registered but the API didn't respond on ${OLLAMA_HOST}. Check: brew services list"
          return 1
        fi
        warn "\`brew services start ollama\` failed. Start manually with: ollama serve"
        return 1
      fi
      warn "Homebrew not available. Start manually with: ollama serve"
      return 1
      ;;
    linux)
      if command_exists systemctl && systemctl list-unit-files 2>/dev/null | grep -q '^ollama'; then
        info "Starting Ollama via systemctl..."
        if sudo systemctl start ollama >/dev/null 2>&1; then
          sleep 2
          return 0
        fi
      fi
      warn "Couldn't auto-start. Start manually in another terminal with: ollama serve"
      return 1
      ;;
    *)
      warn "Auto-start not supported on this OS. Start manually with: ollama serve"
      return 1
      ;;
  esac
}

pull_ollama_model() {
  info "Pulling ${OLLAMA_MODEL} model (~270MB, takes a minute)..."
  if ollama pull "$OLLAMA_MODEL"; then
    ok "Model ${OLLAMA_MODEL} ready"
    return 0
  fi
  warn "Failed to pull ${OLLAMA_MODEL}. You can retry later with: ollama pull ${OLLAMA_MODEL}"
  return 1
}

handle_ollama() {
  detect_ollama_state

  case "$OLLAMA_STATE" in
    ready)
      ok "Ollama detected with ${OLLAMA_MODEL} — semantic search ready"
      ;;
    running_no_model)
      printf "\n${BOLD}? Ollama is running but the ${OLLAMA_MODEL} model isn't pulled yet.${RESET}\n"
      printf "  ${DIM}This is the model chiron uses for vector search over your knowledge.${RESET}\n"
      prompt_yn "Pull it now? (~270MB)" "y"
      if [ "$OLLAMA_REPLY" = "yes" ]; then
        pull_ollama_model
      else
        info "Skipping. The daemon will run BM25-only until you pull it:
    ollama pull ${OLLAMA_MODEL}"
      fi
      ;;
    installed_not_running)
      printf "\n${BOLD}${YELLOW}ℹ${RESET} ${BOLD}Ollama is installed but not running.${RESET}\n"
      printf "  ${DIM}The daemon talks to Ollama over localhost:11434 for vector search.${RESET}\n"
      printf "  ${DIM}It needs the service running — \`chiron start\` won't start it for you.${RESET}\n"
      prompt_yn "Start it now in the background?" "y"
      if [ "$OLLAMA_REPLY" = "yes" ]; then
        if start_ollama_service; then
          ok "Ollama started"
          # Re-detect: maybe the model is already pulled from a previous run.
          detect_ollama_state
          if [ "$OLLAMA_STATE" = "running_no_model" ]; then
            prompt_yn "Pull ${OLLAMA_MODEL} now? (~270MB)" "y"
            if [ "$OLLAMA_REPLY" = "yes" ]; then
              pull_ollama_model
            fi
          fi
        fi
      else
        info "Skipping. Start it later with one of these:"
        if [ "$OS" = "darwin" ]; then
          printf "    ${CYAN}brew services start ollama${RESET}   ${DIM}(background)${RESET}\n"
        fi
        printf "    ${CYAN}ollama serve${RESET}                  ${DIM}(foreground, separate terminal)${RESET}\n"
      fi
      ;;
    missing)
      printf "\n${BOLD}Optional:${RESET} install Ollama for semantic search.\n"
      printf "  ${DIM}Without Ollama the daemon works fine with keyword search (BM25).${RESET}\n"
      printf "  ${DIM}Installing it adds local vector embeddings — the agent finds entries${RESET}\n"
      printf "  ${DIM}by meaning, not just exact words. Runs 100%% on this machine.${RESET}\n"
      prompt_yn "Install Ollama now?" "n"
      if [ "$OLLAMA_REPLY" = "yes" ]; then
        if install_ollama_now; then
          pull_ollama_model
        fi
      else
        info "Skipping. Install later with:"
        if [ "$OS" = "darwin" ]; then
          printf "    ${CYAN}brew install ollama && ollama pull ${OLLAMA_MODEL}${RESET}\n"
        else
          printf "    ${CYAN}curl -fsSL https://ollama.com/install.sh | sh${RESET}\n"
          printf "    ${CYAN}ollama pull ${OLLAMA_MODEL}${RESET}\n"
        fi
      fi
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  printf "\n${BOLD}  Chiron daemon installer${RESET}\n\n"

  detect_platform
  ok "Detected platform: ${PLATFORM}"

  fetch_latest_tag
  ok "Latest release: ${TAG}"

  download_and_verify
  install_binary
  ok "Installed at ${INSTALL_PATH}"

  if ! command_exists chiron; then
    warn "chiron is installed but not yet on PATH in this shell session.
Open a new terminal or re-source your shell config to pick it up."
  fi

  printf "\n${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
  printf "${BOLD}${GREEN}  ✓ Chiron daemon is ready!${RESET}\n"
  printf "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n\n"

  # Detect Ollama state + interactive prompts. Skipped entirely when the
  # user sets OLLAMA=skip; default-y vs default-n depends on current state.
  handle_ollama

  # Agnostic next-step copy. The user might be:
  #   (a) already on the wizard's Pair-Daemon step (came here via "click here
  #       to install" hint) — they just need the setup line + chiron start.
  #   (b) starting fresh from documentation — they'll find the wizard on
  #       their own; we just point them at it without prescribing 5 steps
  #       they may already be past.
  printf "\n${BOLD}Next:${RESET} from your Chiron board's ${BOLD}Pair Daemon${RESET} step,\n"
  printf "copy the ${CYAN}chiron setup --code ... --server ...${RESET} line and run it here.\n"
  printf "Then run ${CYAN}chiron start${RESET} to begin polling for tasks.\n\n"
  printf "${DIM}New to Chiron? Open the board → ${CYAN}+ New Agent${RESET}${DIM} → ${CYAN}Local runtime (daemon)${RESET}${DIM} to get the setup line.${RESET}\n\n"
}

main "$@"
