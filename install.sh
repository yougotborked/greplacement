#!/usr/bin/env bash
# greplacement installer
# Usage: curl -sfL https://raw.githubusercontent.com/yougotborked/greplacement/main/install.sh | bash
set -euo pipefail

REPO="https://raw.githubusercontent.com/yougotborked/greplacement/main"
INSTALL_DIR="${GREPLACEMENT_INSTALL_DIR:-$HOME/.local/bin}"
RG_MIN_VERSION="13.0.0"

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

die() { red "error: $*" >&2; exit 1; }

# ── Detect OS ─────────────────────────────────────────────────────────────────
OS="$(uname -s)"
ARCH="$(uname -m)"

echo ""
bold "greplacement installer"
echo "  OS: $OS / $ARCH"
echo "  Install dir: $INSTALL_DIR"
echo ""

# ── Ensure ripgrep is present ─────────────────────────────────────────────────
install_ripgrep() {
    echo "→ Installing ripgrep..."
    case "$OS" in
        Linux)
            if command -v apt-get &>/dev/null; then
                sudo apt-get install -y ripgrep
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y ripgrep
            elif command -v yum &>/dev/null; then
                sudo yum install -y ripgrep
            elif command -v pacman &>/dev/null; then
                sudo pacman -S --noconfirm ripgrep
            elif command -v zypper &>/dev/null; then
                sudo zypper install -y ripgrep
            elif command -v apk &>/dev/null; then
                sudo apk add ripgrep
            else
                # Fallback: download binary from GitHub releases
                install_rg_binary
            fi
            ;;
        Darwin)
            if command -v brew &>/dev/null; then
                brew install ripgrep
            elif command -v port &>/dev/null; then
                sudo port install ripgrep
            else
                install_rg_binary
            fi
            ;;
        *)
            install_rg_binary
            ;;
    esac
}

install_rg_binary() {
    local rg_version
    rg_version=$(curl -sfL "https://api.github.com/repos/BurntSushi/ripgrep/releases/latest" \
        | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
    local rg_url

    case "$OS-$ARCH" in
        Linux-x86_64)   rg_url="https://github.com/BurntSushi/ripgrep/releases/download/${rg_version}/ripgrep-${rg_version}-x86_64-unknown-linux-musl.tar.gz" ;;
        Linux-aarch64)  rg_url="https://github.com/BurntSushi/ripgrep/releases/download/${rg_version}/ripgrep-${rg_version}-aarch64-unknown-linux-gnu.tar.gz" ;;
        Darwin-x86_64)  rg_url="https://github.com/BurntSushi/ripgrep/releases/download/${rg_version}/ripgrep-${rg_version}-x86_64-apple-darwin.tar.gz" ;;
        Darwin-arm64)   rg_url="https://github.com/BurntSushi/ripgrep/releases/download/${rg_version}/ripgrep-${rg_version}-aarch64-apple-darwin.tar.gz" ;;
        *)              die "No pre-built ripgrep binary for $OS-$ARCH. Install ripgrep manually: https://github.com/BurntSushi/ripgrep#installation" ;;
    esac

    local tmp
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    echo "→ Downloading ripgrep $rg_version..."
    curl -sfL "$rg_url" | tar -xz -C "$tmp"
    local rg_bin
    rg_bin=$(find "$tmp" -name "rg" -type f | head -1)
    [[ -z "$rg_bin" ]] && die "Could not find rg binary in downloaded archive."
    mkdir -p "$INSTALL_DIR"
    cp "$rg_bin" "$INSTALL_DIR/rg"
    chmod +x "$INSTALL_DIR/rg"
    green "→ ripgrep installed to $INSTALL_DIR/rg"
}

if ! command -v rg &>/dev/null; then
    install_ripgrep
fi

# Verify rg works
rg --version &>/dev/null || die "ripgrep installation failed or rg not in PATH."
echo "✓ ripgrep $(rg --version | head -1)"

# ── Find rg path and embed in shim ────────────────────────────────────────────
RG_PATH="$(command -v rg)"
GREP_PATH="$(command -v grep 2>/dev/null || true)"
# Prefer system grep over our own shim for the fallback path
if [[ "$GREP_PATH" == "$INSTALL_DIR/grep" ]]; then
    # Our shim is already there; find the real grep
    GREP_PATH="$(command -v grep -a 2>/dev/null | grep -v "$INSTALL_DIR" | head -1)" || GREP_PATH="/usr/bin/grep"
fi
GREP_PATH="${GREP_PATH:-/usr/bin/grep}"

# ── Install the shim ──────────────────────────────────────────────────────────
echo "→ Downloading greplacement shim..."
mkdir -p "$INSTALL_DIR"

TMP_SHIM=$(mktemp)
trap 'rm -f "$TMP_SHIM"' EXIT
curl -sfL "$REPO/greplacement" -o "$TMP_SHIM"

# Patch in the correct rg and grep paths
sed -i "s|^REAL_GREP=.*|REAL_GREP=$GREP_PATH|" "$TMP_SHIM"
sed -i "s|^REAL_RG=.*|REAL_RG=$RG_PATH|" "$TMP_SHIM"

cp "$TMP_SHIM" "$INSTALL_DIR/grep"
chmod +x "$INSTALL_DIR/grep"

green "✓ greplacement installed to $INSTALL_DIR/grep"

# ── PATH check ────────────────────────────────────────────────────────────────
add_to_path() {
    local shell_rc="$1"
    local export_line='export PATH="$HOME/.local/bin:$PATH"'
    if ! grep -qF 'local/bin' "$shell_rc" 2>/dev/null; then
        echo "" >> "$shell_rc"
        echo "# greplacement: put ~/.local/bin before system PATH" >> "$shell_rc"
        echo "$export_line" >> "$shell_rc"
        echo "→ Added PATH update to $shell_rc"
    fi
}

if [[ "$INSTALL_DIR" == "$HOME/.local/bin" ]]; then
    case "$SHELL" in
        */bash) add_to_path "$HOME/.bashrc" ;;
        */zsh)  add_to_path "$HOME/.zshrc" ;;
    esac
    # Also try the other one
    [[ -f "$HOME/.bashrc" ]] && add_to_path "$HOME/.bashrc"
    [[ -f "$HOME/.zshrc" ]]  && add_to_path "$HOME/.zshrc"
fi

# ── Verify ────────────────────────────────────────────────────────────────────
export PATH="$INSTALL_DIR:$PATH"
if [[ "$(command -v grep)" == "$INSTALL_DIR/grep" ]]; then
    green "✓ grep in PATH resolves to greplacement"
else
    echo ""
    echo "  ⚠ Reload your shell or run:"
    echo "      export PATH=\"$INSTALL_DIR:\$PATH\""
    echo ""
fi

echo ""
bold "Installation complete!"
echo ""
echo "  grep is now backed by ripgrep. All existing grep commands work unchanged."
echo "  Unsupported flags (BRE -G, null-data -z) fall back to the real grep."
echo ""
echo "  Uninstall: rm $INSTALL_DIR/grep"
echo ""
