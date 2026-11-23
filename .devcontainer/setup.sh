
#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================
# Robot Framework + Selenium + Chrome + VNC
# GitHub Codespaces initialization
# ==========================================

PROJECT_DIR="/workspaces/training_auto"
VENV_DIR="$PROJECT_DIR/.venv"
REQUIREMENTS="$PROJECT_DIR/requirements.txt"

DISPLAY_NUM=":1"
VNC_PORT=5900
NOVNC_PORT=6080

export DEBIAN_FRONTEND=noninteractive

log()  { echo -e "\n\033[1;34m[INFO]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[OK]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
fail() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

cd "$PROJECT_DIR"

# ==========================================
# 1. Check Python
# ==========================================

log "Checking Python..."

command -v python3 >/dev/null 2>&1 || fail "Python3 not found."

python3 --version

# ==========================================
# 2. Install missing system dependencies
# ==========================================

log "Checking system dependencies..."

APT_PACKAGES=(
    python3-venv
    python3-pip
    xvfb
    openbox
    x11vnc
    novnc
    websockify
    x11-utils
    xterm
    curl
    wget
    ca-certificates
    fonts-liberation
    fonts-noto-color-emoji
)

MISSING_PACKAGES=()

for pkg in "${APT_PACKAGES[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null |
        grep -q "install ok installed"; then
        MISSING_PACKAGES+=("$pkg")
    fi
done

if (( ${#MISSING_PACKAGES[@]} > 0 )); then
    log "Installing missing packages: ${MISSING_PACKAGES[*]}"

    sudo apt-get update
    sudo apt-get install -y "${MISSING_PACKAGES[@]}"
else
    ok "All system dependencies already installed."
fi

# ==========================================
# 3. Create Python virtual environment
# ==========================================

log "Checking Python virtual environment..."

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    python3 -m venv "$VENV_DIR"
    ok "Virtual environment created."
else
    ok "Virtual environment already exists."
fi

PYTHON="$VENV_DIR/bin/python"

# ==========================================
# 4. Install Python requirements
# ==========================================

log "Checking Python libraries..."

[[ -f "$REQUIREMENTS" ]] || fail "requirements.txt not found."

if ! "$PYTHON" -c \
    "import robot, selenium, SeleniumLibrary" >/dev/null 2>&1; then

    log "Installing Robot Framework dependencies..."
    "$PYTHON" -m pip install -r "$REQUIREMENTS"
else
    ok "Robot Framework dependencies already installed."
fi

"$PYTHON" -m pip check || fail "Python dependency conflicts detected."

# ==========================================
# 5. Install Google Chrome if missing
# ==========================================

log "Checking Google Chrome..."

if command -v google-chrome-stable >/dev/null 2>&1; then
    BROWSER="$(command -v google-chrome-stable)"
elif command -v google-chrome >/dev/null 2>&1; then
    BROWSER="$(command -v google-chrome)"
elif command -v chromium >/dev/null 2>&1; then
    BROWSER="$(command -v chromium)"
elif command -v chromium-browser >/dev/null 2>&1; then
    BROWSER="$(command -v chromium-browser)"
else
    ARCH="$(dpkg --print-architecture)"

    [[ "$ARCH" == "amd64" ]] || fail \
        "Automatic Chrome installation requires amd64."

    log "Installing Google Chrome..."

    TMP_DEB="$(mktemp --suffix=.deb)"

    wget -q \
        https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
        -O "$TMP_DEB"

    sudo apt-get install -y "$TMP_DEB"

    rm -f "$TMP_DEB"

    BROWSER="$(command -v google-chrome-stable)"
fi

ok "Browser found: $BROWSER"
"$BROWSER" --version || true

# ==========================================
# 6. Start Xvfb
# ==========================================

log "Checking Xvfb..."

if ! pgrep -f "^Xvfb ${DISPLAY_NUM} " >/dev/null; then
    nohup Xvfb "$DISPLAY_NUM" \
        -screen 0 1920x1080x24 \
        -ac +extension GLX +render -noreset \
        >/tmp/xvfb.log 2>&1 &

    sleep 2
else
    ok "Xvfb already running."
fi

export DISPLAY="$DISPLAY_NUM"

DISPLAY="$DISPLAY_NUM" xdpyinfo >/dev/null 2>&1 \
    || fail "Xvfb is not responding."

# ==========================================
# 7. Start Openbox
# ==========================================

log "Checking Openbox..."

if ! pgrep -x openbox >/dev/null; then
    nohup openbox --display "$DISPLAY_NUM" \
        >/tmp/openbox.log 2>&1 &

    sleep 1
else
    ok "Openbox already running."
fi

# ==========================================
# 8. Start x11vnc
# ==========================================

log "Checking x11vnc..."

if ! ss -lnt | grep -q ":${VNC_PORT} "; then
    nohup x11vnc \
        -display "$DISPLAY_NUM" \
        -forever \
        -shared \
        -nopw \
        -localhost \
        -rfbport "$VNC_PORT" \
        -xkb \
        >/tmp/x11vnc.log 2>&1 &

    sleep 2
else
    ok "x11vnc already running."
fi

# ==========================================
# 9. Start Websockify / noVNC
# ==========================================

log "Checking noVNC..."

if ! ss -lnt | grep -q ":${NOVNC_PORT} "; then
    nohup websockify \
        --web=/usr/share/novnc \
        "$NOVNC_PORT" "localhost:$VNC_PORT" \
        >/tmp/websockify.log 2>&1 &

    sleep 2
else
    ok "noVNC already running."
fi

# ==========================================
# 10. Final verification
# ==========================================

log "Checking final environment..."

"$PYTHON" -m robot --version

"$PYTHON" -c "import selenium; print('Selenium:', selenium.__version__)"
"$PYTHON" -c "import SeleniumLibrary; print('SeleniumLibrary: OK')"

DISPLAY="$DISPLAY_NUM" xdpyinfo >/dev/null \
    || fail "X Server unavailable."

ss -lnt | grep -q ":${VNC_PORT} " \
    || fail "VNC port unavailable."

ss -lnt | grep -q ":${NOVNC_PORT} " \
    || fail "noVNC port unavailable."

curl -fsS "http://localhost:${NOVNC_PORT}/vnc.html" \
    >/dev/null || fail "noVNC HTTP check failed."

# ==========================================
# 11. Configure terminal environment
# ==========================================

BASHRC="$HOME/.bashrc"

if ! grep -qF "# TRAINING_AUTO_ENV" "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" <<EOF

# TRAINING_AUTO_ENV
export PATH="$VENV_DIR/bin:\$PATH"
export DISPLAY=":1"
EOF
fi

ok "======================================"
ok "AUTOMATION ENVIRONMENT READY"
ok "======================================"

echo "Python : $PYTHON"
echo "Robot  : $VENV_DIR/bin/robot"
echo "Browser: $BROWSER"
echo "Display: $DISPLAY_NUM"
echo "VNC    : localhost:$VNC_PORT"
echo "noVNC  : port $NOVNC_PORT"
echo
echo "Open the PORTS tab and access port 6080."
echo "Run your Robot tests manually."
