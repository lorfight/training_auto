
#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================================
# Robot Framework + Selenium + Google Chrome + VNC
# GitHub Codespaces Environment Setup
#
# - Automatically prepares the environment on startup.
# - Starts Xvfb, Openbox, x11vnc and noVNC.
# - Configures DISPLAY and Python virtual environment.
# - Verifies Selenium can launch Chrome.
# - Does NOT execute Robot Framework tests.
# ==========================================================

# 1. Project configuration
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="$PROJECT_DIR/.venv"
REQUIREMENTS="$PROJECT_DIR/requirements.txt"

DISPLAY_NUM=":1"
VNC_PORT=5900
NOVNC_PORT=6080
NOVNC_WEB="/usr/share/novnc"

export DISPLAY="$DISPLAY_NUM"
export DEBIAN_FRONTEND=noninteractive

PYTHON="$(command -v python3 || true)"

# 2. Logging
log() {
    echo -e "\n\033[1;34m[INFO]\033[0m $*"
}

ok() {
    echo -e "\033[1;32m[OK]\033[0m $*"
}

warn() {
    echo -e "\033[1;33m[WARN]\033[0m $*"
}

fail() {
    echo -e "\033[1;31m[ERROR]\033[0m $*" >&2
    exit 1
}

# 3. Sudo configuration
if [[ "$EUID" -eq 0 ]]; then
    SUDO=()
elif command -v sudo >/dev/null 2>&1; then
    SUDO=(sudo)
else
    fail "sudo is required to install system dependencies."
fi

cd "$PROJECT_DIR"

# Helper: check whether a TCP port is listening
port_listening() {
    ss -H -lnt "sport = :$1" 2>/dev/null | grep -q .
}

# 4. Check Python
log "Checking Python..."

[[ -n "$PYTHON" ]] || fail "Python3 not found."

"$PYTHON" --version

# 5. Install missing system dependencies
log "Checking system dependencies..."

PACKAGES=(
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
    fonts-dejavu-core
    iproute2
    procps
)

MISSING_PACKAGES=()

for package in "${PACKAGES[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null \
        | grep -q "install ok installed"; then
        MISSING_PACKAGES+=("$package")
    fi
done

if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
    log "Installing missing packages: ${MISSING_PACKAGES[*]}"

    # Disable broken Yarn repository (not required).
    YARN_SOURCE="/etc/apt/sources.list.d/yarn.list"

    if [[ -f "$YARN_SOURCE" ]]; then
        log "Disabling unnecessary Yarn repository..."
        "${SUDO[@]}" mv "$YARN_SOURCE" "${YARN_SOURCE}.disabled"
    fi

    "${SUDO[@]}" apt-get update

    "${SUDO[@]}" apt-get install -y \
        "${MISSING_PACKAGES[@]}"
else
    ok "All system dependencies already installed."
fi

# 6. Create Python virtual environment
log "Checking Python virtual environment..."

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    log "Creating virtual environment..."
    "$PYTHON" -m venv "$VENV_DIR"
else
    ok "Virtual environment already exists."
fi

PYTHON="$VENV_DIR/bin/python"

# 7. Install Robot Framework dependencies
log "Checking Python libraries..."

[[ -f "$REQUIREMENTS" ]] \
    || fail "requirements.txt not found: $REQUIREMENTS"

"$PYTHON" -m pip install \
    --disable-pip-version-check \
    -r "$REQUIREMENTS"

"$PYTHON" -m pip check

ok "Robot Framework dependencies ready."

# 8. Install Google Chrome if missing
log "Checking Google Chrome..."

if ! command -v google-chrome-stable >/dev/null 2>&1; then
    log "Installing Google Chrome..."

    ARCH="$(dpkg --print-architecture)"

    [[ "$ARCH" == "amd64" ]] \
        || fail "Automatic Chrome installation currently supports amd64 only."

    CHROME_DEB="/tmp/google-chrome-stable_current_amd64.deb"

    curl -fsSL \
        https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
        -o "$CHROME_DEB"

    "${SUDO[@]}" apt-get install -y "$CHROME_DEB"

    rm -f "$CHROME_DEB"
