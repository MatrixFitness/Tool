#!/bin/sh
# Matrix Toolkit Firmware Recovery - Build 025
REPO="https://raw.githubusercontent.com/MatrixFitness/Tool/main"
LOG="/tmp/matrix_firmware_recovery.log"
BOOTSTRAP="/tmp/matrix_bootstrap.sh"

: >"$LOG"
log(){ echo "$@" | tee -a "$LOG"; }
fail(){ log "ERROR: $*"; log "Log: $LOG"; exit 1; }

log "======================================"
log " MATRIX FIRMWARE RECOVERY"
log " GitHub Recovery Edition"
log "======================================"

log "[1/6] Checking internet..."
ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1 || \
ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1 || fail "No internet connection"

log "[2/6] Updating Teltonika package lists..."
opkg update >>"$LOG" 2>&1 || fail "opkg update failed"

log "[3/6] Installing required packages..."
opkg list-installed 2>/dev/null | grep -q '^zerotier ' || \
    opkg install zerotier >>"$LOG" 2>&1 || fail "ZeroTier package installation failed"

command -v wget >/dev/null 2>&1 || \
    opkg install wget >>"$LOG" 2>&1 || fail "wget installation failed"

log "[4/6] Downloading Matrix bootstrap..."
wget -O "$BOOTSTRAP" "$REPO/bootstrap.sh" >>"$LOG" 2>&1 || fail "bootstrap download failed"
chmod +x "$BOOTSTRAP"

log "[5/6] Rebuilding Matrix Toolkit..."
SAFE_UPDATE=1 FIRMWARE_RECOVERY=1 ZT_NETWORK_ID="cf719fd5409699a2" \
    sh "$BOOTSTRAP" 2>&1 | tee -a "$LOG"
RC=${PIPESTATUS:-0}
# BusyBox ash does not provide reliable PIPESTATUS. Verify installation instead.
[ -x /usr/local/bin/matrix-doctor ] || fail "Toolkit rebuild did not install matrix-doctor"

log "[6/6] Final verification..."
matrix-version 2>&1 | tee -a "$LOG"
matrix-doctor 2>&1 | tee -a "$LOG"

log "======================================"
log " FIRMWARE RECOVERY FINISHED"
log "======================================"
log "Run: matrix-zerotier"
log "Run: matrix-doctor"
log "Log: $LOG"
