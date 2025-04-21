#!/bin/bash

# ╭────────────────────────────────────────────────────────────╮
# │ ODOO MIGRATION TOOL - VERSIÓN FINAL CON FILESTORE          │
# │ Autor: Bit Systems, S.A.                                  │
# │ Soporte: https://bitsys.odoo.com                          │
# │ Compatible: Ubuntu 22.04+ / Odoo 15.0+                    │
# ╰────────────────────────────────────────────────────────────╯

clear

echo "╭────────────────────────────────────────────────────────────╮"
echo "│ ODOO MIGRATION TOOL - VERSIÓN FINAL CON FILESTORE         │"
echo "│ Autor: Bitsys | GT                                        │"
echo "│ Soporte: https://bitsys.odoo.com                          │"
echo "│ Compatible: Ubuntu 22.04+ / Odoo 15.0+                    │"
echo "╰────────────────────────────────────────────────────────────╯"

# Funciones auxiliares
ensure_version_format() {
    echo "$1" | awk -F. '{if(NF==1) print $1".0"; else print $0}'
}

clean_input() {
    echo "$1" | tr -cd '[:alnum:]._-'
}

is_version_installed() {
    local short_version=$(echo "$1" | cut -d. -f1)
    systemctl list-unit-files | grep -q "odoo${short_version}.service"
}

get_installation_info() {
    local short_version=$(echo "$1" | cut -d. -f1)
    local config_file="/etc/odoo${short_version}.conf"
    
    [ ! -f "$config_file" ] && { echo "❌ Config file not found"; return 1; }
    
    echo "$(grep '^db_user' "$config_file" | cut -d'=' -f2 | tr -d ' '),\
$(grep '^db_password' "$config_file" | cut -d'=' -f2 | tr -d ' '),\
$(grep '^xmlrpc_port' "$config_file" | cut -d'=' -f2 | tr -d ' '),\
$(grep '^addons_path' "$config_file" | cut -d'=' -f2 | tr -d ' ')"
}

# Obtener información del usuario
read -p "🔹 Nombre de la base de datos a migrar: " DB_NAME
DB_NAME=$(clean_input "$DB_NAME")

read -p "🔹 Versión actual de Odoo (ej: 16.0): " CURRENT_VERSION
CURRENT_VERSION=$(ensure_version_format "$(clean_input "$CURRENT_VERSION")")

read -p "🔹 Versión objetivo de Odoo (ej: 17.0): " TARGET_VERSION
TARGET_VERSION=$(ensure_version_format "$(clean_input "$TARGET_VERSION")")

# Verificar existencia de la base de datos
if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    echo "❌ La base de datos '$DB_NAME' no existe."
    exit 1
fi

# Configuración inicial
TARGET_VERSION_SHORT=$(echo "$TARGET_VERSION" | cut -d. -f1)
BACKUP_DIR="/var/lib/postgresql/backups"
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_$(date +%Y%m%d_%H%M%S).dump"
FILESTORE_SOURCE="/var/lib/odoo/.local/share/Odoo/filestore/${DB_NAME}"
FILESTORE_BACKUP="${BACKUP_DIR}/${DB_NAME}_filestore_$(date +%Y%m%d_%H%M%S).tar.gz"
UPGRADE_DIR="/var/lib/postgresql/odoo_upgrade_${DB_NAME}"

# Crear respaldos
echo "🔧 Creando respaldos..."
sudo mkdir -p "$BACKUP_DIR"
sudo chown postgres:postgres "$BACKUP_DIR"

# Respaldar base de datos
sudo -u postgres pg_dump -F c -f "$BACKUP_FILE" "$DB_NAME" || { echo "❌ Error al respaldar BD"; exit 1; }

# Respaldar filestore si existe
if [ -d "$FILESTORE_SOURCE" ]; then
    echo "🔹 Respaldando filestore..."
    sudo tar -czf "$FILESTORE_BACKUP" -C "$FILESTORE_SOURCE" .
    sudo chown postgres:postgres "$FILESTORE_BACKUP"
else
    echo "⚠️ No se encontró filestore original en $FILESTORE_SOURCE"
fi

# Preparar entorno de actualización
echo "🔄 Preparando actualización..."
sudo rm -rf "$UPGRADE_DIR"
sudo mkdir -p "$UPGRADE_DIR"
sudo chown postgres:postgres "$UPGRADE_DIR"

