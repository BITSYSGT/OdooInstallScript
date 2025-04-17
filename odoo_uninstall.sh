#!/bin/bash

# ╭────────────────────────────────────────────────────────────╮
# │ ODOO UNINSTALLER MULTIINSTANCIA                            │
# │ Autor: Bit Systems, S.A.                                   │
# │ Soporte: https://bitsys.odoo.com                           │
# │ Compatible: Ubuntu 22.04+ / Odoo 18.0                      │
# ╰────────────────────────────────────────────────────────────╯

clear

echo "╭────────────────────────────────────────────────────────────╮"
echo "│ ODOO UNINSTALLER MULTITENANT (ODOO MIT)                    │"
echo "│ Autor: Bitsys | GT                                         │"
echo "│ Soporte: https://bitsys.odoo.com                           │"
echo "│ Compatible: Ubuntu 22.04+ / Odoo 18.0                      │"
echo "╰────────────────────────────────────────────────────────────╯"

# Función para verificar si un paquete es necesario
is_package_needed() {
    local package=$1
    # Verificar si otros paquetes instalados dependen de este
    if apt-cache rdepends --installed "$package" | grep -qv "Reverse Depends"; then
        return 0  # Paquete es necesario
    else
        return 1  # Paquete no es necesario
    fi
}

# Función para limpiar Nginx de forma segura
safe_nginx_cleanup() {
    echo "🔧 Limpieza segura de Nginx..."
    
    # Verificar si hay otros sitios configurados
    local other_sites=$(ls /etc/nginx/sites-enabled/ | grep -v "odoo")
    
    if [ -z "$other_sites" ]; then
        echo "ℹ️ No hay otras configuraciones de sitios web detectadas"
        
        # Detener Nginx si está corriendo
        if systemctl is-active --quiet nginx; then
            echo "🛑 Deteniendo servicio Nginx..."
            systemctl stop nginx
        fi
        
        # Desinstalar solo si no es necesario
        if ! is_package_needed nginx; then
            echo "🧹 Desinstalando Nginx y componentes relacionados..."
            apt-get purge -y nginx* python3-certbot-nginx
            apt-get autoremove -y
            rm -rf /etc/nginx /var/log/nginx
        else
            echo "⚠️ Nginx se mantiene instalado (otras dependencias lo requieren)"
            echo "🧹 Limpiando solo configuraciones de Odoo..."
            rm -f /etc/nginx/sites-available/odoo*
            rm -f /etc/nginx/sites-enabled/odoo*
            systemctl restart nginx
        fi
    else
        echo "⚠️ Se detectaron otras configuraciones de sitios web:"
        echo "$other_sites"
        echo "🧹 Solo eliminando configuraciones de Odoo..."
        rm -f /etc/nginx/sites-available/odoo*
        rm -f /etc/nginx/sites-enabled/odoo*
        nginx -t && systemctl reload nginx
    fi
}

# 🧠 Detectar versión del sistema
OS_VERSION=$(lsb_release -rs)
if [[ "$OS_VERSION" != "22.04" && "$OS_VERSION" != "24.04" ]]; then
  echo "⚠️ Este script está diseñado para Ubuntu 22.04 o 24.04. Puede no funcionar correctamente en otras versiones."
  read -p "¿Deseas continuar de todos modos? (s/N): " continue_anyway
  [[ "$continue_anyway" != "s" && "$continue_anyway" != "S" ]] && exit 1
fi

