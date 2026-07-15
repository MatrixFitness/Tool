#!/bin/sh
# Matrix Toolkit Firmware Recovery - Build 026
REPO="https://raw.githubusercontent.com/MatrixFitness/Tool/main"
LOG="/tmp/matrix_firmware_recovery.log"
BOOTSTRAP="/tmp/matrix_bootstrap.sh"
AUTH_TIMEOUT="${MATRIX_ZT_AUTH_TIMEOUT:-600}"
AUTH_INTERVAL=5
: >"$LOG"
log(){ echo "$@" | tee -a "$LOG"; }
fail(){ log "ERROR: $*"; log "Log: $LOG"; exit 1; }
wait_for_zerotier_ready(){
  [ -f /usr/local/matrix/lib/zerotier_runtime.sh ] || return 1
  . /usr/local/matrix/lib/zerotier_runtime.sh
  HOME="$(zt_detect_home 2>/dev/null)"
  [ -n "$HOME" ] || { log "ZeroTier runtime not found after provisioning."; return 1; }
  NODE="$(zt_node_id "$HOME" 2>/dev/null)"
  STATE="$(zt_network_state "$HOME" 2>/dev/null)"
  if [ "$STATE" = "OK" ]; then
    log "ZeroTier authorization detected... OK"
  elif [ "$STATE" = "ACCESS_DENIED" ]; then
    log ""
    log "======================================"
    log " ZEROTIER AUTHORIZATION REQUIRED"
    log "======================================"
    log "Node ID: ${NODE:-unknown}"
    log ""
    log "Authorize this Node ID in ZeroTier Central."
    log "Recovery will continue automatically."
    log "Waiting up to $((AUTH_TIMEOUT/60)) minutes..."
    log ""
    ELAPSED=0
    while [ "$ELAPSED" -lt "$AUTH_TIMEOUT" ]; do
      STATE="$(zt_network_state "$HOME" 2>/dev/null)"
      [ "$STATE" = "OK" ] && { log "ZeroTier authorization detected... OK"; break; }
      printf '.' | tee -a "$LOG"
      sleep "$AUTH_INTERVAL"
      ELAPSED=$((ELAPSED+AUTH_INTERVAL))
    done
    echo | tee -a "$LOG"
    [ "$STATE" = "OK" ] || {
      log "Authorization was not completed within the timeout."
      log "Node ID: ${NODE:-unknown}"
      log "After authorization, run: matrix-doctor"
      return 2
    }
  else
    log "ZeroTier network state: ${STATE:-unknown}"
    return 1
  fi
  log "Waiting for ZeroTier IP address..."
  IP="$(zt_wait_ip "$HOME" 2>/dev/null)"
  [ -n "$IP" ] || { log "Authorization is OK, but no IP address was assigned."; return 1; }
  log "ZeroTier IP address.............. $IP"
  return 0
}
log "======================================"
log " MATRIX FIRMWARE RECOVERY"
log " GitHub Recovery Edition"
log " Build 026"
log "======================================"
log "[1/6] Checking internet..."
ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1 || ping -c 1 -W 5 1.1.1.1 >/dev/null 2>&1 || fail "No internet connection"
log "[2/6] Updating Teltonika package lists..."
opkg update >>"$LOG" 2>&1 || fail "opkg update failed"
log "[3/6] Installing required packages..."
opkg list-installed 2>/dev/null | grep -q '^zerotier ' || opkg install zerotier >>"$LOG" 2>&1 || fail "ZeroTier package installation failed"
command -v wget >/dev/null 2>&1 || opkg install wget >>"$LOG" 2>&1 || fail "wget installation failed"
log "[4/6] Downloading Matrix bootstrap..."
wget -O "$BOOTSTRAP" "$REPO/bootstrap.sh" >>"$LOG" 2>&1 || fail "bootstrap download failed"
chmod +x "$BOOTSTRAP"
log "[5/6] Rebuilding Matrix Toolkit..."
SAFE_UPDATE=1 FIRMWARE_RECOVERY=1 ZT_NETWORK_ID="cf719fd5409699a2" sh "$BOOTSTRAP" 2>&1 | tee -a "$LOG"
[ -x /usr/local/bin/matrix-doctor ] || fail "Toolkit rebuild did not install matrix-doctor"
log "[6/6] Waiting for ZeroTier readiness..."
wait_for_zerotier_ready
ZT_RESULT=$?
if [ "$ZT_RESULT" -eq 2 ]; then
  log "Firmware recovery completed locally. ZeroTier authorization is still required."
  exit 2
elif [ "$ZT_RESULT" -ne 0 ]; then
  fail "ZeroTier did not become ready"
fi
log "Running final verification..."
matrix-version 2>&1 | tee -a "$LOG"
matrix-doctor 2>&1 | tee -a "$LOG"
log "======================================"
log " FIRMWARE RECOVERY FINISHED"
log "======================================"
log "Run: matrix-zerotier"
log "Run: matrix-doctor"
log "Log: $LOG"
