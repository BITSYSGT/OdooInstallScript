#!/bin/bash

#==============================
# Script de desinstalación de Odoo (15–18)
# Desarrollado por Bit Systems, S.A.
#==============================

OE_USER="odoo"
OE_HOME="/opt/$OE_USER"
OE_CONFIG="/etc/odoo.conf"
OE_SERVICE="/etc/systemd/system/odoo.service"
OE_LOG_DIR="/var/log/odoo"
OE_ETC_DIR="/etc/odoo"

# Obtener versión desde el archivo de configuración
if [[ -f "$OE_CONFIG" ]]; then
  OE_PORT=$(grep "xmlrpc_port" $OE_CONFIG | cut -d'=' -f2 | xargs)
  OE_VERSION=$(sudo grep -Po 'odoo-\K[0-9]+' $OE_HOME/odoo-bin 2>/dev/null || echo "desconocida")
else
  OE_VERSION="desconocida"
fi

echo "⚠️ Este script eliminará Odoo versión $OE_VERSION y su configuración."
read -p "¿Estás seguro de continuar? (s/N): " confirm
if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
  echo "❌ Cancelado."
  exit 1
fi

echo "🛑 Deteniendo servicio de Odoo..."
systemctl stop odoo 2>/dev/null
systemctl disable odoo 2>/dev/null

echo "🧹 Eliminando archivos de Odoo..."
rm -rf $OE_HOME
rm -f $OE_SERVICE
rm -f $OE_CONFIG
rm -rf $OE_ETC_DIR
rm -rf $OE_LOG_DIR

# Eliminar la carpeta Enterprise si existe
if [ -d "$OE_HOME/enterprise" ]; then
  echo "🧹 Eliminando carpeta Enterprise..."
  rm -rf $OE_HOME/enterprise
fi

echo "👤 Eliminando usuario del sistema '$OE_USER'..."
userdel -r $OE_USER 2>/dev/null

echo "🗃️ Eliminando rol de PostgreSQL '$OE_USER'..."
sudo -u postgres psql -c "DROP ROLE IF EXISTS $OE_USER;" 2>/dev/null

read -p "¿Deseas eliminar PostgreSQL también? (s/N): " delpg
if [[ "$delpg" == "s" || "$delpg" == "S" ]]; then
  echo "🧨 Eliminando PostgreSQL y sus datos..."
  apt-get purge -y postgresql*
  apt-get autoremove -y
  rm -rf /var/lib/postgresql /etc/postgresql
fi

read -p "¿Deseas eliminar Nginx y Certbot? (s/N): " delweb
if [[ "$delweb" == "s" || "$delweb" == "S" ]]; then
  echo "🧹 Eliminando Nginx y Certbot..."
  apt-get purge -y nginx certbot python3-certbot-nginx
  apt-get autoremove -y
fi

echo "✅ Desinstalación de Odoo completada."
