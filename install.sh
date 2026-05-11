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
  local os arch

  case "$(uname -s)" in
    Darwin) os="darwin" ;;
    Linux)  os="linux" ;;
    MINGW*|MSYS*|CYGWIN*)
      fail "Windows is not yet supported by this installer. Download chiron-windows-x64.zip from
   https://github.com/$REPO/releases/latest manually for now." ;;
    *)
      fail "Unsupported OS: $(uname -s)" ;;
  esac

  case "$(uname -m)" in
    x86_64|amd64) arch="x64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
      fail "Unsupported architecture: $(uname -m). Chiron supports x64 and arm64." ;;
  esac

  PLATFORM="${os}-${arch}"
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
    info "/usr/local/bin needs sudo. You'll be prompted for your password ..."
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

  printf "${BOLD}Next step:${RESET} pair this daemon with your manager.\n"
  printf "Run the ${CYAN}chiron setup ...${RESET} command shown in the wizard.\n\n"

  printf "${BOLD}Optional:${RESET} enable local semantic search over your knowledge\n"
  printf "  ${CYAN}brew install ollama && ollama pull nomic-embed-text${RESET}\n"
  printf "  ${DIM}(Without Ollama the daemon still works using BM25-only keyword search.)${RESET}\n\n"
}

main "$@"
