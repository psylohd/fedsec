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
dnf install -y python3-devel python3-pytest

# ─── LDAP client tools (ldapsearch, ldapwhoami, ldapadd, …) ──────────────────
info "=== Installing LDAP client tools ==="
dnf install -y openldap-clients

# ─── Impacket shebang fix ──────────────────────────────────────────────────────
# Fedora's python3-impacket RPM ships scripts with a corrupted shebang
# (#!/usr/bin/python3 -sP -sP) that breaks execution. Fix it.
info "Patching corrupted impacket shebangs..."
grep -l '#!/usr/bin/python3 -sP -sP' /usr/bin/*.py 2>/dev/null | while read -r f; do
  sudo sed -i '1s|#!/usr/bin/python3 -sP -sP|#!/usr/bin/python3 -s|' "$f" && info "  fixed $f" || warn "  failed to fix $f"
done

dnf install -y python3-impacket

# ─── NetExec ─────────────────────────────────────────────────────────────────
info "=== Installing NetExec ==="
NETEXEC_DIR="/tmp/NetExec"
if [[ ! -d "$NETEXEC_DIR/.git" ]]; then
  git clone --depth 1 https://github.com/Pennyw0rth/NetExec.git "$NETEXEC_DIR"
fi
pip3 install -e "$NETEXEC_DIR"
info "NetExec $(command -v nxc >/dev/null && nxc --version 2>&1 | head -1 || echo 'installed')"
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

info "=== Installing crackmapexec (PyPI) ==="
pip3 install -q crackmapexec
info "crackmapexec $(command -v crackmapexec >/dev/null && crackmapexec --version 2>&1 | head -1 || echo 'installed')"
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

# ─── 3b. PayloadsAllTheThings ────────────────────────────────────────────────
info "=== Installing PayloadsAllTheThings ==="
PAYLOADS_DIR="/usr/share/payloadsallthethings"
if [[ ! -d "$PAYLOADS_DIR/.git" ]]; then
  rm -rf "$PAYLOADS_DIR"
  git clone --depth 1 https://github.com/swisskyrepo/PayloadsAllTheThings.git "$PAYLOADS_DIR"
fi
if [[ ! -L /usr/local/bin/payloadsallthethings ]]; then
  ln -sf "$PAYLOADS_DIR" /usr/local/bin/payloadsallthethings
fi

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
# ─── 10. BloodHound ─────────────────────────────────────────────────────────
info "=== Installing BloodHound ==="
BLOODHOUND_TMP=$(mktemp -d)
BLOODHOUND_URL="https://github.com/SpecterOps/bloodhound-cli/releases/latest/download/bloodhound-cli-linux-amd64.tar.gz"
curl -fsSL "$BLOODHOUND_URL" -o "$BLOODHOUND_TMP/bloodhound-cli.tar.gz"
tar -xvzf "$BLOODHOUND_TMP/bloodhound-cli.tar.gz" -C "$BLOODHOUND_TMP"
sudo "$BLOODHOUND_TMP/bloodhound-cli" install
rm -rf "$BLOODHOUND_TMP"
info "BloodHound installed"
# ─── 10b. BloodHound Python packages ─────────────────────────────────────────
info "=== Installing BloodHound Python packages ==="
pip3 install -q --user bloodhound
pip3 install -q --user bloodhound-ce

# ─── 11. WPScan (Ruby gem) ───────────────────────────────────────────────────
info "=== Installing WPScan ==="
dnf install -y ruby-devel
gem install -N evil-winrm
pip3 install -q --user responder

# ─── 12. Burp Suite Community ───────────────────────────────────────────────
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
# ─── John Jumbo (ssh2john, gpg2john, etc.) ─────────────────────────────────────
info "=== Building John the Ripper Jumbo (for *2john tools) ==="
JTR_DIR="${HOME}/john-jumbo"
JTR_REPO="https://github.com/openwall/john.git"
if [[ ! -d "$JTR_DIR/.git" ]]; then
  git clone --depth 1 "$JTR_REPO" "$JTR_DIR"
fi

# Build in a clean tree.  A stale ../run/john from an earlier configure (with a
# different --prefix) is NOT rebuilt by make, so the binary would keep the old
# $JOHN path and look for its config in the wrong directory.
cd "$JTR_DIR"
rm -rf "$JTR_DIR/src/Makefile" "$JTR_DIR/src/config.status" "$JTR_DIR/src/config.log"
cd "$JTR_DIR/src"
./configure --disable-simd --without-openssl --prefix="${HOME}/.local" 2>&1 | tail -3
make clean 2>&1 | tail -2 || true
make -j"$(nproc)" 2>&1 | tail -3

# `make install` in john-jumbo copies NOTHING: the copy rules in src/Makefile
# are commented out (see doc/README-DISTROS).  Install the run/ tree by hand,
# otherwise john.conf / *.chr / *.conf are missing and every run dies with
# "Error in .../john.conf".
JTR_HOME="${HOME}/.local/share/john"
ensure_dir "$JTR_HOME"
cp -a "$JTR_DIR/run/." "$JTR_HOME/"

# john.conf pulls in these two as user override hooks.  They MUST stay empty:
# putting a copy of john.conf in john.local.conf makes john.conf include
# john.local.conf which includes john.conf ... => infinite .include recursion
# ("ERROR, .include recursion too deep") and john refuses to start.
cat > "$JTR_HOME/john.local.conf" << 'LOCALCONF'
# Local John configuration overrides.
# This file is included by john.conf and MUST NOT contain a copy of john.conf
# (doing so creates an infinite .include recursion and breaks every john run).
# Put your own customizations here, e.g.:
#   [defaults]
#   threads = 4
LOCALCONF
cp "$JTR_HOME/john.local.conf" "$JTR_HOME/john-local.conf"

# Put the john binary and its helper tools on PATH.
ensure_dir "${HOME}/.local/bin"
for name in john unshadow unique undrop unfafs base64conv tgtsnarf mkvcalcproba \
             genmkvpwd calc_stat raw2dyna cprepair SIPdump rar2john zip2john \
             keepass2john bitlocker2john dmg2john putty2john uaf2john \
             wpapcap2john gpg2john hccap2john racf2john pkcs12kdf; do
  if [[ -e "$JTR_HOME/$name" ]]; then
    ln -sf "$JTR_HOME/$name" "${HOME}/.local/bin/$name"
  fi
done
# Symlink *2john* helper scripts (*.py, *.pl, *.rb) plus the standalone perl helpers.
for script in "$JTR_HOME"/*2john* "$JTR_HOME"/codepage.pl "$JTR_HOME"/hextoraw.pl \
               "$JTR_HOME"/netntlm.pl "$JTR_HOME"/pass_gen.pl "$JTR_HOME"/potcheck.pl \
               "$JTR_HOME"/tokenize.pl; do
  [[ -e "$script" ]] || continue
  ln -sf "$script" "${HOME}/.local/bin/$(basename "$script")"
done

# Clean up the stale system-wide install left by the old (broken) script, which
# put a mismatched john.conf in /usr/local/share/john and made john look there.
if [[ -d /usr/local/share/john ]]; then
  warn "Removing stale system-wide John install at /usr/local/share/john"
  if ! sudo rm -rf /usr/local/share/john; then
    warn "Could not remove /usr/local/share/john - remove it manually with:"
    warn "  sudo rm -rf /usr/local/share/john"
  fi
fi

cd /
info "John Jumbo installed"
info "  \$JOHN:        $JTR_HOME"
info "  john.conf:    $([[ -f "$JTR_HOME/john.conf" ]] && echo "$JTR_HOME/john.conf" || echo 'MISSING')"
info "  ssh2john:   $(command -v ssh2john.py 2>/dev/null || echo 'not found')"
info "  gpg2john:   $(command -v gpg2john.py 2>/dev/null || echo 'not found')"
info "  john:       $(command -v john 2>/dev/null || echo 'not found')"
info "  rar2john:   $(command -v rar2john 2>/dev/null || echo 'not found')"
info "  zip2john:   $(command -v zip2john 2>/dev/null || echo 'not found')"
info "  john:       $(command -v john 2>/dev/null && john --version 2>&1 | head -1 || echo 'not found')"

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
printf "  %-20s %s\n" "bloodhound"    "$(command -v bloodhound 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "bloodhound-ce" "$(command -v bloodhound-ce 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "wpscan"        "$(command -v wpscan 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "nxc"           "$(command -v nxc 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "searchsploit"  "$(command -v searchsploit 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "hashcat"       "$(command -v hashcat 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "msfconsole"    "$(command -v msfconsole 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "lftp"          "$(command -v lftp 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "impacket-secretsdump" "$(command -v impacket-secretsdump 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "responder"     "$(command -v responder 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "evil-winrm"    "$(command -v evil-winrm 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "wordlists"     "$(ls $WORDLISTS_DIR 2>/dev/null | head -1 && echo '...' || echo 'not found')"
printf "  %-20s %s\n" "ldapsearch"     "$(command -v ldapsearch 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "ssh2john"      "$(command -v ssh2john.py 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "gpg2john"      "$(command -v gpg2john.py 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "rar2john"      "$(command -v rar2john 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "zip2john"      "$(command -v zip2john 2>/dev/null || echo 'not found')"
printf "  %-20s %s\n" "pdf2john"      "$(command -v pdf2john.py 2>/dev/null || echo 'not found')"
info "Log saved to: $LOGFILE"
