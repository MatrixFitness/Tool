#!/bin/sh
REPO_OWNER="${REPO_OWNER:-MatrixFitness}"
REPO_NAME="${REPO_NAME:-Tool}"
REPO_BRANCH="${REPO_BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}"
LATEST_URL="${LATEST_URL:-${RAW_BASE}/latest.txt}"
RELEASE_BASE="${RELEASE_BASE:-${RAW_BASE}/releases}"
ZT_NETWORK_ID="${ZT_NETWORK_ID:-cf719fd5409699a2}"

WORK="/tmp/matrix_bootstrap"
LOG="/tmp/matrix_bootstrap.log"
mkdir -p "$WORK"
: > "$LOG"

log(){ echo "$@" | tee -a "$LOG"; }
fail(){ log "ERROR: $*"; log "Log: $LOG"; exit 1; }

download(){
    URL="$1"
    DEST="$2"
    if command -v wget >/dev/null 2>&1; then
        wget -O "$DEST" "$URL" >>"$LOG" 2>&1
    elif command -v curl >/dev/null 2>&1; then
        curl -fL "$URL" -o "$DEST" >>"$LOG" 2>&1
    else
        return 127
    fi
}

log "======================================"
log " MATRIX TOOLKIT CLOUD BOOTSTRAP"
log " Production Edition"
log "======================================"
log "If connected through router WiFi, SSH may disconnect when services restart."

log "[1/9] Checking internet..."
ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1 || ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1 || fail "No internet connection"

log "[2/9] Checking tools..."
opkg update >>"$LOG" 2>&1 || true
command -v wget >/dev/null 2>&1 || opkg install wget >>"$LOG" 2>&1 || true

log "[3/9] Reading latest build..."
download "$LATEST_URL" "$WORK/latest.txt" || fail "Could not download latest.txt"
BUILD="$(tr -d '\r\n ' < "$WORK/latest.txt")"
case "$BUILD" in ''|*[!0-9]*) fail "Invalid build in latest.txt: $BUILD" ;; esac
BUILD_NUM="$(echo "$BUILD" | sed 's/^0*//')"
[ -z "$BUILD_NUM" ] && BUILD_NUM="0"
BUILD_PAD="$(printf "%03d" "$BUILD_NUM")"

log "[4/9] Downloading Production Build $BUILD_PAD..."
PACKAGE="MatrixToolkit_Build${BUILD_PAD}.tar.gz"
FILE="$WORK/$PACKAGE"
download "${RELEASE_BASE}/${PACKAGE}" "$FILE" || fail "Could not download $PACKAGE"
tar -tzf "$FILE" >/dev/null 2>&1 || fail "Invalid archive: $PACKAGE"

log "[5/9] Extracting..."
rm -rf /tmp/MatrixInstall
rm -f /tmp/matrix_update_request /tmp/matrix_update_worker.lock /tmp/matrix_update_script.lock
tar -xzf "$FILE" -C /tmp || fail "Extract failed"
[ -d /tmp/MatrixInstall ] || fail "MatrixInstall missing"

log "[6/9] Installing files..."
mkdir -p /usr/local/matrix/recovery_source/MatrixInstall /usr/local/matrix/web /usr/local/matrix/adminweb/cgi-bin /usr/local/matrix/platform /usr/local/bin
rm -rf /usr/local/matrix/recovery_source/MatrixInstall
mkdir -p /usr/local/matrix/recovery_source/MatrixInstall
cp -R /tmp/MatrixInstall/. /usr/local/matrix/recovery_source/MatrixInstall/
[ -d /tmp/MatrixInstall/web ] && cp -R /tmp/MatrixInstall/web/. /usr/local/matrix/web/ 2>/dev/null || true
[ -d /tmp/MatrixInstall/adminweb ] && cp -R /tmp/MatrixInstall/adminweb/. /usr/local/matrix/adminweb/ 2>/dev/null || true
[ -d /tmp/MatrixInstall/cgi-bin ] && { mkdir -p /usr/local/matrix/web/cgi-bin; cp -R /tmp/MatrixInstall/cgi-bin/. /usr/local/matrix/web/cgi-bin/; }
[ -f /tmp/MatrixInstall/index.html ] && cp -f /tmp/MatrixInstall/index.html /usr/local/matrix/web/index.html
[ -f /tmp/MatrixInstall/version.txt ] && cp -f /tmp/MatrixInstall/version.txt /usr/local/matrix/version.txt
[ -d /tmp/MatrixInstall/platform ] && cp -R /tmp/MatrixInstall/platform/. /usr/local/matrix/platform/ 2>/dev/null || true
[ -d /tmp/MatrixInstall/bin ] && cp -R /tmp/MatrixInstall/bin/. /usr/local/bin/ 2>/dev/null || true
find /usr/local/matrix -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
chmod +x /usr/local/bin/matrix-* 2>/dev/null || true
[ -x /usr/local/bin/matrix-recovery ] || fail "matrix-recovery missing"