# 🔍 Buscar instancias instaladas
echo "🔎 Buscando instancias instaladas de Odoo..."
ODOO_USERS=($(getent passwd | grep '^odoo[0-9]\{2,4\}' | cut -d: -f1))
if [[ ${#ODOO_USERS[@]} -eq 0 ]]; then
  echo "❌ No se encontraron instancias de Odoo instaladas."
  exit 1
fi

# Mostrar menú de selección
echo ""
echo "Instancias encontradas:"
i=1
for user in "${ODOO_USERS[@]}"; do
  PORT=$(grep -oP '[0-9]+$' <<< "$user" || echo "desconocido")
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
  OE_PORT=$(grep -oP '[0-9]+$' <<< "$OE_USER" || echo "desconocido")
  OE_HOME="/opt/$OE_USER"
  OE_CONFIG="/etc/$OE_USER.conf"
  OE_SERVICE="/etc/systemd/system/$OE_USER.service"
  OE_ENTERPRISE="$OE_HOME/enterprise"
  OE_NGINX_CONFIG="/etc/nginx/sites-available/$OE_USER"

  ODOO_VERSION="desconocida"
  [[ -f "$OE_HOME/odoo-bin" ]] && ODOO_VERSION=$($OE_HOME/odoo-bin --version 2>/dev/null | awk '{print $NF}')

  # Confirmar por instancia
  read -p "⚠️ ¿Estás seguro de eliminar Odoo $ODOO_VERSION en el puerto $OE_PORT? (s/N): " confirm
  [[ "$confirm" != "s" && "$confirm" != "S" ]] && echo "❌ Cancelado." && continue

  echo "🛑 Deteniendo servicio..."
  systemctl stop $OE_USER 2>/dev/null
  systemctl disable $OE_USER 2>/dev/null
  rm -f "$OE_SERVICE"
  systemctl daemon-reload

  echo "🧹 Eliminando archivos..."
  rm -rf "$OE_HOME" "$OE_CONFIG" "/etc/$OE_USER" "/var/log/$OE_USER"
  [[ -d "$OE_ENTERPRISE" ]] && rm -rf "$OE_ENTERPRISE"

  echo "👤 Eliminando usuario del sistema..."
  userdel -r "$OE_USER" 2>/dev/null

  echo "🗃️ Eliminando rol de PostgreSQL..."
  sudo -u postgres psql -c "DROP ROLE IF EXISTS $OE_USER;" &>/dev/null

  # Eliminar configuración de Nginx si existe
  if [[ -f "$OE_NGINX_CONFIG" ]]; then
    echo "🌐 Eliminando configuración de Nginx..."
    rm -f "$OE_NGINX_CONFIG"
    rm -f "/etc/nginx/sites-enabled/$OE_USER"
    nginx -t && systemctl reload nginx
  fi

  echo "✅ Instancia $OE_USER eliminada."
  echo ""
done

# Opcional: PostgreSQL
read -p "¿Deseas eliminar PostgreSQL completamente? (s/N): " delpg
if [[ "$delpg" == "s" || "$delpg" == "S" ]]; then
  echo "🧨 Verificando dependencias de PostgreSQL..."
  if ! is_package_needed postgresql; then
    echo "🗑️ Eliminando PostgreSQL y sus datos..."
    apt-get purge -y postgresql*
    apt-get autoremove -y
    rm -rf /var/lib/postgresql /etc/postgresql
  else
    echo "⚠️ PostgreSQL se mantiene instalado (otras dependencias lo requieren)"
  fi
fi

# Opcional: Nginx y Certbot
read -p "¿Deseas eliminar Nginx y Certbot también? (s/N): " delweb
if [[ "$delweb" == "s" || "$delweb" == "S" ]]; then
  safe_nginx_cleanup
  
  echo "🔍 Verificando dependencias de Certbot..."
  if ! is_package_needed certbot; then
    echo "🧹 Eliminando Certbot..."
    apt-get purge -y certbot python3-certbot-nginx
    apt-get autoremove -y
  else
    echo "⚠️ Certbot se mantiene instalado (otras dependencias lo requieren)"
  fi
fi

# Limpieza final de paquetes no necesarios
echo "🧽 Limpieza final de paquetes..."
apt-get autoremove -y

echo ""
echo "🎉 Desinstalación completada."
echo "╭────────────────────────────────────────────────────────────╮"
echo "│ ℹ️  Recomendaciones:                                       |"
echo "│ 1. Verifica con 'dpkg --list | grep odoo' si quedan paq.   │"
echo "│ 2. Revisa /opt/ para eliminar directorios residuales       │"
echo "│ 3. Ejecuta 'sudo apt autoremove' para limpieza final       │"
echo "╰────────────────────────────────────────────────────────────╯"