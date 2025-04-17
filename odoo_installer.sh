#!/bin/bash

#===============================================
# Script de instalación multiinstancia Odoo
# Autor: Bit Systems, S.A.
# Compatible con: Ubuntu 22.04 y 24.04 LTS
#===============================================

# 🧠 Detectando sistema operativo...
OS_VERSION=$(lsb_release -rs)
if [[ "$OS_VERSION" != "22.04" && "$OS_VERSION" != "24.04" ]]; then
  echo "⚠️ Este script está diseñado para Ubuntu 22.04 o 24.04. Puede no funcionar correctamente en otras versiones."
  read -p "¿Deseas continuar de todos modos? (s/N): " continue_anyway
  [[ "$continue_anyway" != "s" && "$continue_anyway" != "S" ]] && exit 1
fi

# Solicitar versión de Odoo a instalar
read -p "🔹 Ingrese la versión de Odoo que desea instalar (15, 16, 17, 18): " OE_VERSION
if [[ ! "$OE_VERSION" =~ ^(15|16|17|18)$ ]]; then
  echo "❌ Versión no válida."
  exit 1
fi

# Ajustes de instancia
OE_USER="odoo$OE_VERSION"
OE_HOME="/opt/$OE_USER"
OE_PORT_DEFAULT=$((8068 + (OE_VERSION - 15)))

# Mostramos el valor por defecto y pedimos la entrada
echo "🔹 Puerto por defecto para Odoo: $OE_PORT_DEFAULT"
read -p "🔹 Ingrese el puerto para Odoo (Enter para usar $OE_PORT_DEFAULT): " OE_PORT

# Si el puerto no fue ingresado, asignamos el valor por defecto
OE_PORT=${OE_PORT:-$OE_PORT_DEFAULT}
OE_CONFIG="/etc/${OE_USER}.conf"
OE_SERVICE="/etc/systemd/system/${OE_USER}.service"
LOGFILE="/var/log/${OE_USER}/odoo.log"
OE_SUPERADMIN="$OE_USER"
ADMIN_PASSWORD=$(openssl rand -hex 16)

# Enterprise
echo "🔹 ¿Deseas instalar la versión Enterprise? (s/N): "
read INSTALL_ENTERPRISE
if [[ "$INSTALL_ENTERPRISE" =~ ^[sS]$ ]]; then
  IS_ENTERPRISE=true
  read -p "🔹 Ingresa tu token de acceso a GitHub: " GITHUB_TOKEN
else
  IS_ENTERPRISE=false
fi

# Preparación del sistema
apt-get update && apt-get upgrade -y
apt-get install -y python3-dev python3-pip python3-venv build-essential \
  libsasl2-dev libldap2-dev libssl-dev libmysqlclient-dev libjpeg-dev \
  liblcms2-dev libblas-dev libatlas-base-dev libxml2-dev libxslt1-dev \
  zlib1g-dev npm git postgresql libpq-dev gcc

# Crear usuario
adduser --system --home=$OE_HOME --group --disabled-password --shell=/bin/bash $OE_USER

# Clonar Odoo
git config --global http.postBuffer 524288000
git clone https://github.com/odoo/odoo --branch $OE_VERSION --single-branch $OE_HOME
chown -R $OE_USER: $OE_HOME

# Enterprise
if [ "$IS_ENTERPRISE" = true ]; then
  mkdir -p $OE_HOME/enterprise
  git clone https://$GITHUB_TOKEN@github.com/odoo/enterprise.git --branch $OE_VERSION --single-branch $OE_HOME/enterprise
  chown -R $OE_USER: $OE_HOME/enterprise
  ADDONS_PATH="$OE_HOME/addons,$OE_HOME/enterprise"
else
  ADDONS_PATH="$OE_HOME/addons"
fi

# Configuración
mkdir -p /etc/odoo /var/log/$OE_USER
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

# PostgreSQL
sudo -u postgres psql -c "CREATE ROLE $OE_SUPERADMIN WITH LOGIN SUPERUSER CREATEDB CREATEROLE PASSWORD '$OE_SUPERADMIN';"

# Requisitos Python
cd $OE_HOME
pip install --break-system-packages -r requirements.txt

# Servicio systemd
cat <<EOF > $OE_SERVICE
[Unit]
Description=Odoo $OE_VERSION
After=postgresql.service

[Service]
Type=simple
User=$OE_USER
ExecStart=/usr/bin/python3 $OE_HOME/odoo-bin -c $OE_CONFIG
KillMode=process
KillSignal=SIGINT
TimeoutSec=300

[Install]
WantedBy=default.target
EOF

systemctl daemon-reload
systemctl start $OE_USER
systemctl enable $OE_USER

# Nginx + Certbot
apt-get install -y nginx certbot python3-certbot-nginx

# Mostrar info
SERVER_IP=$(hostname -I | awk '{print $1}')
echo "\n==================================================="
echo "🎉 INSTALACIÓN COMPLETA DE ODOO $OE_VERSION"
echo "===================================================="
echo "Puerto:             $OE_PORT"
echo "Usuario PostgreSQL: $OE_SUPERADMIN"
echo "Contraseña DB:      $OE_SUPERADMIN"
echo "Ruta:               $OE_HOME"
echo "Log:                $LOGFILE"
echo "Config:             $OE_CONFIG"
echo "Addons:             $ADDONS_PATH"
echo "Master Password:    $ADMIN_PASSWORD"
echo "Enterprise:         $( [ "$IS_ENTERPRISE" = true ] && echo 'Sí' || echo 'No')"
echo "URL:                http://$SERVER_IP:$OE_PORT"
echo "===================================================="
echo "📌 Comandos para gestionar el servicio:"
echo "  - Para iniciar el servicio de Odoo:     systemctl start $OE_USER"
echo "  - Para detener el servicio de Odoo:     systemctl stop $OE_USER"
echo "  - Para reiniciar el servicio de Odoo:   systemctl restart $OE_USER"
echo "  - Para verificar el estado del servicio: systemctl status $OE_USER"
echo "===================================================="