# Build 020: install critical tools before recovery
[ -f /tmp/MatrixInstall/bin/matrix-zerotier-state ] && cp -f /tmp/MatrixInstall/bin/matrix-zerotier-state /usr/local/bin/matrix-zerotier-state
[ -f /tmp/MatrixInstall/bin/matrix_update_worker.sh ] && cp -f /tmp/MatrixInstall/bin/matrix_update_worker.sh /usr/local/matrix/matrix_update_worker.sh.new
if [ -f /usr/local/matrix/matrix_update_worker.sh.new ]; then
    chmod +x /usr/local/matrix/matrix_update_worker.sh.new
    mv -f /usr/local/matrix/matrix_update_worker.sh.new /usr/local/matrix/matrix_update_worker.sh
fi
chmod +x /usr/local/bin/matrix-zerotier-state /usr/local/matrix/matrix_update_worker.sh 2>/dev/null || true

# Build 020 unified ZeroTier runtime library
mkdir -p /usr/local/matrix/lib /usr/local/bin
[ -f /tmp/MatrixInstall/lib/zerotier_runtime.sh ] && cp -f /tmp/MatrixInstall/lib/zerotier_runtime.sh /usr/local/matrix/lib/zerotier_runtime.sh
[ -f /tmp/MatrixInstall/bin/matrix-zerotier ] && cp -f /tmp/MatrixInstall/bin/matrix-zerotier /usr/local/bin/matrix-zerotier
[ -f /tmp/MatrixInstall/bin/matrix-zerotier-state ] && cp -f /tmp/MatrixInstall/bin/matrix-zerotier-state /usr/local/bin/matrix-zerotier-state
chmod +x /usr/local/matrix/lib/zerotier_runtime.sh /usr/local/bin/matrix-zerotier /usr/local/bin/matrix-zerotier-state 2>/dev/null || true
grep -Fq '$3==n{print $(NF-1);exit}' /usr/local/matrix/lib/zerotier_runtime.sh || fail "ZeroTier parser validation failed"

log "[7/9] Running recovery..."
SAFE_UPDATE="${SAFE_UPDATE:-0}" MATRIX_KEEP_TMP_INSTALL=1 ZT_NETWORK_ID="$ZT_NETWORK_ID" /usr/local/bin/matrix-recovery

log "[8/9] Running doctor..."
/usr/local/bin/matrix-doctor | tee -a "$LOG"

log "[9/9] Finalizing..."
[ -x /usr/local/bin/matrix-cleanup ] && /usr/local/bin/matrix-cleanup --auto >>"$LOG" 2>&1 || true

ZT_IP="$(ip -4 addr show ztdiyqsthc 2>/dev/null | awk '/inet / {split($2,a,"/"); print a[1]; exit}')"
ZT_NODE="$(cut -d: -f1 /etc/zerotier/identity.public 2>/dev/null)"

log "======================================"
log " BOOTSTRAP COMPLETED"
log "======================================"
log "Installed: Production Edition Build $BUILD_PAD"
log "Toolkit: http://192.168.1.1:8080"
log "Admin:   http://192.168.1.1:8081/cgi-bin/admin_login.sh"
if [ -n "$ZT_IP" ]; then
    log "ZeroTier Toolkit: http://$ZT_IP:8080"
    log "ZeroTier Admin:   http://$ZT_IP:8081/cgi-bin/admin_login.sh"
else
    log "ZeroTier remote access is not ready yet."
    [ -n "$ZT_NODE" ] && log "Authorize Node ID: $ZT_NODE"
fi
log "Run: matrix-doctor"
log "Log: $LOG"


# Build 020 tools
[ -f /usr/local/matrix/bin/matrix-zerotier-state ] && cp -f /usr/local/matrix/bin/matrix-zerotier-state /usr/local/bin/matrix-zerotier-state
[ -f /usr/local/matrix/bin/matrix_update_worker.sh ] && cp -f /usr/local/matrix/bin/matrix_update_worker.sh /usr/local/matrix/matrix_update_worker.sh
chmod +x /usr/local/bin/matrix-zerotier-state /usr/local/matrix/matrix_update_worker.sh 2>/dev/null
