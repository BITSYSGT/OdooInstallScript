#!/bin/bash

# ╭────────────────────────────────────────────────────────────╮
# │ ODOO INSTALLER MULTIINSTANCIA                              │
# │ Autor: Bit Systems, S.A.                                   │
# │ Soporte: https://bitsys.odoo.com                           │
# │ Compatible: Ubuntu 22.04+ / Odoo 18.0                      │
# ╰────────────────────────────────────────────────────────────╯

clear

echo "╭────────────────────────────────────────────────────────────╮"
echo "│ ODOO INSTALLER MULTITENANT (ODOO MIT)                      │"
echo "│ Autor: Bitsys | GT                                         │"
echo "│ Soporte: https://bitsys.odoo.com                           │"
echo "│ Compatible: Ubuntu 22.04+ / Odoo 18.0                      │"
echo "╰────────────────────────────────────────────────────────────╯"

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

# Paso 2: Verificar y configurar Nginx correctamente
echo "🔧 Verificando y configurando Nginx..."
if ! command -v nginx &> /dev/null; then
    echo "⚠️ Nginx no está instalado correctamente. Intentando reinstalar..."
    sudo apt install --reinstall nginx -y
fi

# Crear archivo de configuración básico de nginx si no existe
if [ ! -f "/etc/nginx/nginx.conf" ]; then
    echo "🔧 Creando archivo de configuración básico para Nginx..."
    sudo tee /etc/nginx/nginx.conf > /dev/null <<EOF
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    gzip on;
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF
fi

# Asegurar que los directorios necesarios existan
sudo mkdir -p /etc/nginx/sites-available
sudo mkdir -p /etc/nginx/sites-enabled
sudo mkdir -p /var/log/nginx

# Intentar reiniciar Nginx para aplicar cambios
sudo systemctl restart nginx || {
    echo "⚠️ No se pudo reiniciar Nginx. Solucionando problemas..."
    sudo nginx -t
    sudo systemctl daemon-reload
    sudo systemctl start nginx
}

# Paso 3: Crear usuario si no existe
if id "$ODOO_USER" &>/dev/null; then
    echo "ℹ️ El usuario del sistema '$ODOO_USER' ya existe. Continuando..."
else
    sudo adduser --system --home="$ODOO_DIR" --group "$ODOO_USER"
fi

# Paso 4: Preparar directorio de instalación
if [ -d "$ODOO_DIR" ]; then
    echo "⚠️ La carpeta $ODOO_DIR ya existe. Moviéndola a ${ODOO_DIR}_backup_$(date +%s)"
    sudo mv "$ODOO_DIR" "${ODOO_DIR}_backup_$(date +%s)"
fi
sudo mkdir -p "$ODOO_DIR"
sudo chown $USER:$USER "$ODOO_DIR"

# Paso 5: Mostrar y clonar repositorios
ODOO_BRANCH="${ODOO_VERSION}.0"
echo "📦 Se descargará el repositorio de Odoo desde la rama: $ODOO_BRANCH"
git clone --depth 1 --branch $ODOO_BRANCH $ODOO_REPO "$ODOO_DIR/odoo"

if [[ "$INSTALL_ENTERPRISE" == "s" ]]; then
    echo "📦 Clonando Odoo Enterprise $ODOO_VERSION desde la rama $ODOO_BRANCH..."
    git clone --depth 1 --branch $ODOO_BRANCH https://$GITHUB_TOKEN@github.com/odoo/enterprise.git "$ODOO_DIR/enterprise"
fi

# Paso 6: Instalar requisitos
echo "📦 Instalando dependencias..."
pip install --break-system-packages -r "$ODOO_DIR/odoo/requirements.txt"

# Paso 7: Crear symlink para odoo-bin
ln -s "$ODOO_DIR/odoo/odoo-bin" "$ODOO_DIR/odoo-bin"

# Paso 8: Crear archivo de configuración
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

# Paso 9: Crear archivo systemd
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
ExecStart=$ODOO_DIR/odoo-bin -c $CONFIG_FILE
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF

# Paso 10: Asignar permisos y habilitar servicio
sudo chown -R $ODOO_USER:$ODOO_USER "$ODOO_DIR"
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable odoo$ODOO_VERSION
sudo systemctl start odoo$ODOO_VERSION

# Paso 11: Configuración de Nginx y Certbot (Let's Encrypt)
echo "🔧 Configurando Nginx y Certbot..."

# Crear archivo de configuración de Nginx
DOMAIN="tu-dominio.com"
echo "🔹 Ingrese el dominio de Odoo para la configuración de Nginx: "
read DOMAIN

# Configurar sitio de Nginx para Odoo
sudo tee /etc/nginx/sites-available/odoo$ODOO_VERSION > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    access_log /var/log/nginx/odoo$ODOO_VERSION.access.log;
    error_log /var/log/nginx/odoo$ODOO_VERSION.error.log;

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Crear el enlace simbólico en sites-enabled
sudo ln -s /etc/nginx/sites-available/odoo$ODOO_VERSION /etc/nginx/sites-enabled/

# Verificar configuración de Nginx
sudo nginx -t

# Reiniciar Nginx
sudo systemctl restart nginx

# Si el dominio es válido, configurar Certbot para Let's Encrypt
if curl --head --silent --fail "$DOMAIN" > /dev/null; then
    echo "🔧 Dominio válido, procediendo con la validación de Certbot..."
    sudo certbot --nginx -d $DOMAIN
else
    echo "⚠️ Dominio no válido. Asegúrese de que su dominio apunte a este servidor antes de validar con Certbot."
    echo "Realice la validación de Certbot más tarde cuando el dominio esté correctamente configurado."
fi

# Paso 12: Final
IP=$(hostname -I | awk '{print $1}')
ADDONS_PATH="$ODOO_DIR/odoo/addons"
if [[ "$INSTALL_ENTERPRISE" == "s" ]]; then
    ADDONS_PATH="$ADDONS_PATH, $ODOO_DIR/enterprise"
    ENTERPRISE_STATUS="Instalado"
else
    ENTERPRISE_STATUS="No Instalado"
fi

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
echo "Addons:             $ADDONS_PATH"
echo "Master Password:    $MASTER_PASSWORD"
echo "Enterprise:         $ENTERPRISE_STATUS"
echo "URL:                http://$IP:$PORT"
echo "==================================================="
echo "📌 Comandos para gestionar el servicio:"
echo "  - Iniciar:        sudo systemctl start odoo$ODOO_VERSION"
echo "  - Detener:        sudo systemctl stop odoo$ODOO_VERSION"
echo "  - Reiniciar:      sudo systemctl restart odoo$ODOO_VERSION"
echo "  - Ver estado:     sudo systemctl status odoo$ODOO_VERSION"
echo "  - Ver logs:       tail -f $LOG_FILE"

# Mostrar ruta de Nginx y sites-available
echo "🔧 La configuración de Nginx para Odoo $ODOO_VERSION se encuentra en:"
echo "/etc/nginx/sites-available/odoo$ODOO_VERSION"
echo "🔧 El enlace simbólico a la configuración está en:"
echo "/etc/nginx/sites-enabled/odoo$ODOO_VERSION"