# Configurar filestore para la herramienta
FILESTORE_TARGET="/var/lib/postgresql/.local/share/Odoo/filestore/${DB_NAME}"
sudo mkdir -p "/var/lib/postgresql/.local/share/Odoo/filestore"
sudo chown -R postgres:postgres "/var/lib/postgresql/.local"

if [ -f "$FILESTORE_BACKUP" ]; then
    sudo -u postgres mkdir -p "$FILESTORE_TARGET"
    sudo -u postgres tar -xzf "$FILESTORE_BACKUP" -C "$FILESTORE_TARGET"
fi

# Ejecutar actualización
echo "🚀 Ejecutando herramienta de actualización..."
REGISTRATION_CHECK=$(sudo -u postgres psql -d "$DB_NAME" -t -c "SELECT value FROM ir_config_parameter WHERE key = 'database.enterprise_code';" | tr -d ' ')

if [ -z "$REGISTRATION_CHECK" ]; then
    read -p "🔹 Ingrese el código de contrato: " CONTRACT_CODE
    [ -z "$CONTRACT_CODE" ] && { echo "❌ Se requiere código de contrato"; exit 1; }
    UPGRADE_CMD="cd '$UPGRADE_DIR' && python3 <(curl -s https://upgrade.odoo.com/upgrade) test -d $DB_NAME -t $TARGET_VERSION --contract $CONTRACT_CODE"
else
    UPGRADE_CMD="cd '$UPGRADE_DIR' && python3 <(curl -s https://upgrade.odoo.com/upgrade) test -d $DB_NAME -t $TARGET_VERSION"
fi

UPGRADE_OUTPUT=$(sudo -u postgres bash -c "$UPGRADE_CMD")

# Verificar éxito de la migración (nuevo método)
if ! echo "$UPGRADE_OUTPUT" | grep -q "Upgrade request successfully processed"; then
    echo "❌ Error en la migración:"
    echo "$UPGRADE_OUTPUT"
    echo "🔄 Restaurando backup original..."
    sudo -u postgres pg_restore -F c -d "$DB_NAME" "$BACKUP_FILE"
    exit 1
fi

echo "✅ Migración de base de datos completada"

# Instalar versión objetivo si es necesario
if ! is_version_installed "$TARGET_VERSION"; then
    echo "🔧 Instalando Odoo ${TARGET_VERSION}..."
    [ ! -f "./odoo_install.sh" ] && { echo "❌ Script de instalación no encontrado"; exit 1; }
    sudo bash "./odoo_install.sh"
fi

# Configurar base de datos migrada
INSTALL_INFO=$(get_installation_info "$TARGET_VERSION") || exit 1
IFS=',' read -r TARGET_DB_USER TARGET_DB_PASSWORD TARGET_PORT TARGET_ADDONS_PATH <<< "$INSTALL_INFO"

# Cambiar propietario de la base de datos
CURRENT_OWNER=$(sudo -u postgres psql -t -c "SELECT pg_catalog.pg_get_userbyid(d.datdba) FROM pg_catalog.pg_database d WHERE d.datname = '$DB_NAME';" | tr -d ' ')
[ "$CURRENT_OWNER" != "$TARGET_DB_USER" ] && {
    echo "🔹 Cambiando propietario a ${TARGET_DB_USER}..."
    sudo -u postgres psql -c "ALTER DATABASE \"$DB_NAME\" OWNER TO \"$TARGET_DB_USER\";"
    sudo -u postgres psql -d "$DB_NAME" -c "REASSIGN OWNED BY \"$CURRENT_OWNER\" TO \"$TARGET_DB_USER\";"
}

# Configurar archivo de configuración
TARGET_CONFIG_FILE="/etc/odoo${TARGET_VERSION_SHORT}.conf"
sudo sed -i "s/^db_name = .*/db_name = $DB_NAME/" "$TARGET_CONFIG_FILE"

# Manejo del filestore migrado
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

# Reiniciar servicio
echo "🔄 Reiniciando servicio..."
sudo systemctl restart "odoo${TARGET_VERSION_SHORT}.service"

# Mostrar resumen
echo ""
echo "╭──────────────────────────────────────────────────────╮"
echo "│ 🎉 MIGRACIÓN COMPLETA                                │"
echo "├──────────────────────────────────────────────────────┤"
echo "│ Base de datos:   $DB_NAME                            │"
echo "│ Versión origen:  $CURRENT_VERSION                    │"
echo "│ Versión destino: $TARGET_VERSION                     │"
echo "│ Filestore:       $NEW_FILESTORE_DIR                  │"
echo "╰──────────────────────────────────────────────────────╯"