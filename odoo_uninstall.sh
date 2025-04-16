#!/bin/bash

#==============================
# Script de desinstalación Odoo
# Desarrollado por Bit Systems, S.A.
#==============================

OE_USER="odoo"
OE_HOME="/opt/$OE_USER"
OE_CONFIG="/etc/odoo.conf"
OE_SERVICE="/etc/systemd/system/odoo.service"

echo "⚠️ Este script eliminará Odoo 18 y su configuración."
read -p "¿Estás seguro? (s/N): " confirm
if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
  echo "❌ Cancelado."
  exit 1
fi

echo "🛑 Deteniendo servicio de Odoo..."
systemctl stop odoo
systemctl disable odoo

echo "🧹 Eliminando archivos de Odoo..."
rm -rf $OE_HOME
rm -f $OE_SERVICE
rm -f $OE_CONFIG
rm -rf /etc/odoo
rm -rf /var/log/odoo

echo "👤 Eliminando usuario del sistema '$OE_USER'..."
userdel -r $OE_USER 2>/dev/null

echo "🗃️ Eliminando rol de PostgreSQL 'odoo'..."
sudo -u postgres psql -c "DROP ROLE IF EXISTS odoo;" 2>/dev/null

read -p "¿Quieres eliminar PostgreSQL también? (s/N): " delpg
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

echo "✅ Desinstalación de Odoo 18 completada."
