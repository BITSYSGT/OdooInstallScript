#!/bin/bash

# ╭────────────────────────────────────────────────────────────╮
# │ ODOO MIGRATION TOOL - VERSIÓN FINAL                        │
# │ Autor: Bit Systems, S.A.                                   │
# │ Soporte: https://bitsys.odoo.com                           │
# │ Compatible: Ubuntu 22.04+ / Odoo 15.0+                     │
# ╰────────────────────────────────────────────────────────────╯

clear

echo "╭────────────────────────────────────────────────────────────╮"
echo "│ ODOO MIGRATION TOOL - VERSIÓN FINAL                        │"
echo "│ Autor: Bitsys | GT                                         │"
echo "│ Soporte: https://bitsys.odoo.com                           │"
echo "│ Compatible: Ubuntu 22.04+ / Odoo 15.0+                     │"
echo "╰────────────────────────────────────────────────────────────╯"

# Función para asegurar que la versión termine en .0
ensure_version_format() {
    local version=$1
    if [[ "$version" != *.* ]]; then
        version="${version}.0"
    fi
    echo "$version"
}

# Función para limpiar caracteres especiales
clean_input() {
    echo "$1" | tr -cd '[:alnum:]._-'
}

# Función para verificar si una versión de Odoo está instalada
is_version_installed() {
    local version=$1
    local short_version=$(echo "$version" | cut -d. -f1)
    if systemctl list-unit-files | grep -q "odoo${short_version}.service"; then
        return 0
    else
        return 1
    fi
}

# Función para obtener información de instalación de una versión
get_installation_info() {
    local version=$1
    local short_version=$(echo "$version" | cut -d. -f1)
    local config_file="/etc/odoo${short_version}.conf"
    
    if [ ! -f "$config_file" ]; then
        echo "❌ No se encontró el archivo de configuración para Odoo ${version}"
        return 1
    fi
    
    # Extraer información del archivo de configuración
    local db_user=$(grep '^db_user' "$config_file" | cut -d'=' -f2 | tr -d ' ')
    local db_password=$(grep '^db_password' "$config_file" | cut -d'=' -f2 | tr -d ' ')
    local port=$(grep '^xmlrpc_port' "$config_file" | cut -d'=' -f2 | tr -d ' ')
    local addons_path=$(grep '^addons_path' "$config_file" | cut -d'=' -f2 | tr -d ' ')
    
    echo "$db_user,$db_password,$port,$addons_path"
}

# Paso 1: Obtener información de la base de datos a migrar
read -p "🔹 Ingrese el nombre de la base de datos a migrar: " DB_NAME
DB_NAME=$(clean_input "$DB_NAME")

# Verificar si la base de datos existe
if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    echo "❌ La base de datos '$DB_NAME' no existe."
    exit 1
fi

# Paso 2: Obtener información de la versión actual
read -p "🔹 Ingrese la versión actual de Odoo (ej: 16.0): " CURRENT_VERSION
CURRENT_VERSION=$(clean_input "$CURRENT_VERSION")
CURRENT_VERSION=$(ensure_version_format "$CURRENT_VERSION")

# Paso 3: Obtener versión objetivo
read -p "🔹 Ingrese la versión objetivo de Odoo (ej: 17.0): " TARGET_VERSION
TARGET_VERSION=$(clean_input "$TARGET_VERSION")
TARGET_VERSION=$(ensure_version_format "$TARGET_VERSION")

# Obtener versión corta (sin .0) para nombres de servicio
TARGET_VERSION_SHORT=$(echo "$TARGET_VERSION" | cut -d. -f1)
INSTALL_REQUIRED=1

if is_version_installed "$TARGET_VERSION"; then
    echo "✅ Odoo ${TARGET_VERSION} ya está instalado."
    INSTALL_REQUIRED=0
    
    # Obtener información de la instalación existente
    INSTALL_INFO=$(get_installation_info "$TARGET_VERSION")
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    IFS=',' read -r TARGET_DB_USER TARGET_DB_PASSWORD TARGET_PORT TARGET_ADDONS_PATH <<< "$INSTALL_INFO"
else
    echo "ℹ️ Odoo ${TARGET_VERSION} no está instalado. Se procederá a instalarlo."
fi

# Paso 4: Crear respaldo de la base de datos
BACKUP_DIR="/var/lib/postgresql/backups"
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_$(date +%Y%m%d_%H%M%S).dump"

echo "🔧 Creando respaldo de la base de datos..."
sudo mkdir -p "$BACKUP_DIR"
sudo chown postgres:postgres "$BACKUP_DIR"
sudo -u postgres pg_dump -F c -f "$BACKUP_FILE" "$DB_NAME"

