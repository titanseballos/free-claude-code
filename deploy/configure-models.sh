#!/usr/bin/env bash
# Configura los modelos óptimos para Claude Code tool use en el VPS.
# Uso: bash deploy/configure-models.sh
set -euo pipefail

ENV_FILE="$HOME/.config/free-claude-code/.env"

log() { echo "[fcc-config] $*"; }
err() { echo "[fcc-config] ERROR: $*" >&2; exit 1; }

# ── Verificar claude CLI ─────────────────────────────────────────────────────
if ! command -v claude &>/dev/null; then
    log "claude CLI no encontrado. Instalando..."
    if command -v npm &>/dev/null; then
        npm install -g @anthropic-ai/claude-code
    else
        err "npm no encontrado. Instalá Node.js primero: https://nodejs.org"
    fi
fi
log "claude CLI: $(claude --version 2>/dev/null || echo 'instalado')"

# ── Verificar .env ───────────────────────────────────────────────────────────
if [ ! -f "$ENV_FILE" ]; then
    err "No existe $ENV_FILE. Corré primero: bash deploy/setup-vps.sh"
fi
log "Configurando $ENV_FILE..."

# Leer API keys existentes
CURRENT_NIM_KEY=$(grep -E "^NVIDIA_NIM_API_KEY=" "$ENV_FILE" | cut -d= -f2 | tr -d '"' || true)
CURRENT_OR_KEY=$(grep -E "^OPENROUTER_API_KEY=" "$ENV_FILE" | cut -d= -f2 | tr -d '"' || true)

# ── Elegir proveedor ─────────────────────────────────────────────────────────
echo ""
echo "¿Cuál API key tenés?"
echo "  1) NVIDIA NIM  (recomendado, 40 req/min gratis - build.nvidia.com/settings/api-keys)"
echo "  2) OpenRouter  (deepseek gratis - openrouter.ai/keys)"
echo ""
read -rp "Elegí [1/2]: " CHOICE

case "$CHOICE" in
    1)
        if [ -n "$CURRENT_NIM_KEY" ] && [ "$CURRENT_NIM_KEY" != '""' ]; then
            log "API key NVIDIA NIM ya configurada."
            NIM_KEY="$CURRENT_NIM_KEY"
        else
            read -rp "Pegá tu NVIDIA NIM API key (nvapi-...): " NIM_KEY
        fi
        [ -z "$NIM_KEY" ] && err "API key vacía"

        # Actualizar .env con modelos NIM optimizados para tool use
        sed -i "s|^NVIDIA_NIM_API_KEY=.*|NVIDIA_NIM_API_KEY=\"${NIM_KEY}\"|" "$ENV_FILE"
        sed -i "s|^MODEL_OPUS=.*|MODEL_OPUS=\"nvidia_nim/moonshotai/kimi-k2-thinking\"|" "$ENV_FILE"
        sed -i "s|^MODEL_SONNET=.*|MODEL_SONNET=\"nvidia_nim/moonshotai/kimi-k2-thinking\"|" "$ENV_FILE"
        sed -i "s|^MODEL_HAIKU=.*|MODEL_HAIKU=\"nvidia_nim/stepfun-ai/step-3.5-flash\"|" "$ENV_FILE"
        sed -i "s|^MODEL=.*|MODEL=\"nvidia_nim/moonshotai/kimi-k2-thinking\"|" "$ENV_FILE"
        sed -i "s|^NIM_ENABLE_THINKING=.*|NIM_ENABLE_THINKING=true|" "$ENV_FILE"
        log "Modelos NVIDIA NIM configurados (Kimi K2 para tool use)."
        ;;
    2)
        if [ -n "$CURRENT_OR_KEY" ] && [ "$CURRENT_OR_KEY" != '""' ]; then
            log "API key OpenRouter ya configurada."
            OR_KEY="$CURRENT_OR_KEY"
        else
            read -rp "Pegá tu OpenRouter API key (sk-or-...): " OR_KEY
        fi
        [ -z "$OR_KEY" ] && err "API key vacía"

        sed -i "s|^OPENROUTER_API_KEY=.*|OPENROUTER_API_KEY=\"${OR_KEY}\"|" "$ENV_FILE"
        sed -i "s|^MODEL_OPUS=.*|MODEL_OPUS=\"open_router/deepseek/deepseek-r1-0528:free\"|" "$ENV_FILE"
        sed -i "s|^MODEL_SONNET=.*|MODEL_SONNET=\"open_router/deepseek/deepseek-r1-0528:free\"|" "$ENV_FILE"
        sed -i "s|^MODEL_HAIKU=.*|MODEL_HAIKU=\"open_router/stepfun/step-3.5-flash:free\"|" "$ENV_FILE"
        sed -i "s|^MODEL=.*|MODEL=\"open_router/deepseek/deepseek-r1-0528:free\"|" "$ENV_FILE"
        log "Modelos OpenRouter configurados (DeepSeek R1 para tool use)."
        ;;
    *)
        err "Opción inválida"
        ;;
esac

# ── Configurar workspace ─────────────────────────────────────────────────────
CURRENT_WS=$(grep -E "^CLAUDE_WORKSPACE=" "$ENV_FILE" | cut -d= -f2 | tr -d '"' || true)
if [ -z "$CURRENT_WS" ] || [ "$CURRENT_WS" = "./agent_workspace" ]; then
    DEFAULT_WS="$HOME/agent_workspace"
    read -rp "Directorio de trabajo del agente [$DEFAULT_WS]: " WS_INPUT
    WS="${WS_INPUT:-$DEFAULT_WS}"
    mkdir -p "$WS"
    sed -i "s|^CLAUDE_WORKSPACE=.*|CLAUDE_WORKSPACE=\"${WS}\"|" "$ENV_FILE"
    sed -i "s|^ALLOWED_DIR=.*|ALLOWED_DIR=\"${WS}\"|" "$ENV_FILE"
    log "Workspace: $WS"
fi

# ── Reiniciar servicio ───────────────────────────────────────────────────────
if systemctl is-active --quiet free-claude-code 2>/dev/null; then
    log "Reiniciando servicio..."
    sudo systemctl restart free-claude-code
    sleep 2
    sudo systemctl status free-claude-code --no-pager -l | head -15
else
    log "Servicio no activo. Arrancándolo..."
    sudo systemctl start free-claude-code 2>/dev/null || \
        uv run uvicorn server:app --host 0.0.0.0 --port 8082 &
fi

log ""
log "✅ Listo. Ahora tu bot de Telegram puede ejecutar comandos reales en el VPS."
log "   Probá mandando: 'Creá un archivo hola.txt en el workspace con la fecha de hoy'"
