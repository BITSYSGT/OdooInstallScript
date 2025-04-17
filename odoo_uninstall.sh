#!/bin/bash

# ╭────────────────────────────────────────────────────────────╮
# │ ODOO UNINSTALLER MULTIINSTANCIA                            │
# │ Autor: Bit Systems, S.A.                                   │
# │ Soporte: https://bitsys.odoo.com                           │
# │ Compatible: Ubuntu 22.04+ / Odoo 15-18                     │
# ╰────────────────────────────────────────────────────────────╯

clear

# 🧠 Verificar versión del sistema
OS_VERSION=$(lsb_release -rs)
if [[ "$OS_VERSION" != "22.04" && "$OS_VERSION" != "24.04" ]]; then
  echo "⚠️ Este script está diseñado para Ubuntu 22.04 o 24.04. Puede no funcionar correctamente en otras versiones."
  read -p "¿Deseas continuar de todos modos? (s/N): " continue_anyway
  [[ "$continue_anyway" != "s" && "$continue_anyway" != "S" ]] && exit 1
fi

# 🔍 Solicitar versión de Odoo a desinstalar
read -p "🔍 Ingresa la versión de Odoo a eliminar (15, 16, 17, 18): " ODOO_VERSION

ODOO_USER="odoo$ODOO_VERSION"
ODOO_DIR="/opt/odoo$ODOO_VERSION"
CONFIG_FILE="/etc/odoo$ODOO_VERSION.conf"
SERVICE_FILE="/etc/systemd/system/odoo$ODOO_VERSION.service"
LOG_DIR="/var/log/odoo$ODOO_VERSION"
ENTERPRISE_DIR="$ODOO_DIR/enterprise"

# 🔎 Detectar puerto desde el archivo de configuración
if [[ -f "$CONFIG_FILE" ]]; then
  ODOO_PORT=$(grep "xmlrpc_port" "$CONFIG_FILE" | awk -F= '{print $2}' | xargs)
else
  ODOO_PORT="desconocido"
fi

# 🔎 Detectar versión de Odoo si existe
ODOO_ACTUAL_VERSION="desconocida"
if [[ -f "$ODOO_DIR/odoo-bin" ]]; then
    ODOO_ACTUAL_VERSION=$($ODOO_DIR/odoo-bin --version 2>/dev/null | awk '{print $NF}')
fi

echo "⚠️ Este script eliminará Odoo versión $ODOO_ACTUAL_VERSION que corre como usuario $ODOO_USER y puerto $ODOO_PORT."
read -p "¿Estás seguro? (s/N): " confirm
if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
  echo "❌ Cancelado."
  exit 1
fi

# 🛑 Detener y deshabilitar el servicio
echo "🛑 Deteniendo servicio systemd..."
sudo systemctl stop odoo$ODOO_VERSION
sudo systemctl disable odoo$ODOO_VERSION

# 🧹 Eliminar archivos y configuraciones
echo "🧹 Eliminando archivos y configuraciones..."
sudo rm -rf "$ODOO_DIR"
sudo rm -f "$CONFIG_FILE"
sudo rm -f "$SERVICE_FILE"
sudo rm -rf "$LOG_DIR"

# 👤 Eliminar usuario del sistema
echo "👤 Eliminando usuario del sistema '$ODOO_USER'..."
sudo userdel -r "$ODOO_USER" 2>/dev/null

# 🗃️ Eliminar rol de PostgreSQL
echo "🗃️ Eliminando rol de PostgreSQL '$ODOO_USER'..."
sudo -u postgres psql -c "DROP ROLE IF EXISTS $ODOO_USER;" 2>/dev/null

# ❓ ¿Eliminar PostgreSQL?
read -p "¿Deseas eliminar PostgreSQL también? (s/N): " delpg
if [[ "$delpg" == "s" || "$delpg" == "S" ]]; then
  echo "🧨 Eliminando PostgreSQL y sus datos..."
  sudo apt-get purge -y postgresql*
  sudo apt-get autoremove -y
  sudo rm -rf /var/lib/postgresql /etc/postgresql
fi

# ❓ ¿Eliminar Nginx y Certbot?
read -p "¿Deseas eliminar Nginx y Certbot? (s/N): " delweb
if [[ "$delweb" == "s" || "$delweb" == "S" ]]; then
  echo "🧹 Eliminando Nginx y Certbot..."
  sudo apt-get purge -y nginx certbot python3-certbot-nginx
  sudo apt-get autoremove -y
fi

echo "✅ Desinstalación de Odoo $ODOO_ACTUAL_VERSION completada."