if [ $? -ne 0 ]; then
    echo "❌ Error al crear el respaldo de la base de datos."
    exit 1
fi

echo "✅ Respaldo creado en: $BACKUP_FILE"

# Paso 5: Configurar entorno de actualización con permisos adecuados
UPGRADE_DIR="/var/lib/postgresql/odoo_upgrade_${DB_NAME}"
echo "🔧 Configurando entorno de actualización en ${UPGRADE_DIR}..."

# Limpiar directorio existente y crear uno nuevo con permisos adecuados
sudo rm -rf "$UPGRADE_DIR"
sudo mkdir -p "$UPGRADE_DIR"
sudo chown postgres:postgres "$UPGRADE_DIR"
sudo -u postgres mkdir -p "${UPGRADE_DIR}/filestore"

# Paso 6: Copiar filestore original a ubicación esperada
FILESTORE_SOURCE="/var/lib/odoo/.local/share/Odoo/filestore/${DB_NAME}"
FILESTORE_TARGET="/var/lib/postgresql/.local/share/Odoo/filestore/${DB_NAME}"

if [ -d "$FILESTORE_SOURCE" ]; then
    echo "🔧 Copiando filestore a ubicación esperada por la herramienta de actualización..."
    sudo mkdir -p "/var/lib/postgresql/.local/share/Odoo/filestore"
    sudo chown -R postgres:postgres "/var/lib/postgresql/.local"
    sudo -u postgres cp -r "$FILESTORE_SOURCE" "$FILESTORE_TARGET"
else
    echo "⚠️ No se encontró el filestore original en $FILESTORE_SOURCE"
    echo "   El filestore deberá ser migrado manualmente después de la actualización."
fi

# Paso 7: Ejecutar herramienta de actualización de Odoo con permisos controlados
echo "🔄 Ejecutando herramienta de actualización de Odoo..."

# Verificar registro de la base de datos
REGISTRATION_CHECK=$(sudo -u postgres psql -d "$DB_NAME" -t -c "SELECT value FROM ir_config_parameter WHERE key = 'database.enterprise_code';" | tr -d ' ')

if [ -z "$REGISTRATION_CHECK" ]; then
    echo "⚠️ La base de datos no está registrada. Necesita un código de suscripción."
    read -p "🔹 Ingrese el código de contrato (subscription code): " CONTRACT_CODE
    CONTRACT_CODE=$(clean_input "$CONTRACT_CODE")
    
    if [ -z "$CONTRACT_CODE" ]; then
        echo "❌ No se puede continuar sin código de suscripción."
        exit 1
    fi
    
    UPGRADE_CMD="cd '$UPGRADE_DIR' && python3 <(curl -s https://upgrade.odoo.com/upgrade) test -d $DB_NAME -t $TARGET_VERSION --contract $CONTRACT_CODE"
else
    UPGRADE_CMD="cd '$UPGRADE_DIR' && python3 <(curl -s https://upgrade.odoo.com/upgrade) test -d $DB_NAME -t $TARGET_VERSION"
fi

# Ejecutar como postgres con entorno controlado
echo "🔹 Ejecutando actualización como usuario postgres..."
UPGRADE_OUTPUT=$(sudo -u postgres bash -c "$UPGRADE_CMD")

if [[ "$UPGRADE_OUTPUT" != *"Your database is now ready"* ]]; then
    echo "❌ Error durante la actualización:"
    echo "$UPGRADE_OUTPUT"
    echo "ℹ️ Directorio de trabajo: $UPGRADE_DIR"
    
    # Intentar restaurar la base de datos original si falla la actualización
    echo "🔄 Intentando restaurar la base de datos original..."
    sudo -u postgres pg_restore -F c -d "$DB_NAME" "$BACKUP_FILE"
    
    exit 1
fi

echo "✅ Actualización completada con éxito."

# Paso 8: Instalar versión objetivo si es necesario
if [ $INSTALL_REQUIRED -eq 1 ]; then
    echo "🔧 Instalando Odoo ${TARGET_VERSION}..."
    
    INSTALL_SCRIPT="./odoo_install.sh"
    if [ ! -f "$INSTALL_SCRIPT" ]; then
        echo "❌ No se encontró el script de instalación ($INSTALL_SCRIPT)"
        exit 1
    fi
    
    sudo bash "$INSTALL_SCRIPT"
    
    INSTALL_INFO=$(get_installation_info "$TARGET_VERSION")
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    IFS=',' read -r TARGET_DB_USER TARGET_DB_PASSWORD TARGET_PORT TARGET_ADDONS_PATH <<< "$INSTALL_INFO"
fi

