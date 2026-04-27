#!/data/data/com.termux/files/usr/bin/bash
# =============================================================
#  free-claude-code — Termux setup
#  Ejecutar UNA sola vez en Termux:
#    curl -fsSL https://raw.githubusercontent.com/titanseballos/free-claude-code/main/termux-setup.sh | bash
# =============================================================
set -e

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; exit 1; }

echo ""
echo "================================================="
echo "  free-claude-code — Configuración en Termux"
echo "================================================="
echo ""

# 1. Permisos de almacenamiento
info "Solicitando permisos de almacenamiento..."
termux-setup-storage 2>/dev/null || true

# 2. Actualizar paquetes
info "Actualizando paquetes..."
pkg update -y -o Dpkg::Options::="--force-confold" 2>/dev/null
pkg upgrade -y -o Dpkg::Options::="--force-confold" 2>/dev/null

# 3. Instalar dependencias
info "Instalando openssh, nodejs y git..."
pkg install -y openssh nodejs-lts git

# 4. Instalar Claude Code CLI
info "Instalando Claude Code CLI..."
npm install -g @anthropic-ai/claude-code 2>/dev/null || \
  npm install -g @anthropic-ai/claude-code --unsafe-perm 2>/dev/null

# 5. Configurar SSH
info "Configurando servidor SSH..."
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Generar clave del servidor si no existe
if [ ! -f ~/.ssh/id_rsa ]; then
  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -q
fi

# Puerto por defecto de Termux sshd
SSHD_PORT=8022

# 6. Crear carpeta de trabajo
WORKSPACE="$HOME/claude-workspace"
mkdir -p "$WORKSPACE"
info "Carpeta de trabajo: $WORKSPACE"

# 7. Iniciar sshd
info "Iniciando servidor SSH en puerto $SSHD_PORT..."
pkill sshd 2>/dev/null || true
sshd -p "$SSHD_PORT"

# 8. Obtener información para la PC
PHONE_USER=$(whoami)
PHONE_IP=$(ip route get 1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
if [ -z "$PHONE_IP" ]; then
  PHONE_IP=$(ifconfig 2>/dev/null | grep -oP '(?<=inet )\d+\.\d+\.\d+\.\d+' | grep -v 127 | head -1)
fi

echo ""
echo "================================================="
echo "  ✅  Termux listo"
echo "================================================="
echo ""
echo "  Usuario:  $PHONE_USER"
echo "  IP celular: ${PHONE_IP:-<verificar en Ajustes > Wi-Fi>}"
echo "  Puerto SSH: $SSHD_PORT"
echo "  Workspace:  $WORKSPACE"
echo ""
warn "Paso siguiente en la PC:"
echo ""
echo "  1. Copiá tu clave SSH pública al celular:"
echo "     ssh-copy-id -p $SSHD_PORT ${PHONE_USER}@${PHONE_IP:-<IP_CELULAR>}"
echo ""
echo "  2. Ejecutá el script de configuración de la PC:"
echo "     bash pc-mobile-setup.sh"
echo ""
echo "================================================="
