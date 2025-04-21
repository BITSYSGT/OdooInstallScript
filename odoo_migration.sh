#!/bin/bash

# ╭────────────────────────────────────────────────────────────╮
# │ ODOO MIGRATION TOOL - RESTAURACIÓN MEJORADA                │
# │ Autor: Bit Systems, S.A.                                   │
# │ Soporte: https://bitsys.odoo.com                           │
# │ Compatible: Ubuntu 22.04+ / Odoo 15.0+                     │
# ╰────────────────────────────────────────────────────────────╯

clear

echo "╭────────────────────────────────────────────────────────────╮"
echo "│ ODOO MIGRATION TOOL - RESTAURACIÓN MEJORADA                │"
echo "│ Autor: Bitsys | GT                                         │"
echo "│ Soporte: https://bitsys.odoo.com                           │"
echo "│ Compatible: Ubuntu 22.04+ / Odoo 15.0+                     │"
echo "╰────────────────────────────────────────────────────────────╯"

# Función para restaurar backup limpiamente
restore_clean_backup() {
    local db_name=$1
    local backup_file=$2
    
    echo "🔄 Restaurando backup de manera limpia..."
    
    # 1. Eliminar la base de datos existente si está corrupta
    if sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$db_name"; then
        echo "🔹 Eliminando base de datos corrupta..."
        sudo -u postgres psql -c "DROP DATABASE \"$db_name\";"
    fi
    
    # 2. Crear nueva base de datos vacía
    echo "🔹 Creando nueva base de datos..."
    sudo -u postgres psql -c "CREATE DATABASE \"$db_name\";"
    
    # 3. Restaurar el backup omitiendo constraints
    echo "🔹 Restaurando datos (omitir constraints)..."
    sudo -u postgres pg_restore -F c -d "$db_name" "$backup_file" \
        --no-owner \
        --no-privileges \
        --no-comments \
        --disable-triggers \
        --data-only
    
    # 4. Recrear constraints manualmente si es necesario
    echo "🔹 Reconstruyendo estructura..."
    sudo -u postgres pg_restore -F c -d "$db_name" "$backup_file" \
        --section=pre-data \
        --no-data
    
    echo "✅ Restauración limpia completada"
}

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

# Paso 4: Crear respaldo completo (base de datos + filestore)
BACKUP_DIR="/var/lib/postgresql/backups"
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_$(date +%Y%m%d_%H%M%S).dump"
FILESTORE_SOURCE="/var/lib/odoo/.local/share/Odoo/filestore/${DB_NAME}"
FILESTORE_BACKUP="${BACKUP_DIR}/${DB_NAME}_filestore_$(date +%Y%m%d_%H%M%S).tar.gz"

echo "🔧 Creando respaldo completo..."
sudo mkdir -p "$BACKUP_DIR"
sudo chown postgres:postgres "$BACKUP_DIR"

# 1. Respaldar base de datos
echo "🔹 Respaldando base de datos..."
sudo -u postgres pg_dump -F c -f "$BACKUP_FILE" "$DB_NAME" || { echo "❌ Error al respaldar BD"; exit 1; }

# 2. Respaldar filestore si existe
if [ -d "$FILESTORE_SOURCE" ]; then
    echo "🔹 Respaldando filestore..."
    sudo tar -czf "$FILESTORE_BACKUP" -C "$FILESTORE_SOURCE" .
    sudo chown postgres:postgres "$FILESTORE_BACKUP"
else
    echo "⚠️ No se encontró el filestore original en $FILESTORE_SOURCE"
fi

echo "✅ Respaldo completo creado:"
echo "   - Base de datos: $BACKUP_FILE"
echo "   - Filestore: $FILESTORE_BACKUP"

# Paso 5: Configurar entorno de actualización
UPGRADE_DIR="/var/lib/postgresql/odoo_upgrade_${DB_NAME}"
echo "🔧 Configurando entorno de actualización en ${UPGRADE_DIR}..."

sudo rm -rf "$UPGRADE_DIR"
sudo mkdir -p "$UPGRADE_DIR"
sudo chown postgres:postgres "$UPGRADE_DIR"
sudo -u postgres mkdir -p "${UPGRADE_DIR}/filestore"

# Paso 6: Ejecutar herramienta de actualización
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

# Ejecutar como postgres
echo "🔹 Ejecutando actualización como usuario postgres..."
UPGRADE_OUTPUT=$(sudo -u postgres bash -c "$UPGRADE_CMD")

# Verificar éxito de la migración
if ! echo "$UPGRADE_OUTPUT" | grep -q "Upgrade request successfully processed"; then
    echo "❌ Error en la migración:"
    echo "$UPGRADE_OUTPUT"
    
    # Restaurar backup usando método limpio
    restore_clean_backup "$DB_NAME" "$BACKUP_FILE"
    
    exit 1