# Paso 9: Configurar permisos y propiedad de la base de datos
echo "🔧 Configurando permisos y propiedad de la base de datos..."

CURRENT_OWNER=$(sudo -u postgres psql -t -c "SELECT pg_catalog.pg_get_userbyid(d.datdba) FROM pg_catalog.pg_database d WHERE d.datname = '$DB_NAME';" | tr -d ' ')

if [ "$CURRENT_OWNER" != "$TARGET_DB_USER" ]; then
    echo "🔹 Cambiando propietario a ${TARGET_DB_USER}..."
    sudo -u postgres psql -c "ALTER DATABASE \"$DB_NAME\" OWNER TO \"$TARGET_DB_USER\";"
    sudo -u postgres psql -d "$DB_NAME" -c "REASSIGN OWNED BY \"$CURRENT_OWNER\" TO \"$TARGET_DB_USER\";"
fi

# Paso 10: Migrar el filestore a la nueva ubicación
echo "🔧 Migrando filestore a la nueva versión..."

NEW_FILESTORE_DIR="/var/lib/odoo${TARGET_VERSION_SHORT}/filestore/${DB_NAME}"
if [ -d "$FILESTORE_TARGET" ]; then
    echo "🔹 Moviendo filestore actualizado a la nueva ubicación..."
    sudo mkdir -p "/var/lib/odoo${TARGET_VERSION_SHORT}/filestore"
    sudo mv "$FILESTORE_TARGET" "$NEW_FILESTORE_DIR"
    sudo chown -R "odoo${TARGET_VERSION_SHORT}:odoo${TARGET_VERSION_SHORT}" "$NEW_FILESTORE_DIR"
elif [ -d "$FILESTORE_SOURCE" ]; then
    echo "🔹 Copiando filestore original a la nueva ubicación..."
    sudo mkdir -p "/var/lib/odoo${TARGET_VERSION_SHORT}/filestore"
    sudo cp -r "$FILESTORE_SOURCE" "$NEW_FILESTORE_DIR"
    sudo chown -R "odoo${TARGET_VERSION_SHORT}:odoo${TARGET_VERSION_SHORT}" "$NEW_FILESTORE_DIR"
else
    echo "⚠️ No se encontró el filestore. Deberá ser migrado manualmente."
fi

# Paso 11: Configurar la instancia de Odoo
echo "🔧 Configurando instancia de Odoo ${TARGET_VERSION}..."
TARGET_CONFIG_FILE="/etc/odoo${TARGET_VERSION_SHORT}.conf"

sudo sed -i "s/^db_name = .*/db_name = $DB_NAME/" "$TARGET_CONFIG_FILE"

# Reiniciar servicio
echo "🔄 Reiniciando servicio Odoo ${TARGET_VERSION_SHORT}..."
sudo systemctl restart "odoo${TARGET_VERSION_SHORT}.service"

# Paso 12: Mostrar resumen
IP_ADDRESS=$(hostname -I | awk '{print $1}')
DOMAIN_NAME=$(grep 'server_name' /etc/nginx/sites-available/odoo${TARGET_VERSION_SHORT} 2>/dev/null | awk '{print $2}' | head -1 || echo "No configurado")

echo ""
echo "╭───────────────────────────────────────────────────────────────────────────────╮"
echo "│ 🎉 MIGRACIÓN COMPLETA DE ODOO $CURRENT_VERSION a $TARGET_VERSION"
echo "├───────────────────────────────────────────────────────────────────────────────┤"
echo "│ 🔹 Base de datos:       $DB_NAME"
echo "│ 🔹 Versión origen:      $CURRENT_VERSION"
echo "│ 🔹 Versión destino:     $TARGET_VERSION"
echo "│ 🔹 Respaldo:            $BACKUP_FILE"
echo "│ 🔹 Propietario DB:      $TARGET_DB_USER"
echo "│ 🔹 Puerto:              $TARGET_PORT"
echo "│ 🔹 Filestore:           $NEW_FILESTORE_DIR"
echo "├───────────────────────────────────────────────────────────────────────────────┤"
echo "│ 🔗 Accesos:"
echo "│    - Directo:          http://${IP_ADDRESS}:${TARGET_PORT}"
echo "│    - Web:              https://${DOMAIN_NAME}"
echo "├───────────────────────────────────────────────────────────────────────────────┤"
echo "│ ⚠️  NOTA: Si el filestore no se migró automáticamente, copie manualmente"
echo "│    el contenido de $FILESTORE_SOURCE a $NEW_FILESTORE_DIR"
echo "╰───────────────────────────────────────────────────────────────────────────────╯"

# Limpieza final
sudo rm -rf "$UPGRADE_DIR"