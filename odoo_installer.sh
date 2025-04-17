#!/bin/bash

# ╭────────────────────────────────────────────────────────────╮
# │ ODOO INSTALLER MULTIINSTANCIA                              │
# │ Autor: Bit Systems, S.A.                                   │
# │ Soporte: https://bitsys.odoo.com                           │
# │ Compatible: Ubuntu 22.04+ / Odoo 18.0                      │
# ╰────────────────────────────────────────────────────────────╯

clear
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

# Paso 4: Clonar repositorios
echo "📦 Clonando Odoo Community $ODOO_VERSION..."
git clone --depth 1 --branch $ODOO_VERSION $ODOO_REPO "$ODOO_DIR/odoo"

if [[ "$INSTALL_ENTERPRISE" == "s" ]]; then
    echo "📦 Clonando Odoo Enterprise $ODOO_VERSION..."
    git clone --depth 1 --branch $ODOO_VERSION https://$GITHUB_TOKEN@github.com/odoo/enterprise.git "$ODOO_DIR/enterprise"
fi

# Paso 5: Crear entorno virtual
echo "🐍 Creando entorno virtual en $ODOO_DIR/venv..."
python3 -m venv "$ODOO_DIR/venv"
source "$ODOO_DIR/venv/bin/activate"
pip install -U pip wheel setuptools
pip install -r "$ODOO_DIR/odoo/requirements.txt"

# Paso 6: Crear symlink para odoo-bin
ln -s "$ODOO_DIR/odoo/odoo-bin" "$ODOO_DIR/odoo-bin"

# Paso 7: Crear archivo de configuración
echo "📝 Creando archivo de configuración..."
sudo mkdir -p "$(dirname $LOG_FILE)"
sudo tee $CONFIG_FILE > /dev/null <<EOF
[options]
admin_passwd = $MASTER_PASSWORD
db_host = False
db_port = False
db_user = $ODOO_USER
db_password = $DB_PASSWORD
addons_path = $ODOO_DIR/odoo/addons${INSTALL_ENTERPRISE:+,$ODOO_DIR/enterprise}
logfile = $LOG_FILE
xmlrpc_port = $PORT
EOF

# Paso 8: Crear archivo systemd
echo "🧩 Creando servicio systemd..."
sudo tee $SERVICE_FILE > /dev/null <<EOF
[Unit]
Description=Odoo $ODOO_VERSION
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=odoo$ODOO_VERSION
PermissionsStartOnly=true
User=$ODOO_USER
Group=$ODOO_USER
ExecStart=$ODOO_DIR/venv/bin/python3 $ODOO_DIR/odoo-bin -c $CONFIG_FILE
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF

# Paso 9: Asignar permisos y habilitar servicio
sudo chown -R $ODOO_USER:$ODOO_USER "$ODOO_DIR"
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable odoo$ODOO_VERSION
sudo systemctl start odoo$ODOO_VERSION

# Paso 10: Final
IP=$(hostname -I | awk '{print $1}')
echo ""
echo "==================================================="
echo "🎉 INSTALACIÓN COMPLETA DE ODOO $ODOO_VERSION"
echo "==================================================="
echo "Puerto:             $PORT"
echo "Usuario PostgreSQL: $ODOO_USER"
echo "Contraseña DB:      $DB_PASSWORD"
echo "Ruta:               $ODOO_DIR"
echo "Log:                $LOG_FILE"
echo "Config:             $CONFIG_FILE"
echo "Addons:             ${INSTALL_ENTERPRISE:+Community + Enterprise}"
echo "Master Password:    $MASTER_PASSWORD"
echo "Enterprise:         ${INSTALL_ENTERPRISE^^}"
echo "URL:                http://$IP:$PORT"
echo "==================================================="
echo "📌 Comandos para gestionar el servicio:"
echo "  - Iniciar:        sudo systemctl start odoo$ODOO_VERSION"
echo "  - Detener:        sudo systemctl stop odoo$ODOO_VERSION"
echo "  - Reiniciar:      sudo systemctl restart odoo$ODOO_VERSION"
echo "  - Ver estado:     sudo systemctl status odoo$ODOO_VERSION"
echo "  - Ver logs:       tail -f $LOG_FILE"
