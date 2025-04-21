#!/bin/bash

# ╭────────────────────────────────────────────────────────────╮
# │ ODOO INSTALLER MULTIINSTANCIA                              │
# │ Autor: Bit Systems, S.A.                                   │
# │ Soporte: https://bitsys.odoo.com                           │
# │ Compatible: Ubuntu 22.04+ / Odoo 15.0+                     │
# ╰────────────────────────────────────────────────────────────╯

clear

echo "╭────────────────────────────────────────────────────────────╮"
echo "│ ODOO INSTALLER MULTITENANT (ODOO MIT)                      │"
echo "│ Autor: Bitsys | GT                                         │"
echo "│ Soporte: https://bitsys.odoo.com                           │"
echo "│ Compatible: Ubuntu 22.04+ / Odoo 15.0+                     │"
echo "╰────────────────────────────────────────────────────────────╯"

# Función para verificar si un puerto está en uso
check_port() {
    local port=$1
    if ss -tuln | grep -q ":$port "; then
        return 0  # Puerto en uso
    else
        return 1  # Puerto disponible
    fi
}

# Función para encontrar puerto disponible
find_available_port() {
    local base_port=$1
    local increment=0
    local max_attempts=20
    local found_port=0
    
    while [ $increment -lt $max_attempts ]; do
        local test_port=$((base_port + increment))
        if ! check_port $test_port; then
            found_port=$test_port
            break
        fi
        ((increment++)) 
    done
    
    echo $found_port
}

# Paso 0: Configuración inicial
read -p "🔹 Ingrese la versión de Odoo que desea instalar (15, 16, 17, 18): " ODOO_VERSION

DEFAULT_PORT="8069"

# Verificar si el puerto por defecto está disponible
if check_port $DEFAULT_PORT; then
    echo "⚠️ El puerto por defecto $DEFAULT_PORT está en uso."
    AVAILABLE_PORT=$(find_available_port $DEFAULT_PORT)
    
    if [ $AVAILABLE_PORT -eq 0 ]; then
        echo "❌ No se encontró un puerto disponible automáticamente."
        read -p "🔹 Ingrese manualmente el puerto para Odoo: " PORT
    else
        echo "🔹 Se recomienda usar el puerto: $AVAILABLE_PORT"
        read -p "🔹 Ingrese el puerto para Odoo (Enter para usar $AVAILABLE_PORT): " PORT
        PORT=${PORT:-$AVAILABLE_PORT}
    fi
else
    echo "✅ Puerto $DEFAULT_PORT está disponible."
    read -p "🔹 Ingrese el puerto para Odoo (Enter para usar $DEFAULT_PORT): " PORT
    PORT=${PORT:-$DEFAULT_PORT}
fi

# Verificar nuevamente el puerto seleccionado
while check_port $PORT; do
    echo "❌ El puerto $PORT ya está en uso. Por favor elija otro."
    read -p "🔹 Ingrese un puerto diferente: " PORT
done

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
LOG_DIR="/var/log/odoo$ODOO_VERSION"
LOG_FILE="$LOG_DIR/odoo.log"
SERVICE_FILE="/etc/systemd/system/odoo$ODOO_VERSION.service"
DB_PASSWORD=$(openssl rand -hex 12)
MASTER_PASSWORD=$(openssl rand -hex 16)

# Paso 1: Verificar sistema y dependencias
echo "🔧 Verificando dependencias del sistema..."
sudo apt update
sudo apt install -y python3-dev python3-pip python3-venv build-essential \
    libsasl2-dev libldap2-dev libssl-dev libmysqlclient-dev \
    libjpeg-dev liblcms2-dev libblas-dev libatlas-base-dev \
    libxml2-dev libxslt1-dev zlib1g-dev npm git postgresql \
    libpq-dev gcc nginx certbot python3-certbot-nginx \
    libfreetype6-dev libzip-dev libwebp-dev libtiff5-dev \
    libopenjp2-7-dev libharfbuzz-dev libfribidi-dev libxcb1-dev

