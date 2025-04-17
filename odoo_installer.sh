#!/bin/bash

# ╭────────────────────────────────────────────────────────────╮
# │ ODOO INSTALLER MULTIINSTANCIA                              │
# │ Autor: Bit Systems, S.A.                                   │
# │ Soporte: https://bitsys.odoo.com                           │
# │ Compatible: Ubuntu 22.04+ / Odoo 18.0                      │
# ╰────────────────────────────────────────────────────────────╯

# Instalar pyfiglet si no está instalado
if ! command -v pyfiglet &>/dev/null; then
    echo "⚠️ pyfiglet no está instalado. Instalando..."
    sudo apt install -y pyfiglet
fi

# Mostrar título artístico con pyfiglet
clear
pyfiglet -c "ODOO MIT" | tee /dev/tty
echo "by Bitsys | GT"

# 🎨 Mostrar título artístico
echo "🔹 Ingrese la versión de Odoo que desea instalar (15, 16, 17, 18): "
read ODOO_VERSION

DEFAULT_PORT="8071"
echo "🔹 Puerto por defecto para Odoo: $DEFAULT_PORT"
read -p "🔹 Ingrese el puerto para Odoo (Enter para usar $DEFAULT_PORT): " PORT
PORT=${PORT:-$DEFAULT_PORT}

read -p "🔹 ¿Deseas instalar la versión Enterprise? (s/N): " INSTALL_ENTERPRISE
INSTALL_ENTERPRISE=${INSTALL_ENTERPRISE,,}  # convertir a minúscula

if [[ "$INSTALL_ENTERPRISE" == "s" ]]; then
    read -p "🔹 Ingresa tu token de acceso a GitHub: " GITHUB_TOKEN
fi

ODOO_USER="odoo$ODOO_VERSION"
ODOO_DIR="/opt/odoo$ODOO_VERSION"
ODOO_REPO="https://github.com/odoo/odoo.git"
ODOO_ENTERPRISE_REPO="https://github.com/odoo/enterprise.git"
CONFIG_FILE="/etc/odoo$ODOO_VERSION.conf"
LOG_FILE="/var/log/odoo$ODOO_VERSION/odoo.log"
SERVICE_FILE="/etc/systemd/system/odoo$ODOO_VERSION.service"
DB_PASSWORD=$ODOO_USER
MASTER_PASSWORD=$(openssl rand -hex 16)

# Paso 1: Verificar sistema y dependencias
echo "🔧 Verificando dependencias del sistema..."
sudo apt update
sudo apt install -y python3-dev python3-pip python3-venv build-essential \
    libsasl2-dev libldap2-dev libssl-dev libmysqlclient-dev \
    libjpeg-dev liblcms2-dev libblas-dev libatlas-base-dev \
    libxml2-dev libxslt1-dev zlib1g-dev npm git postgresql \
    libpq-dev gcc nginx certbot python3-certbot-nginx

# Verificar si nginx está instalado correctamente
echo "🔧 Verificando la instalación de Nginx..."
if ! command -v nginx &>/dev/null; then
    echo "⚠️ Nginx no está instalado correctamente. Instalando Nginx..."
    sudo apt install -y nginx
fi

# Paso 2: Crear usuario si no existe
if id "$ODOO_USER" &>/dev/null; then
    echo "ℹ️ El usuario del sistema '$ODOO_USER' ya existe. Continuando..."
else
    sudo adduser --system --home="$ODOO_DIR" --group "$ODOO_USER"
fi

# Paso 3: Preparar directorio de instalación
if [ -d "$ODOO_DIR" ]; then
    echo "⚠️ La carpeta $ODOO_DIR ya existe. Moviéndola a ${ODOO_DIR}_backup_$(date +%s)"
    sudo mv "$ODOO_DIR" "${ODOO_DIR}_backup_$(date +%s)"
fi
sudo mkdir -p "$ODOO_DIR"
sudo chown $USER:$USER "$ODOO_DIR"

# Paso 4: Mostrar y clonar repositorios
ODOO_BRANCH="${ODOO_VERSION}.0"
echo "📦 Se descargará el repositorio de Odoo desde la rama: $ODOO_BRANCH"
git clone --depth 1
