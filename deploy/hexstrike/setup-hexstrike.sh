#!/usr/bin/env bash
# Full setup script for HexStrike AI + Telegram bot on Ubuntu 24.04 VPS
# Run as root: bash setup-hexstrike.sh
set -euo pipefail

VENV=/opt/hexstrike-env
REPO=/opt/hexstrike-ai
BOT=/opt/hexstrike-bot.py
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo "[hexstrike] $*"; }

log "Installing system dependencies..."
apt-get update -qq
apt-get install -y -qq git python3 python3-pip python3-venv curl \
    nmap nikto sqlmap gobuster whatweb wafw00f whois dnsutils \
    subfinder amass httpx nuclei ffuf

log "Cloning HexStrike AI..."
if [ -d "$REPO" ]; then
    git -C "$REPO" pull --ff-only
else
    git clone https://github.com/0x4m4/hexstrike-ai.git "$REPO"
fi

log "Creating Python virtual environment at $VENV..."
python3 -m venv "$VENV"
"$VENV/bin/pip" install --upgrade pip -q

log "Installing HexStrike dependencies..."
"$VENV/bin/pip" install -r "$REPO/requirements.txt" -q

log "Installing Telegram bot dependencies..."
"$VENV/bin/pip" install "python-telegram-bot==21.3" "requests>=2.31" -q

log "Installing HexStrike systemd service..."
cp "$SCRIPT_DIR/hexstrike.service" /etc/systemd/system/hexstrike.service
systemctl daemon-reload
systemctl enable hexstrike
systemctl restart hexstrike
sleep 3
if systemctl is-active --quiet hexstrike; then
    log "HexStrike server running."
else
    log "WARNING: HexStrike server failed to start — check: journalctl -u hexstrike -n 30"
fi

log "Deploying Telegram bot..."
cp "$SCRIPT_DIR/hexstrike-bot.py" "$BOT"
chmod 600 "$BOT"

log "Installing bot systemd service..."
cp "$SCRIPT_DIR/hexstrike-bot.service" /etc/systemd/system/hexstrike-bot.service
systemctl daemon-reload
systemctl enable hexstrike-bot
systemctl restart hexstrike-bot
sleep 2
if systemctl is-active --quiet hexstrike-bot; then
    log "Telegram bot running."
else
    log "WARNING: Bot failed to start — check: journalctl -u hexstrike-bot -n 30"
fi

log ""
log "=== Setup complete ==="
log "HexStrike server: systemctl status hexstrike"
log "Telegram bot:     systemctl status hexstrike-bot"
log "Server health:    curl http://localhost:8888/health"
log ""
log "Test the API manually:"
log "  curl -X POST http://localhost:8888/api/command \\"
log "    -H 'Content-Type: application/json' \\"
log "    -d '{\"command\": \"subfinder -d example.com -silent\"}'"