# Paso 2: Configuración de PostgreSQL
echo "🔧 Configurando PostgreSQL..."
sudo -u postgres psql -c "CREATE USER $ODOO_USER WITH PASSWORD '$DB_PASSWORD' CREATEDB;" 2>/dev/null || \
echo "ℹ️ El usuario PostgreSQL $ODOO_USER ya existe. Continuando..."

# Paso 3: Configuración de Nginx
echo "🔧 Configurando Nginx..."
if [ ! -f "/etc/nginx/nginx.conf" ]; then
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

sudo systemctl restart nginx

# Paso 4: Crear usuario si no existe
if id "$ODOO_USER" &>/dev/null; then
    echo "ℹ️ El usuario del sistema '$ODOO_USER' ya existe. Continuando..."
else
    sudo adduser --system --home="$ODOO_DIR" --group "$ODOO_USER"
fi

# Paso 5: Preparar directorio de instalación
if [ -d "$ODOO_DIR" ]; then
    echo "⚠️ La carpeta $ODOO_DIR ya existe. Moviéndola a ${ODOO_DIR}_backup_$(date +%s)"
    sudo mv "$ODOO_DIR" "${ODOO_DIR}_backup_$(date +%s)"
fi
sudo mkdir -p "$ODOO_DIR"
sudo chown $ODOO_USER:$ODOO_USER "$ODOO_DIR"

# Paso 6: Clonar repositorios
ODOO_BRANCH="${ODOO_VERSION}.0"
echo "📦 Descargando Odoo $ODOO_VERSION (rama $ODOO_BRANCH)..."
sudo -u $ODOO_USER git clone --depth 1 --branch $ODOO_BRANCH $ODOO_REPO "$ODOO_DIR/odoo"

if [[ "$INSTALL_ENTERPRISE" == "s" ]]; then
    echo "📦 Clonando Odoo Enterprise $ODOO_VERSION..."
    sudo -u $ODOO_USER git clone --depth 1 --branch $ODOO_BRANCH https://$GITHUB_TOKEN@github.com/odoo/enterprise.git "$ODOO_DIR/enterprise"
fi

# Paso 7: Instalar requisitos en entorno virtual
echo "📦 Creando entorno virtual y instalando dependencias..."
sudo -u $ODOO_USER python3 -m venv "$ODOO_DIR/venv"
sudo -u $ODOO_USER "$ODOO_DIR/venv/bin/pip" install wheel
sudo -u $ODOO_USER "$ODOO_DIR/venv/bin/pip" install -r "$ODOO_DIR/odoo/requirements.txt"

# Instalar manualmente librerías problemáticas
echo "🔧 Instalando dependencias problemáticas específicas..."
sudo -u $ODOO_USER "$ODOO_DIR/venv/bin/pip" install \
    reportlab==3.6.12 \
    decorator==4.4.2 \
    lxml_html_clean==0.1.1 \
    pillow==9.5.0 \
    psycopg2-binary==2.9.9 \
    docutils==0.21.2 \
    zeep==4.3.1

# Paso 8: Crear symlink para odoo-bin
sudo -u $ODOO_USER ln -s "$ODOO_DIR/odoo/odoo-bin" "$ODOO_DIR/odoo-bin"

# Paso 9: Configurar logs
sudo mkdir -p "$LOG_DIR"
sudo chown $ODOO_USER:$ODOO_USER "$LOG_DIR"
sudo touch "$LOG_FILE"
sudo chown $ODOO_USER:$ODOO_USER "$LOG_FILE"

# Paso 10: Crear archivo de configuración
echo "📝 Creando archivo de configuración..."
sudo tee $CONFIG_FILE > /dev/null <<EOF
[options]
admin_passwd = $MASTER_PASSWORD
db_host = False
db_port = False
db_user = $ODOO_USER
db_password = $DB_PASSWORD
addons_path = $ODOO_DIR/odoo/addons${INSTALL_ENTERPRISE:+,$ODOO_DIR/enterprise}
logfile = $LOG_FILE
log_level = info
xmlrpc_port = $PORT
EOF

sudo chown $ODOO_USER:$ODOO_USER $CONFIG_FILE

