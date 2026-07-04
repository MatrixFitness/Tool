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

log() { echo "$@" | tee -a "$LOG"; }
fail() { log "ERROR: $*"; exit 1; }

download() {
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
log "======================================"

ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1 || ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1 || fail "No internet connection"

opkg update >>"$LOG" 2>&1 || true
opkg install ca-certificates wget tar gzip >>"$LOG" 2>&1 || true

download "$LATEST_URL" "$WORK/latest.txt" || fail "Could not download latest.txt"
VERSION="$(tr -d '\r\n ' < "$WORK/latest.txt")"
case "$VERSION" in
    ''|*[!0-9.]*) fail "Invalid version in latest.txt: $VERSION" ;;
esac

PACKAGE="MatrixToolkit_v${VERSION}.tar.gz"
URL="${RELEASE_BASE}/${PACKAGE}"
FILE="$WORK/$PACKAGE"

log "Installing stable release v$VERSION"
download "$URL" "$FILE" || fail "Could not download $URL"
tar -tzf "$FILE" >/dev/null 2>&1 || fail "Downloaded archive is invalid"

rm -rf /tmp/MatrixInstall
rm -f /tmp/matrix_update_request /tmp/matrix_update_worker.lock /tmp/matrix_update_script.lock
tar -xzf "$FILE" -C /tmp || fail "Could not extract release"
[ -d /tmp/MatrixInstall ] || fail "MatrixInstall folder missing"

mkdir -p /usr/local/matrix/recovery_source/MatrixInstall
rm -rf /usr/local/matrix/recovery_source/MatrixInstall/*
cp -R /tmp/MatrixInstall/. /usr/local/matrix/recovery_source/MatrixInstall/

mkdir -p /usr/local/matrix/web /usr/local/matrix/adminweb /usr/local/matrix/platform /usr/local/bin

[ -d /tmp/MatrixInstall/web ] && cp -R /tmp/MatrixInstall/web/. /usr/local/matrix/web/ 2>/dev/null || true
[ -d /tmp/MatrixInstall/adminweb ] && cp -R /tmp/MatrixInstall/adminweb/. /usr/local/matrix/adminweb/ 2>/dev/null || true
[ -d /tmp/MatrixInstall/cgi-bin ] && {
    mkdir -p /usr/local/matrix/web/cgi-bin
    cp -R /tmp/MatrixInstall/cgi-bin/. /usr/local/matrix/web/cgi-bin/
}
[ -f /tmp/MatrixInstall/index.html ] && cp -f /tmp/MatrixInstall/index.html /usr/local/matrix/web/index.html
[ -f /tmp/MatrixInstall/version.txt ] && cp -f /tmp/MatrixInstall/version.txt /usr/local/matrix/version.txt
[ -d /tmp/MatrixInstall/platform ] && cp -R /tmp/MatrixInstall/platform/. /usr/local/matrix/platform/
[ -d /tmp/MatrixInstall/bin ] && cp -R /tmp/MatrixInstall/bin/. /usr/local/bin/

find /usr/local/matrix -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
chmod +x /usr/local/bin/matrix-* 2>/dev/null || true

[ -x /usr/local/bin/matrix-recovery ] || fail "matrix-recovery was not installed"

ZT_NETWORK_ID="$ZT_NETWORK_ID" /usr/local/bin/matrix-recovery
[ -x /usr/local/bin/matrix-doctor ] && /usr/local/bin/matrix-doctor

ZT_IP="$(ip -4 addr 2>/dev/null | awk '/ztd/ && /inet / {split($2,a,"/"); print a[1]; exit}')"
ZT_NODE="$(cut -d: -f1 /etc/zerotier/identity.public 2>/dev/null)"

log "======================================"
log " BOOTSTRAP COMPLETED"
log "======================================"
log "Toolkit: http://192.168.1.1:8080"
log "Admin:   http://192.168.1.1:8081/cgi-bin/admin_login.sh"

if [ -n "$ZT_IP" ]; then
    log "ZeroTier Toolkit: http://$ZT_IP:8080"
    log "ZeroTier Admin:   http://$ZT_IP:8081/cgi-bin/admin_login.sh"
else
    log "ZeroTier remote access is not ready yet."
    [ -n "$ZT_NODE" ] && log "Authorize Node ID in ZeroTier Central: $ZT_NODE"
fi

log "Log: $LOG"
