#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# Security Tools Installer — Fedora
#
# ⚠  WARNING: @security-lab pulls in ~700 packages including an older
#     quickshell (0.2.x) that DOWNGRADES the Hyprland COPR version (0.3.x)
#     that dms-greeter requires.  After running this script you MUST:
#
#       sudo dnf install quickshell-0.3.1* --best
#       sudo dnf versionlock add quickshell-0:0.3.1*
#       sudo systemctl restart greetd
#
#     If greetd fails to start after installing security tools, this is
#     almost always the cause.  See: https://github.com/AvengeMedia/dms-greeter
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

# ─── Config ───────────────────────────────────────────────────────────────────
INSTALL_DIR="${INSTALL_DIR:-/opt/security-tools}"
WORDLISTS_DIR="${WORDLISTS_DIR:-/usr/share/wordlists}"
LOGFILE="${LOGFILE:-$HOME/install-security-tools.log}"

# ─── Helpers ─────────────────────────────────────────────────────────────────
info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*" >&2; }
error() { echo "[ERROR] $*" >&2; exit 1; }
log()   { "$@" 2>&1 | tee -a "$LOGFILE"; }

need_root() {
  if [[ $EUID -ne 0 ]]; then
    error "Run as root (or with sudo)"
  fi
}

ensure_dir() {
  if [[ ! -d "$1" ]]; then
    info "Creating $1"
    mkdir -p "$1"
  fi
}

load_cargo() {
  # shellcheck disable=SC1091
  # rustup-init installs to ~/.cargo and tells users to source ~/.cargo/env
  source "$HOME/.cargo/env" 2>/dev/null || true
  # Also try system-wide rustup profile (handles root installs)
  source /etc/profile.d/rustup.sh 2>/dev/null || true
  if [[ ":$PATH:" != *":$HOME/.cargo/bin:"* ]] && [[ -d "$HOME/.cargo/bin" ]]; then
    export PATH="$HOME/.cargo/bin:$PATH"
  fi
}

# ─── Pre-flight ───────────────────────────────────────────────────────────────
info "Security Tools Installer — Fedora"
info "Log: $LOGFILE"
echo

# ─── 1. DNF group: Security Lab ───────────────────────────────────────────────
info "=== Installing @security-lab DNF group ==="
dnf group install -y "security-lab"

# @security-lab ships desktop entries wrapping CLI tools in xfce4-terminal.
# Remove them — they're not useful for CLI tools.

# @security-lab downgrades quickshell from COPR 0.3.x to Fedora 0.2.x,
# which breaks dms-greeter.  Reinstall + lock the COPR version.
info "Fixing quickshell version (downgraded by @security-lab)..."
dnf install -y quickshell --best
dnf versionlock add quickshell-0:0.3.1* 2>/dev/null || true

# ─── 2. DNF packages ──────────────────────────────────────────────────────────
info "=== Installing DNF packages ==="
dnf install -y hashcat ffuf openvpn lftp pocl ocl-icd clinfo xfreerdp
dnf install -y python3-impacket

# ─── Impacket symlinks ────────────────────────────────────────────────────────
# impacket RPM installs scripts as *.py; create impacket-* symlinks (Kali style).
info "=== Creating impacket symlinks ==="
for script in \
  secretsdump wmiexec smbexec psexec lookupsid atexec dcomexec goldenPac \
  ntfsacls services relangelem smbclient mssqlclient rbcd Toolkit; do
  src="/usr/bin/${script}.py"
  dst="/usr/local/bin/impacket-${script}"
  if [[ -f "$src" && ! -e "$dst" ]]; then
    ln -sf "$src" "$dst"
    info "  impacket-$script → $src"
  fi
done

# ─── 3. SearchSploit (ExploitDB) ─────────────────────────────────────────────
info "=== Installing SearchSploit ==="
EXPLOITDB_DIR="/opt/exploitdb"
if [[ ! -d "$EXPLOITDB_DIR/.git" ]]; then
  rm -rf "$EXPLOITDB_DIR"
  git clone https://gitlab.com/exploit-database/exploitdb.git "$EXPLOITDB_DIR"
