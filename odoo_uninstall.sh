#!/bin/bash

# ╭────────────────────────────────────────────────────────────╮
# │ ODOO INSTALLER MULTIINSTANCIA                              │
# │ Autor: Bit Systems, S.A.                                   │
# │ Soporte: https://bitsys.odoo.com                           │
# │ Compatible: Ubuntu 22.04+ / Odoo 18.0                      │
# ╰────────────────────────────────────────────────────────────╯

# 🧠 Detectar versión del sistema
OS_VERSION=$(lsb_release -rs)
if [[ "$OS_VERSION" != "22.04" && "$OS_VERSION" != "24.04" ]]; then
  echo "⚠️ Este script está diseñado para Ubuntu 22.04 o 24.04. Puede no funcionar correctamente en otras versiones."
  read -p "¿Deseas continuar de todos modos? (s/N): " continue_anyway
  [[ "$continue_anyway" != "s" && "$continue_anyway" != "S" ]] && exit 1
fi

# 🔍 Buscar instancias instaladas
echo "🔎 Buscando instancias instaladas de Odoo..."
ODOO_USERS=($(getent passwd | grep '^odoo[0-9]\{4\}' | cut -d: -f1))
if [[ ${#ODOO_USERS[@]} -eq 0 ]]; then
  echo "❌ No se encontraron instancias de Odoo instaladas."
  exit 1
fi

# Mostrar menú de selección
echo ""
echo "Instancias encontradas:"
i=1
for user in "${ODOO_USERS[@]}"; do
  PORT=${user:4}
  HOME="/opt/$user"
  VERSION="desconocida"
  [[ -f "$HOME/odoo-bin" ]] && VERSION=$($HOME/odoo-bin --version 2>/dev/null | awk '{print $NF}')
  echo "  $i) $user (Puerto: $PORT, Versión: $VERSION)"
  OPTIONS[$i]=$user
  ((i++))
done
echo "  0) Desinstalar TODAS las instancias anteriores"
echo ""

# Leer opción
read -p "👉 Selecciona una opción para desinstalar: " choice
echo ""

# Si elige 0, desinstalar todas
if [[ "$choice" == "0" ]]; then
  SELECTED_USERS=("${ODOO_USERS[@]}")
else
  SELECTED_USER="${OPTIONS[$choice]}"
  if [[ -z "$SELECTED_USER" ]]; then
    echo "❌ Opción inválida."
    exit 1
  fi
  SELECTED_USERS=("$SELECTED_USER")
fi

# Desinstalar instancia(s)
for OE_USER in "${SELECTED_USERS[@]}"; do
  echo "=============================="
  echo "🚮 Eliminando instancia $OE_USER..."
  OE_PORT=${OE_USER:4}
  OE_HOME="/opt/$OE_USER"
  OE_CONFIG="/etc/$OE_USER.conf"
  OE_SERVICE="/etc/systemd/system/$OE_USER.service"
  OE_ENTERPRISE="$OE_HOME/enterprise"

  ODOO_VERSION="desconocida"
  [[ -f "$OE_HOME/odoo-bin" ]] && ODOO_VERSION=$($OE_HOME/odoo-bin --version 2>/dev/null | awk '{print $NF}')

  # Confirmar por instancia
  read -p "⚠️ ¿Estás seguro de eliminar Odoo $ODOO_VERSION en el puerto $OE_PORT? (s/N): " confirm
  [[ "$confirm" != "s" && "$confirm" != "S" ]] && echo "❌ Cancelado." && continue

  echo "🛑 Deteniendo servicio..."
  systemctl stop $OE_USER 2>/dev/null
  systemctl disable $OE_USER 2>/dev/null
  rm -f "$OE_SERVICE"

  echo "🧹 Eliminando archivos..."
  rm -rf "$OE_HOME" "$OE_CONFIG" "/etc/$OE_USER" "/var/log/$OE_USER"
  [[ -d "$OE_ENTERPRISE" ]] && rm -rf "$OE_ENTERPRISE"

  echo "👤 Eliminando usuario del sistema..."
  userdel -r "$OE_USER" 2>/dev/null

  echo "🗃️ Eliminando rol de PostgreSQL..."
  sudo -u postgres psql -c "DROP ROLE IF EXISTS $OE_USER;" &>/dev/null

  echo "✅ Instancia $OE_USER eliminada."
  echo ""
done

# Opcional: PostgreSQL
read -p "¿Deseas eliminar PostgreSQL completamente? (s/N): " delpg
if [[ "$delpg" == "s" || "$delpg" == "S" ]]; then
  echo "🧨 Eliminando PostgreSQL y sus datos..."
  apt-get purge -y postgresql*
  apt-get autoremove -y
  rm -rf /var/lib/postgresql /etc/postgresql
fi

# Opcional: Nginx y Certbot
read -p "¿Deseas eliminar Nginx y Certbot también? (s/N): " delweb
if [[ "$delweb" == "s" || "$delweb" == "S" ]]; then
  echo "🧹 Eliminando Nginx y Certbot..."
  apt-get purge -y nginx certbot python3-certbot-nginx
  apt-get autoremove -y
fi

echo ""
echo "🎉 Desinstalación completada."