else
    ok "Browser found: $(command -v google-chrome-stable)"
fi

BROWSER="$(command -v google-chrome-stable)"
"$BROWSER" --version

# 9. Start Xvfb
log "Checking Xvfb..."

if ! pgrep -f "^Xvfb ${DISPLAY_NUM} " >/dev/null 2>&1; then
    nohup Xvfb "$DISPLAY_NUM" \
        -screen 0 1920x1080x24 \
        -ac \
        +extension GLX \
        +render \
        -noreset \
        >/tmp/xvfb.log 2>&1 </dev/null &

    sleep 2
else
    ok "Xvfb already running."
fi

export DISPLAY="$DISPLAY_NUM"

X_READY=false

for i in {1..15}; do
    if DISPLAY="$DISPLAY_NUM" xdpyinfo >/dev/null 2>&1; then
        X_READY=true
        break
    fi
    sleep 1
done

[[ "$X_READY" == true ]] \
    || fail "Xvfb is not responding. Check /tmp/xvfb.log."

ok "Xvfb is ready on $DISPLAY_NUM."

# 10. Start Openbox
log "Checking Openbox..."

if ! pgrep -x openbox >/dev/null 2>&1; then
    nohup env DISPLAY="$DISPLAY_NUM" openbox \
        >/tmp/openbox.log 2>&1 </dev/null &

    sleep 2
else
    ok "Openbox already running."
fi

if ! pgrep -x openbox >/dev/null 2>&1; then
    warn "Openbox did not start. Check /tmp/openbox.log."
else
    ok "Openbox is running."
fi

# 11. Start x11vnc
log "Checking x11vnc..."

X11VNC_RUNNING=false

if pgrep -x x11vnc >/dev/null 2>&1 \
    && port_listening "$VNC_PORT"; then
    X11VNC_RUNNING=true
    ok "x11vnc already running."
fi

if [[ "$X11VNC_RUNNING" != true ]]; then
    if ! port_listening "$VNC_PORT"; then
        pkill -x x11vnc 2>/dev/null || true
        sleep 1

        nohup x11vnc \
            -display "$DISPLAY_NUM" \
            -forever \
            -shared \
            -nopw \
            -localhost \
            -rfbport "$VNC_PORT" \
            -xkb \
            >/tmp/x11vnc.log 2>&1 </dev/null &
    else
        fail "Port $VNC_PORT is occupied but x11vnc is not running."
    fi
fi

X11VNC_READY=false

for i in {1..20}; do
    if pgrep -x x11vnc >/dev/null 2>&1 \
        && port_listening "$VNC_PORT"; then
        X11VNC_READY=true
        break
    fi
    sleep 1
done

[[ "$X11VNC_READY" == true ]] || {
    tail -30 /tmp/x11vnc.log
    fail "x11vnc failed to start."
}

ok "x11vnc is ready on port $VNC_PORT."

# 12. Start noVNC / Websockify
log "Checking noVNC..."

[[ -f "$NOVNC_WEB/vnc.html" ]] \
    || fail "noVNC web interface not found: $NOVNC_WEB/vnc.html"

WEBSOCKIFY_RUNNING=false

if pgrep -af 'websockify.*6080' >/dev/null 2>&1 \
    && port_listening "$NOVNC_PORT"; then
    WEBSOCKIFY_RUNNING=true
    ok "Websockify already running."
fi

if [[ "$WEBSOCKIFY_RUNNING" != true ]]; then
    if port_listening "$NOVNC_PORT"; then
        fail "Port $NOVNC_PORT is occupied by another process."
    fi

    nohup websockify \
        --web="$NOVNC_WEB" \
        "$NOVNC_PORT" \
        "localhost:$VNC_PORT" \
        >/tmp/websockify.log 2>&1 </dev/null &