fi
if [[ ! -L /usr/local/bin/searchsploit ]]; then
  ln -sf "$EXPLOITDB_DIR/searchsploit" /usr/local/bin/searchsploit
fi
info "SearchSploit $(searchsploit --version 2>&1 | head -1) installed"

# ─── 4. Metasploit (Rapid7 RPM repo) ─────────────────────────────────────────
info "=== Setting up Metasploit ==="
MSF_REPO_FILE="/etc/yum.repos.d/metasploit.repo"
cat > "$MSF_REPO_FILE" << 'REPOFILE'
[metasploit]
name=Metasploit Framework
baseurl=https://rpm.metasploit.com/
enabled=1
gpgcheck=0
REPOFILE
dnf clean metadata
dnf makecache
dnf install -y metasploit-framework

# ─── 5. Feroxbuster ──────────────────────────────────────────────────────────
info "=== Installing Feroxbuster ==="
FRXBUST_VERSION="2.13.1"
FRXBUST_URL="https://github.com/epi052/feroxbuster/releases/download/v${FRXBUST_VERSION}/x86_64-linux-feroxbuster.tar.gz"
FRXBUST_TMP=$(mktemp -d)
curl -fsSL "$FRXBUST_URL" -o "$FRXBUST_TMP/feroxbuster.tar.gz"
tar -xzf "$FRXBUST_TMP/feroxbuster.tar.gz" -C /usr/local/bin/
rm -rf "$FRXBUST_TMP"
info "Feroxbuster $(/usr/local/bin/feroxbuster --version 2>&1 | head -1) installed"
info "=== Installing RustScan ==="
if ! command -v rustscan &>/dev/null; then
  /usr/bin/rustup-init -y
  load_cargo
  rustup default stable
  load_cargo
  if ! command -v cargo &>/dev/null; then
    error "cargo not found after rustup install. Try: source ~/.cargo/env && rustup default stable"
  fi
  cargo install rustscan 2>&1 | tail -3
  info "RustScan installed"
else
  info "RustScan already installed"
fi

# ─── 7. Gitleaks ─────────────────────────────────────────────────────────────
info "=== Installing Gitleaks ==="
GTLK_VERSION="v8.30.1"
GTLK_URL="https://github.com/gitleaks/gitleaks/releases/download/${GTLK_VERSION}/gitleaks_${GTLK_VERSION#v}_linux_x64.tar.gz"
GTLK_TMP=$(mktemp -d)
curl -fsSL "$GTLK_URL" -o "$GTLK_TMP/gitleaks.tar.gz"
tar -xzf "$GTLK_TMP/gitleaks.tar.gz" -C /usr/local/bin/
if [[ -f "/usr/local/bin/gitleaks" ]]; then
  chmod +x /usr/local/bin/gitleaks
  info "Gitleaks $(/usr/local/bin/gitleaks version) installed"
else
  tar -xzf "$GTLK_TMP/gitleaks.tar.gz" -C "$GTLK_TMP"
  find "$GTLK_TMP" -type f -name "gitleaks" -exec cp {} /usr/local/bin/gitleaks \; -exec chmod +x /usr/local/bin/gitleaks \; -exec true \;
  info "Gitleaks installed"
fi
rm -rf "$GTLK_TMP"

# ─── 8. SQLmap ────────────────────────────────────────────────────────────────
info "=== Installing SQLmap ==="
pip3 install -q --user sqlmap
ensure_dir "$HOME/.local/bin"
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  warn "Add $HOME/.local/bin to your PATH for sqlmap"
fi

# ─── 9. Pwncat ────────────────────────────────────────────────────────────────
info "=== Installing Pwncat ==="
pip3 install -q --user pwncat
if [[ ! -L /usr/local/bin/pwncat ]]; then
  ln -sf "$HOME/.local/bin/pwncat" /usr/local/bin/pwncat
fi

# ─── 10. WPScan (Ruby gem) ───────────────────────────────────────────────────
info "=== Installing WPScan ==="
dnf install -y ruby-devel
gem install -N wpscan