# Paso 11: Crear archivo systemd
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

# Paso 12: Asignar permisos y habilitar servicio
sudo chown -R $ODOO_USER:$ODOO_USER "$ODOO_DIR"
sudo systemctl daemon-reload
sudo systemctl enable odoo$ODOO_VERSION
sudo systemctl start odoo$ODOO_VERSION

# Paso 13: Configuración de Nginx y Certbot
echo "🔧 Configurando Nginx y Certbot..."
DOMAIN=""
while [ -z "$DOMAIN" ]; do
    read -p "🔹 Ingrese el dominio para Odoo (ej: odoo.midominio.com): " DOMAIN
done

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

    location /longpolling {
        proxy_pass http://127.0.0.1:$((PORT+1));
    }

    gzip_types text/css text/less text/plain text/xml application/xml application/json application/javascript;
    gzip on;
}
EOF

sudo ln -s /etc/nginx/sites-available/odoo$ODOO_VERSION /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl restart nginx

# Configurar Certbot si el dominio resuelve
if ping -c 1 $DOMAIN &> /dev/null; then
    sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN
    sudo systemctl restart nginx
else
    echo "⚠️ El dominio $DOMAIN no resuelve. Configure DNS primero y luego ejecute:"
    echo "   sudo certbot --nginx -d $DOMAIN"
fi

# Paso 14: Mostrar resumen de instalación
IP=$(hostname -I | awk '{print $1}')
ADDONS_PATH="$ODOO_DIR/odoo/addons"
if [[ "$INSTALL_ENTERPRISE" == "s" ]]; then
    ADDONS_PATH="$ADDONS_PATH,$ODOO_DIR/enterprise"
    ENTERPRISE_STATUS="✅ Instalado"
else
    ENTERPRISE_STATUS="❌ No instalado"
fi

echo ""
echo "╭───────────────────────────────────────────────────────────────────────────────╮"
echo "│ 🎉 INSTALACIÓN COMPLETA DE ODOO $ODOO_VERSION"
echo "├───────────────────────────────────────────────────────────────────────────────┤"
echo "│ 🔹 Puerto:             $PORT"
echo "│ 🔹 Usuario:            $ODOO_USER"
echo "│ 🔹 Contraseña DB:      $DB_PASSWORD"
echo "│ 🔹 Master Password:    $MASTER_PASSWORD"
echo "│ 🔹 Ruta instalación:   $ODOO_DIR"
echo "│ 🔹 Archivo configuración: $CONFIG_FILE"
echo "│ 🔹 Addons Path:        $ADDONS_PATH"
echo "│ 🔹 Enterprise:         $ENTERPRISE_STATUS"
echo "├───────────────────────────────────────────────────────────────────────────────┤"
echo "│ 📋 Archivos importantes:"
echo "│    - Configuración:   $CONFIG_FILE"
echo "│    - Logs:            $LOG_FILE"
echo "│    - Servicio:        $SERVICE_FILE"
echo "├───────────────────────────────────────────────────────────────────────────────┤"
echo "│ 🔗 Accesos:"
echo "│    - Directo:         http://$IP:$PORT"
echo "│    - Nginx:           http://$DOMAIN"
echo "│    - Nginx (SSL):     https://$DOMAIN"
echo "├───────────────────────────────────────────────────────────────────────────────┤"
echo "│ ⚙️  Comandos útiles:"
echo "│    - Iniciar:        sudo systemctl start odoo$ODOO_VERSION"
echo "│    - Detener:        sudo systemctl stop odoo$ODOO_VERSION"
echo "│    - Reiniciar:      sudo systemctl restart odoo$ODOO_VERSION"
echo "│    - Ver logs:       journalctl -u odoo$ODOO_VERSION -f"
echo "│    - Ver logs:       sudo tail -f $LOG_FILE"
echo "│    - Ver logs Nginx: sudo tail -f /var/log/nginx/odoo$ODOO_VERSION.error.log"
echo "╰───────────────────────────────────────────────────────────────────────────────╯"
echo ""
echo "⚠️ IMPORTANTE: Guarde esta información en un lugar seguro ⚠️"