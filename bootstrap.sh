#!/bin/sh
# Matrix Cloud Bootstrap - Build 046

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
: >"$LOG"

log(){ echo "$@" | tee -a "$LOG"; }
fail(){ log "ERROR: $*"; log "Log: $LOG"; exit 1; }

download(){
    URL="$1"; DEST="$2"
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
log " Transactional Edition"
log "======================================"

log "[1/9] Checking internet..."
ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1 || \
ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1 || fail "No internet connection"

log "[2/9] Checking download tools..."
command -v wget >/dev/null 2>&1 || {
    opkg update >>"$LOG" 2>&1 || true
    opkg install wget >>"$LOG" 2>&1 || fail "wget is unavailable"
}

log "[3/9] Reading latest build..."
download "$LATEST_URL" "$WORK/latest.txt" || fail "Could not download latest.txt"
BUILD="$(tr -d '\r\n ' <"$WORK/latest.txt")"
case "$BUILD" in ''|*[!0-9]*) fail "Invalid build: $BUILD" ;; esac
BUILD_NUM="$(echo "$BUILD" | sed 's/^0*//')"
[ -n "$BUILD_NUM" ] || BUILD_NUM=0
BUILD_PAD="$(printf '%03d' "$BUILD_NUM")"

log "[4/9] Downloading Build $BUILD_PAD..."
PACKAGE="MatrixToolkit_Build${BUILD_PAD}.tar.gz"
FILE="$WORK/$PACKAGE"
download "${RELEASE_BASE}/${PACKAGE}" "$FILE" || fail "Could not download $PACKAGE"
tar -tzf "$FILE" >/dev/null 2>&1 || fail "Invalid archive: $PACKAGE"

log "[5/9] Extracting and validating package..."
rm -rf /tmp/MatrixInstall
tar -xzf "$FILE" -C /tmp || fail "Extraction failed"
[ -d /tmp/MatrixInstall ] || fail "MatrixInstall missing"
SOURCE_BUILD="$(grep '^Build=' /tmp/MatrixInstall/version.txt 2>/dev/null | cut -d= -f2-)"
[ "$SOURCE_BUILD" = "$BUILD_PAD" ] || fail "Package build mismatch: expected $BUILD_PAD, found ${SOURCE_BUILD:-missing}"
[ -x /tmp/MatrixInstall/bin/matrix-recovery ] || fail "Transactional recovery missing"

log "[6/9] Preparing critical installer files..."
mkdir -p /usr/local/bin
cp -f /tmp/MatrixInstall/bin/matrix-recovery /usr/local/bin/matrix-recovery || fail "Could not install recovery command"
chmod 755 /usr/local/bin/matrix-recovery

log "[7/9] Installing Build $BUILD_PAD transactionally..."
SAFE_UPDATE="${SAFE_UPDATE:-0}" \
MATRIX_KEEP_TMP_INSTALL=1 \
ZT_NETWORK_ID="$ZT_NETWORK_ID" \
/usr/local/bin/matrix-recovery || fail "Transactional recovery failed"

log "[8/9] Validating matching installed tools..."
INSTALLED="$(grep '^Build=' /usr/local/matrix/version.txt 2>/dev/null | cut -d= -f2-)"
[ "$INSTALLED" = "$BUILD_PAD" ] || fail "Installed Build mismatch: expected $BUILD_PAD, found ${INSTALLED:-missing}"

DOCTOR_BUILD="$(grep -m1 'Build [0-9][0-9][0-9]' /usr/local/bin/matrix-doctor 2>/dev/null | sed 's/.*Build //;s/[^0-9].*//' | head -1)"
[ -z "$DOCTOR_BUILD" ] || [ "$DOCTOR_BUILD" = "$BUILD_PAD" ] || fail "Matrix Doctor is from Build $DOCTOR_BUILD, expected $BUILD_PAD"

log "[9/9] Running Matrix Doctor..."
/usr/local/bin/matrix-doctor | tee -a "$LOG"
DOCTOR_RC=${PIPESTATUS:-0}

ZT_IP=""
if [ -f /usr/local/matrix/lib/zerotier_runtime.sh ]; then
    . /usr/local/matrix/lib/zerotier_runtime.sh
    ZH="$(zt_detect_home 2>/dev/null)"
    [ -n "$ZH" ] && ZT_IP="$(zt_ip "$ZH" 2>/dev/null)"
fi

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
fi
log "Run: matrix-doctor"
log "Log: $LOG"

# Local installation is complete even when ZeroTier still needs repair.
exit 0