fi

NOVNC_READY=false

for i in {1..20}; do
    if port_listening "$NOVNC_PORT" \
        && curl -fsS \
            "http://127.0.0.1:${NOVNC_PORT}/vnc.html" \
            >/dev/null; then
        NOVNC_READY=true
        break
    fi
    sleep 1
done

[[ "$NOVNC_READY" == true ]] || {
    tail -30 /tmp/websockify.log
    fail "noVNC failed to start."
}

ok "noVNC is ready on port $NOVNC_PORT."

# 13. Configure terminal environment
log "Configuring terminal environment..."

BASHRC="$HOME/.bashrc"

touch "$BASHRC"

# Remove old managed block to avoid duplicate entries.
if grep -qF "# BEGIN TRAINING_AUTO_ENV" "$BASHRC"; then
    sed -i '/# BEGIN TRAINING_AUTO_ENV/,/# END TRAINING_AUTO_ENV/d' "$BASHRC"
fi

# Add the latest environment configuration.
cat >> "$BASHRC" <<EOF

# BEGIN TRAINING_AUTO_ENV
export PATH="$VENV_DIR/bin:\$PATH"
export DISPLAY="$DISPLAY_NUM"
# END TRAINING_AUTO_ENV
EOF

# Apply environment to the current setup process.
export PATH="$VENV_DIR/bin:$PATH"
export DISPLAY="$DISPLAY_NUM"

ok "Terminal environment configured."

# 14. Final verification
log "Checking final environment..."

"$PYTHON" -c "import robot; print('Robot Framework:', robot.__version__)"

"$PYTHON" -c "import selenium; print('Selenium:', selenium.__version__)"

"$PYTHON" -c "import selenium; print('Selenium:', selenium.__version__)"

"$PYTHON" -c "import SeleniumLibrary; print('SeleniumLibrary: OK')"

DISPLAY="$DISPLAY_NUM" xdpyinfo >/dev/null \
    || fail "X Server unavailable."

pgrep -x x11vnc >/dev/null \
    || fail "x11vnc process is not running."

port_listening "$VNC_PORT" \
    || fail "VNC port unavailable."

port_listening "$NOVNC_PORT" \
    || fail "noVNC port unavailable."

curl -fsS \
    "http://127.0.0.1:${NOVNC_PORT}/vnc.html" \
    >/dev/null \
    || fail "noVNC HTTP check failed."

# 15. Verify Selenium + Chrome
log "Checking Selenium + Chrome..."

"$PYTHON" - <<'PY'
from selenium import webdriver
from selenium.webdriver.chrome.options import Options

options = Options()
options.add_argument("--no-sandbox")
options.add_argument("--disable-dev-shm-usage")
options.add_argument("--disable-gpu")

driver = None

try:
    driver = webdriver.Chrome(options=options)
    driver.get("https://example.com")

    assert driver.title == "Example Domain", (
        f"Unexpected page title: {driver.title}"
    )

    print("Chrome:", driver.capabilities.get("browserVersion"))
    print("Title:", driver.title)
    print("URL:", driver.current_url)

finally:
    if driver:
        driver.quit()
PY

ok "Selenium + Chrome verification passed."

# 16. Final result
ok "=========================================="
ok "AUTOMATION ENVIRONMENT READY"
ok "=========================================="

echo
echo "Project : $PROJECT_DIR"
echo "Python  : $PYTHON"
echo "Robot   : $VENV_DIR/bin/robot"
echo "Browser : $BROWSER"
echo "Display : $DISPLAY_NUM"
echo "VNC     : localhost:$VNC_PORT"
echo "noVNC   : port $NOVNC_PORT"
echo
echo "Open the PORTS tab and access port 6080."
echo "Robot tests will NOT run automatically."
echo
echo "Run tests manually:"
echo "robot -d results test/smoke.robot"
echo
