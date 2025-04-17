#!/bin/bash

#==============================
# Script de desinstalación Odoo (Multiinstancia)
# Desarrollado por Bit Systems, S.A.
# Compatible con: Ubuntu 22.04 y 24.04 LTS
#==============================

# 🧠 Detectando sistema operativo...
OS_VERSION=$(lsb_release -rs)
if [[ "$OS_VERSION" != "22.04" && "$OS_VERSION" != "24.04" ]]; then
  echo "⚠️ Este script está diseñado para Ubuntu 22.04 o 24.04. Puede no funcionar correctamente en otras versiones."
  read -p "¿Deseas continuar de todos modos? (s/N): " continue_anyway
  [[ "$continue_anyway" != "s" && "$continue_anyway" != "S" ]] && exit 1
fi

# Solicitar puerto de la instancia a desinstalar
read -p "🔍 Ingresa el número de puerto de la instancia de Odoo a eliminar: " OE_PORT
OE_USER="odoo$OE_PORT"
OE_HOME="/opt/$OE_USER"
OE_CONFIG="/etc/$OE_USER.conf"
OE_SERVICE="/etc/systemd/system/$OE_USER.service"
OE_ENTERPRISE="$OE_HOME/enterprise"

# Detectar versión de Odoo si existe
ODOO_VERSION="desconocida"
if [[ -f "$OE_HOME/odoo-bin" ]]; then
    ODOO_VERSION=$($OE_HOME/odoo-bin --version 2>/dev/null | awk '{print $NF}')
fi

echo "⚠️ Este script eliminará Odoo versión $ODOO_VERSION que corre en el puerto $OE_PORT."
read -p "¿Estás seguro? (s/N): " confirm
if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
  echo "❌ Cancelado."
  exit 1
fi

# 🛑 Detener el servicio de Odoo
echo "🛑 Deteniendo servicio de Odoo ($OE_USER)..."
systemctl stop $OE_USER
systemctl disable $OE_USER

# 🧹 Eliminar archivos de Odoo
echo "🧹 Eliminando archivos de Odoo..."
rm -rf $OE_HOME
rm -f $OE_SERVICE
rm -f $OE_CONFIG
rm -rf /etc/$OE_USER
rm -rf /var/log/$OE_USER

# Eliminar la carpeta Enterprise si fue instalada
if [ -d "$OE_ENTERPRISE" ]; then
  echo "🧹 Eliminando carpeta de Enterprise..."
  rm -rf $OE_ENTERPRISE
fi

# 👤 Eliminar usuario del sistema
echo "👤 Eliminando usuario del sistema '$OE_USER'..."
userdel -r $OE_USER 2>/dev/null

# 🗃️ Eliminar rol de PostgreSQL
echo "🗃️ Eliminando rol de PostgreSQL '$OE_USER'..."
sudo -u postgres psql -c "DROP ROLE IF EXISTS $OE_USER;" 2>/dev/null

# Preguntar si eliminar PostgreSQL
read -p "¿Quieres eliminar PostgreSQL también? (s/N): " delpg
if [[ "$delpg" == "s" || "$delpg" == "S" ]]; then
  echo "🧨 Eliminando PostgreSQL y sus datos..."
  apt-get purge -y postgresql*
  apt-get autoremove -y
  rm -rf /var/lib/postgresql /etc/postgresql
fi

# Preguntar si eliminar Nginx y Certbot
read -p "¿Deseas eliminar Nginx y Certbot? (s/N): " delweb
if [[ "$delweb" == "s" || "$delweb" == "S" ]]; then
  echo "🧹 Eliminando Nginx y Certbot..."
  apt-get purge -y nginx certbot python3-certbot-nginx
  apt-get autoremove -y
fi

echo "✅ Desinstalación de Odoo $ODOO_VERSION en puerto $OE_PORT completada."