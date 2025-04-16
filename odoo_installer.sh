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
OE_SUPERADMIN_PWD="odoo"
OE_CONFIG="/etc/odoo.conf"
LOGFILE="/var/log/odoo/odoo.log"

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

echo "---- Creando archivo de configuración ----"
mkdir -p /etc/odoo
cat <<EOF > $OE_CONFIG
[options]
xmlrpc_port = $OE_PORT
db_host = False
db_port = False
db_user = $OE_SUPERADMIN
db_password = $OE_SUPERADMIN_PWD
addons_path = $OE_HOME/addons
logfile = $LOGFILE
EOF

chmod 640 $OE_CONFIG
chown $OE_USER: $OE_CONFIG

echo "---- Creando base de datos de PostgreSQL ----"
sudo -u postgres psql -c "CREATE ROLE $OE_SUPERADMIN WITH LOGIN SUPERUSER CREATEDB CREATEROLE PASSWORD '$OE_SUPERADMIN_PWD';"

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

echo "---- Fin de la instalación de Odoo 18 ----"
echo "Puedes acceder a Odoo en http://<tu_dominio_o_IP>:$OE_PORT"