fi

echo "✅ Migración de base de datos completada"

# Paso 7: Instalar versión objetivo si es necesario
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

# Paso 8: Configurar base de datos migrada
echo "🔧 Configurando base de datos migrada..."

# 1. Cambiar propietario de la base de datos
CURRENT_OWNER=$(sudo -u postgres psql -t -c "SELECT pg_catalog.pg_get_userbyid(d.datdba) FROM pg_catalog.pg_database d WHERE d.datname = '$DB_NAME';" | tr -d ' ')

if [ "$CURRENT_OWNER" != "$TARGET_DB_USER" ]; then
    echo "🔹 Cambiando propietario a ${TARGET_DB_USER}..."
    sudo -u postgres psql -c "ALTER DATABASE \"$DB_NAME\" OWNER TO \"$TARGET_DB_USER\";"
    sudo -u postgres psql -d "$DB_NAME" -c "REASSIGN OWNED BY \"$CURRENT_OWNER\" TO \"$TARGET_DB_USER\";"
fi

# 2. Configurar archivo de configuración
TARGET_CONFIG_FILE="/etc/odoo${TARGET_VERSION_SHORT}.conf"
sudo sed -i "s/^db_name = .*/db_name = $DB_NAME/" "$TARGET_CONFIG_FILE"

# Paso 9: Manejar filestore migrado
NEW_FILESTORE_DIR="/var/lib/odoo${TARGET_VERSION_SHORT}/filestore/${DB_NAME}"
MIGRATED_DB_NAME=$(sudo -u postgres ls /var/lib/postgresql/.local/share/Odoo/filestore/ | grep "${DB_NAME}_test_${TARGET_VERSION}" | head -1)

if [ -n "$MIGRATED_DB_NAME" ]; then
    echo "🔹 Moviendo filestore migrado..."
    sudo mkdir -p "/var/lib/odoo${TARGET_VERSION_SHORT}/filestore"
    sudo mv "/var/lib/postgresql/.local/share/Odoo/filestore/${MIGRATED_DB_NAME}" "$NEW_FILESTORE_DIR"
elif [ -f "$FILESTORE_BACKUP" ]; then
    echo "🔹 Restaurando filestore desde respaldo..."
    sudo mkdir -p "$NEW_FILESTORE_DIR"
    sudo tar -xzf "$FILESTORE_BACKUP" -C "$NEW_FILESTORE_DIR"
else
    echo "⚠️ No se encontró filestore migrado. Deberá copiarlo manualmente:"
    echo "   Desde: /var/lib/odoo/.local/share/Odoo/filestore/${DB_NAME}"
    echo "   Hacia: $NEW_FILESTORE_DIR"
fi

[ -d "$NEW_FILESTORE_DIR" ] && sudo chown -R "odoo${TARGET_VERSION_SHORT}:odoo${TARGET_VERSION_SHORT}" "$NEW_FILESTORE_DIR"

# Paso 10: Reiniciar servicio
echo "🔄 Reiniciando servicio Odoo ${TARGET_VERSION_SHORT}..."
sudo systemctl restart "odoo${TARGET_VERSION_SHORT}.service"

# Paso 11: Mostrar resumen
IP_ADDRESS=$(hostname -I | awk '{print $1}')
DOMAIN_NAME=$(grep 'server_name' /etc/nginx/sites-available/odoo${TARGET_VERSION_SHORT} 2>/dev/null | awk '{print $2}' | head -1 || echo "No configurado")

echo ""
echo "╭───────────────────────────────────────────────────────────────────────────────╮"
echo "│ 🎉 MIGRACIÓN COMPLETA DE ODOO $CURRENT_VERSION a $TARGET_VERSION"
echo "├───────────────────────────────────────────────────────────────────────────────┤"
echo "│ 🔹 Base de datos:       $DB_NAME"
echo "│ 🔹 Versión origen:      $CURRENT_VERSION"
echo "│ 🔹 Versión destino:     $TARGET_VERSION"
echo "│ 🔹 Respaldo BD:         $BACKUP_FILE"
echo "│ 🔹 Respaldo Filestore:  $FILESTORE_BACKUP"
echo "│ 🔹 Filestore nuevo:     $NEW_FILESTORE_DIR"
echo "│ 🔹 Propietario DB:      $TARGET_DB_USER"
echo "│ 🔹 Puerto:              $TARGET_PORT"
echo "├───────────────────────────────────────────────────────────────────────────────┤"
echo "│ 🔗 Accesos:"
echo "│    - Directo:          http://${IP_ADDRESS}:${TARGET_PORT}"
echo "│    - Web:              https://${DOMAIN_NAME}"
echo "╰───────────────────────────────────────────────────────────────────────────────╯"

# Limpieza final
sudo rm -rf "$UPGRADE_DIR"