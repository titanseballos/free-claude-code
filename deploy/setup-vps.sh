#!/usr/bin/env bash
# Automates free-claude-code installation and systemd service setup on a VPS.
# Run as the user who will own the service (not root).
# Usage: bash deploy/setup-vps.sh
set -euo pipefail

REPO_URL="https://github.com/Alishahryar1/free-claude-code.git"
CONFIG_ENV="$HOME/.config/free-claude-code/.env"
SERVICE_NAME="free-claude-code"
SERVICE_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/free-claude-code.service"
SERVICE_DST="/etc/systemd/system/${SERVICE_NAME}.service"

log() { echo "[fcc-setup] $*"; }
die() { echo "[fcc-setup] ERROR: $*" >&2; exit 1; }

# ── 1. Install / update uv ──────────────────────────────────────────────────
if command -v uv &>/dev/null; then
    log "Updating uv..."
    uv self update
else
    log "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # shellcheck source=/dev/null
    source "$HOME/.local/bin/env"
fi

# ── 2. Python 3.14 ──────────────────────────────────────────────────────────
log "Ensuring Python 3.14 is available..."
uv python install 3.14

# ── 3. Install / upgrade free-claude-code package ───────────────────────────
if uv tool list 2>/dev/null | grep -q free-claude-code; then
    log "Upgrading free-claude-code..."
    uv tool upgrade free-claude-code
else
    log "Installing free-claude-code..."
    uv tool install "git+${REPO_URL}"
fi

# Ensure the binary is on PATH
export PATH="$HOME/.local/bin:$PATH"
command -v free-claude-code &>/dev/null || die "free-claude-code binary not found in PATH after install"

# ── 4. Initialise config ─────────────────────────────────────────────────────
if [ ! -f "$CONFIG_ENV" ]; then
    log "Creating config at $CONFIG_ENV..."
    fcc-init
    log ""
    log "  *** Edit $CONFIG_ENV with your API keys before starting the service ***"
    log ""
else
    log "Config already exists at $CONFIG_ENV — skipping fcc-init."
fi

# ── 5. Install systemd service ───────────────────────────────────────────────
[ -f "$SERVICE_SRC" ] || die "Service template not found: $SERVICE_SRC"
[ "$(id -u)" -ne 0 ] || die "Run this script as a normal user, not root."

CURRENT_USER="$(id -un)"
CURRENT_HOME="$HOME"

log "Installing systemd service as user '$CURRENT_USER'..."
sed \
    -e "s|__FCC_USER__|${CURRENT_USER}|g" \
    -e "s|__FCC_HOME__|${CURRENT_HOME}|g" \
    "$SERVICE_SRC" \
    | sudo tee "$SERVICE_DST" > /dev/null

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"

# ── 6. Start (or restart) the service ───────────────────────────────────────
if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
    log "Restarting $SERVICE_NAME..."
    sudo systemctl restart "$SERVICE_NAME"
else
    log "Starting $SERVICE_NAME..."
    sudo systemctl start "$SERVICE_NAME"
fi

log ""
log "Done. Useful commands:"
log "  sudo systemctl status $SERVICE_NAME"
log "  sudo journalctl -u $SERVICE_NAME -f"
log "  sudo systemctl restart $SERVICE_NAME"
log "  sudo systemctl stop $SERVICE_NAME"
