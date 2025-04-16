#!/bin/bash

#====================================================
# Autor: Bit Systems, S.A.
# Script para instalar Odoo 15, 16, 17 o 18 en Ubuntu 24.04 LTS
#====================================================

#=======================
# VERIFICAR SISTEMA OPERATIVO
#=======================
. /etc/os-release
if [[ "$NAME" != "Ubuntu" || "$VERSION_ID" != "24.04" ]]; then
    echo "Este script está diseñado para Ubuntu 24.04 LTS."
    echo "Detectado: $NAME $VERSION_ID"
    read -p "¿Deseas continuar de todas formas? (s/n): " CONTINUE_ANYWAY
    if [[ "$CONTINUE_ANYWAY" != "s" && "$CONTINUE_ANYWAY" != "S" ]]; then
        echo "Abortando instalación."
        exit 1
    fi
fi

#=======================
# CONFIGURACIONES
#=======================
echo "---- ¿Qué versión de Odoo deseas instalar? (15, 16, 17, 18) ----"
read OE_VERSION
if [[ "$OE_VERSION" != "15" && "$OE_VERSION" != "16" && "$OE_VERSION" != "17" && "$OE_VERSION" != "18" ]]; then
    echo "Versión no soportada. Solo se permiten: 15, 16, 17, 18."
    exit 1
fi

OE_USER="odoo"
OE_HOME="/opt/$OE_USER"
OE_PORT="8070"
OE_SUPERADMIN="odoo"
OE_CONFIG="/etc/odoo.conf"
LOGFILE="/var/log/odoo/odoo.log"
ADMIN_PASSWORD=$(openssl rand -hex 16)

echo "---- ¿Instalar versión Enterprise? (s/n) ----"
read INSTALL_ENTERPRISE

if [[ "$INSTALL_ENTERPRISE" == "s" || "$INSTALL_ENTERPRISE" == "S" ]]; then
    IS_ENTERPRISE=true
    echo "---- Ingresa tu token de acceso a GitHub ----"
    read GITHUB_TOKEN
else
    IS_ENTERPRISE=false
fi

#=======================
# ACTUALIZACIÓN E INSTALACIÓN DE DEPENDENCIAS
#=======================
echo "---- Actualizando sistema ----"
apt-get update && apt-get upgrade -y

echo "---- Instalando dependencias del sistema ----"
apt-get install -y python3-dev python3-pip python3-venv build-essential \
    libsasl2-dev libldap2-dev libssl-dev libmysqlclient-dev libjpeg-dev \
    liblcms2-dev libblas-dev libatlas-base-dev libxml2-dev libxslt1-dev \
    zlib1g-dev npm git postgresql libpq-dev gcc wget curl

#=======================
# CREAR USUARIO Y CLONAR REPOSITORIO
#=======================
echo "---- Creando usuario del sistema: $OE_USER ----"
adduser --system --home=$OE_HOME --group --disabled-password --shell=/bin/bash $OE_USER

echo "---- Clonando código fuente de Odoo ----"
git config --global http.postBuffer 524288000
git clone https://github.com/odoo/odoo --branch $OE_VERSION.0 --single-branch $OE_HOME
chown -R $OE_USER: $OE_HOME

#=======================
# CLONAR ENTERPRISE (SI APLICA)
#=======================
if [ "$IS_ENTERPRISE" = true ]; then
    echo "---- Clonando módulos Enterprise ----"
    mkdir -p $OE_HOME/enterprise
    git clone https://$GITHUB_TOKEN@github.com/odoo/enterprise.git --branch $OE_VERSION.0 --single-branch $OE_HOME/enterprise
    chown -R $OE_USER: $OE_HOME/enterprise
    ADDONS_PATH="$OE_HOME/addons,$OE_HOME/enterprise"
else
    ADDONS_PATH="$OE_HOME/addons"
fi

#=======================
# ARCHIVO DE CONFIGURACIÓN
#=======================
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

#=======================
# BASE DE DATOS
#=======================
echo "---- Configurando PostgreSQL ----"
sudo -u postgres psql -c "CREATE ROLE $OE_SUPERADMIN WITH LOGIN SUPERUSER CREATEDB CREATEROLE PASSWORD '$OE_SUPERADMIN';"

#=======================
# DEPENDENCIAS DE PYTHON
#=======================
echo "---- Instalando dependencias de Python ----"
cd $OE_HOME

# Usar requirements.txt según versión
if [[ "$OE_VERSION" == "18" ]]; then
    pip install --break-system-packages -r requirements.txt
else
    case "$OE_VERSION" in
        "15") PYTHON_REQUIREMENTS_URL="https://raw.githubusercontent.com/odoo/odoo/15.0/requirements.txt" ;;
        "16") PYTHON_REQUIREMENTS_URL="https://raw.githubusercontent.com/odoo/odoo/16.0/requirements.txt" ;;
        "17") PYTHON_REQUIREMENTS_URL="https://raw.githubusercontent.com/odoo/odoo/17.0/requirements.txt" ;;
    esac
    wget $PYTHON_REQUIREMENTS_URL -O /tmp/requirements.txt
    pip install --break-system-packages -r /tmp/requirements.txt
fi

#=======================
# SERVICIO SYSTEMD
#=======================
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

systemctl daemon-reload
systemctl start odoo
systemctl enable odoo

#=======================
# NGINX Y CERTBOT
#=======================
echo "---- Instalando Nginx y Certbot ----"
apt-get install -y nginx certbot python3-certbot-nginx

#=======================
# INFO FINAL
#=======================
SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "======================================================="
echo "  INSTALACIÓN COMPLETA DE ODOO $OE_VERSION EN UBUNTU 24.04 LTS"
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
