#!/bin/bash

# ╭────────────────────────────────────────────────────────────╮
# │ ODOO UNINSTALLER MULTIINSTANCIA                            │
# │ Autor: Bit Systems, S.A.                                   │
# │ Soporte: https://bitsys.odoo.com                           │
# │ Compatible: Ubuntu 22.04+ / Odoo 15-18                     │
# ╰────────────────────────────────────────────────────────────╯

clear

set -e

# Detectar versión de Ubuntu
OS_VERSION=$(lsb_release -rs)
if [[ "$OS_VERSION" != "22.04" && "$OS_VERSION" != "24.04" ]]; then
  echo "⚠️ Este script está diseñado para Ubuntu 22.04 o 24.04. Puede no funcionar correctamente en otras versiones."
  read -p "¿Deseas continuar de todos modos? (s/N): " continue_anyway
  [[ "$continue_anyway" != "s" && "$continue_anyway" != "S" ]] && exit 1
fi

echo "🔍 Buscando versiones de Odoo instaladas..."
ODOO_USERS=($(ls /opt | grep -Po '^odoo\d+$'))

if [ ${#ODOO_USERS[@]} -eq 0 ]; then
  echo "❌ No se encontraron instalaciones de Odoo."
  exit 1
fi

echo ""
echo "🔎 Instancias encontradas:"
select OE_USER in "${ODOO_USERS[@]}" "Eliminar TODAS"; do
  [[ -z "$OE_USER" ]] && echo "Opción inválida. Intenta de nuevo." && continue
  break
done

delete_instance() {
  local OE_USER=$1
  local OE_HOME="/opt/$OE_USER"
  local OE_CONFIG="/etc/${OE_USER}.conf"
  local OE_SERVICE="/etc/systemd/system/${OE_USER}.service"
  local OE_ENTERPRISE="$OE_HOME/enterprise"

  local OE_PORT="desconocido"
  [[ -f "$OE_CONFIG" ]] && OE_PORT=$(grep -Po '(?<=xmlrpc_port = )\d+' "$OE_CONFIG")

  local ODOO_VERSION="desconocida"
  [[ -f "$OE_HOME/odoo-bin" ]] && ODOO_VERSION=$($OE_HOME/odoo-bin --version 2>/dev/null | awk '{print $NF}')

  echo "⚠️ Este script eliminará Odoo versión $ODOO_VERSION (usuario: $OE_USER, puerto: $OE_PORT)"
  read -p "¿Estás seguro? (s/N): " confirm
  [[ "$confirm" != "s" && "$confirm" != "S" ]] && echo "❌ Cancelado." && return

  # Detener servicio si existe
  if [[ -f "$OE_SERVICE" ]]; then
    echo "🛑 Deteniendo servicio systemd..."
    systemctl stop "$OE_USER" || true
    systemctl disable "$OE_USER" || true
    rm -f "$OE_SERVICE"
  else
    echo "⚠️ Servicio systemd no encontrado para $OE_USER."
  fi

  echo "🧹 Eliminando archivos y configuraciones..."
  rm -rf "$OE_HOME"
  rm -f "$OE_CONFIG"
  rm -rf "/etc/$OE_USER"
  rm -rf "/var/log/$OE_USER"

  [[ -d "$OE_ENTERPRISE" ]] && rm -rf "$OE_ENTERPRISE"

  echo "👤 Eliminando usuario del sistema '$OE_USER'..."
  userdel -r "$OE_USER" 2>/dev/null || true

  echo "🗃️ Eliminando rol de PostgreSQL '$OE_USER'..."
  sudo -u postgres psql -c "DROP ROLE IF EXISTS $OE_USER;" 2>/dev/null

  echo "✅ Instancia $OE_USER eliminada correctamente."
  echo "----------------------------------------------"
}

if [[ "$OE_USER" == "Eliminar TODAS" ]]; then
  for u in "${ODOO_USERS[@]}"; do
    delete_instance "$u"
  done

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

else
  delete_instance "$OE_USER"
fi

echo "✅ Desinstalación finalizada."