# ─── 11. Burp Suite Community ───────────────────────────────────────────────
info "=== Installing Burp Suite Community ==="
BURP_DIR="/opt/BurpSuiteCommunity"

# Check if Burp Suite JAR file exists (only after successful install)
burp_check() {
  [[ -f "$BURP_DIR/burpsuite_community.jar" ]]
}

if burp_check; then
  info "Burp Suite already installed at $BURP_DIR"
else
  info "Downloading Burp Suite Community..."
  curl -fsSL "https://portswigger.net/Burp/releases/download?product=community&type=Linux" -o /tmp/burpsuite_community.sh
  chmod +x /tmp/burpsuite_community.sh
  /tmp/burpsuite_community.sh
  rm -f /tmp/burpsuite_community.sh

  # Create symlink for easier access
  ln -sf "$BURP_DIR/BurpSuiteCommunity" /usr/local/bin/burpsuite
  # Create desktop entry
  cat > /usr/share/applications/burpsuite.desktop << 'EOF'
[Desktop Entry]
Name=Burp Suite Community
Comment=Web vulnerability scanner and proxy
Exec=/usr/local/bin/BurpSuiteCommunity
Icon=/usr/local/BurpSuiteCommunity/burp-128x128.png
Terminal=false
Type=Application
Categories=Security;Network;Development;
EOF
  info "Desktop entry created"
fi
info "=== Installing Kali wordlists ==="
ensure_dir "$WORDLISTS_DIR"
WL_TMP=$(mktemp -d)

info "Downloading Kali wordlists…"
KALIWL_URL="https://github.com/00xBAD/kali-wordlists/archive/refs/heads/master.tar.gz"
curl -fsSL "$KALIWL_URL" -o "$WL_TMP/kali-wordlists.tar.gz"
tar -xzf "$WL_TMP/kali-wordlists.tar.gz" -C "$WL_TMP"
cp -r "$WL_TMP/kali-wordlists-master/"* "$WORDLISTS_DIR/"
info "Kali wordlists installed"

info "Downloading rockyou.txt…"
curl -fsSL "https://gitlab.com/kalilinux/packages/wordlists/raw/kali/master/rockyou.txt.gz" \
  -o "$WL_TMP/rockyou.txt.gz"
gunzip -f "$WL_TMP/rockyou.txt.gz" -c > "$WORDLISTS_DIR/rockyou.txt"
info "rockyou.txt installed ($(wc -l < "$WORDLISTS_DIR/rockyou.txt") lines)"

rm -rf "$WL_TMP"
info "Wordlists installed to $WORDLISTS_DIR"
ls "$WORDLISTS_DIR"

# ─── Done ─────────────────────────────────────────────────────────────────────
echo
info "=== Installation complete ==="
info "Tools available:"
printf "  %-20s %s\n" "feroxbuster"   "$(command -v feroxbuster 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "ffuf"          "$(command -v ffuf 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "openvpn"       "$(command -v openvpn 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "burpsuite"     "$(command -v burpsuite 2>/dev/null || test -d /usr/local/BurpSuiteCommunity && echo '/usr/local/BurpSuiteCommunity' || echo 'not found')"
printf "  %-20s %s\n" "gitleaks"      "$(command -v gitleaks 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "sqlmap"        "$(command -v sqlmap 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "pwncat"        "$(command -v pwncat 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "wpscan"        "$(command -v wpscan 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "burpsuite"     "$(flatpak info net.portswigger.BurpSuite-Community 2>/dev/null || echo 'flatpak installed')"
printf "  %-20s %s\n" "searchsploit"  "$(command -v searchsploit 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "hashcat"       "$(command -v hashcat 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "msfconsole"    "$(command -v msfconsole 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "lftp"          "$(command -v lftp 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "xfreerdp"      "$(command -v xfreerdp 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "impacket-secretsdump" "$(command -v impacket-secretsdump 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "wordlists"     "$(ls $WORDLISTS_DIR 2>/dev/null | head -1 && echo '...' || echo 'not found')"
info "Log saved to: $LOGFILE"
