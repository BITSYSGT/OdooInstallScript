#!/bin/bash

#====================================================
# Autor: Bit Systems, S.A.
# Script para instalar Odoo 18 en Ubuntu 24.04 LTS
#====================================================

OE_USER="odoo"
OE_HOME="/opt/$OE_USER"
OE_VERSION="18.0"
OE_PORT="8070"
OE_SUPERADMIN="odoo"
OE_CONFIG="/etc/odoo.conf"
LOGFILE="/var/log/odoo/odoo.log"
ENTERPRISE_REPO="https://github.com/odoo/enterprise.git"
ADMIN_PASSWORD=$(openssl rand -hex 16)

echo "---- ¿Instalar versión Enterprise? (s/n) ----"
read INSTALL_ENTERPRISE

if [[ "$INSTALL_ENTERPRISE" == "s" || "$INSTALL_ENTERPRISE" == "S" ]]; then
    IS_ENTERPRISE=true
    echo "---- ¿Cuál es tu token de acceso a GitHub para clonar el repositorio Enterprise? ----"
    read GITHUB_TOKEN
else
    IS_ENTERPRISE=false
fi

echo "---- Actualizando el sistema ----"
apt-get update && apt-get upgrade -y

echo "---- Instalando dependencias ----"
apt-get install -y python3-dev python3-pip python3-venv build-essential \
    libsasl2-dev libldap2-dev libssl-dev libmysqlclient-dev libjpeg-dev \
    liblcms2-dev libblas-dev libatlas-base-dev libxml2-dev libxslt1-dev \
    zlib1g-dev npm git postgresql libpq-dev gcc

echo "---- Creando usuario del sistema: $OE_USER ----"
adduser --system --home=$OE_HOME --group --disabled-password --shell=/bin/bash $OE_USER

echo "---- Clonando código fuente de Odoo ----"
git config --global http.postBuffer 524288000
git clone https://github.com/odoo/odoo --branch $OE_VERSION --single-branch $OE_HOME
chown -R $OE_USER: $OE_HOME

if [ "$IS_ENTERPRISE" = true ]; then
    echo "---- Clonando módulo Enterprise ----"
    mkdir -p $OE_HOME/enterprise
    git clone https://$GITHUB_TOKEN@github.com/odoo/enterprise.git --branch $OE_VERSION --single-branch $OE_HOME/enterprise
    chown -R $OE_USER: $OE_HOME/enterprise
    ADDONS_PATH="$OE_HOME/addons,$OE_HOME/enterprise"
else
    ADDONS_PATH="$OE_HOME/addons"
fi

echo "---- Creando archivo de configuración ----"
mkdir -p /etc/odoo /var/log/odoo
touch $LOGFILE
chown $OE_USER: $LOGFILE

cat <<EOF > $OE_CONFIG
[options]
xmlrpc_port = $OE_PORT
db_host = False
db_port = False
db_user = $OE_SUPERADMIN
db_password = $OE_SUPERADMIN
addons_path = $ADDONS_PATH
logfile = $LOGFILE
admin_passwd = $ADMIN_PASSWORD
EOF

chmod 640 $OE_CONFIG
chown $OE_USER: $OE_CONFIG

echo "---- Creando base de datos de PostgreSQL ----"
sudo -u postgres psql -c "CREATE ROLE $OE_SUPERADMIN WITH LOGIN SUPERUSER CREATEDB CREATEROLE PASSWORD '$OE_SUPERADMIN';"

echo "---- Instalando dependencias de Python ----"
cd $OE_HOME
pip install --break-system-packages -r requirements.txt

echo "---- Configurando servicio de Odoo ----"
cat <<EOF > /etc/systemd/system/odoo.service
[Unit]
Description=Odoo
Documentation=http://www.odoo.com
After=postgresql.service

[Service]
Type=simple
User=$OE_USER
ExecStart=/usr/bin/python3 $OE_HOME/odoo-bin -c $OE_CONFIG
ExecStop=/bin/kill -SIGTERM \$MAINPID
KillMode=process
KillSignal=SIGINT
TimeoutSec=300

[Install]
WantedBy=default.target
EOF

echo "---- Activando servicio de Odoo ----"
systemctl daemon-reload
systemctl start odoo
systemctl enable odoo

echo "---- Instalando Nginx y Certbot ----"
apt-get install -y nginx certbot python3-certbot-nginx

# Obtener IP del servidor
SERVER_IP=$(hostname -I | awk '{print $1}')

# Mostrar información final
echo ""
echo "======================================================="
echo "  INSTALACIÓN COMPLETA DE ODOO 18 EN UBUNTU 24.04 LTS"
echo "======================================================="
echo "Puerto XMLRPC:        $OE_PORT"
echo "Usuario PostgreSQL:   $OE_SUPERADMIN"
echo "Contraseña PostgreSQL:$OE_SUPERADMIN"
echo "Ruta de instalación:  $OE_HOME"
echo "Ruta del log:         $LOGFILE"
echo "Archivo de config:    $OE_CONFIG"
echo "Ruta de addons:       $ADDONS_PATH"
echo "Master Password:      $ADMIN_PASSWORD"
if [ "$IS_ENTERPRISE" = true ]; then
    echo "Enterprise:           Instalado"
else
    echo "Enterprise:           No instalado"
fi
echo "Accede a Odoo en:     http://$SERVER_IP:$OE_PORT"
echo "======================================================="
