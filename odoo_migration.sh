#!/bin/bash

# ╭────────────────────────────────────────────────────────────╮
# │ ODOO MIGRATION TOOL                                        │
# │ Autor: Bit Systems, S.A.                                   │
# │ Soporte: https://bitsys.odoo.com                           │
# │ Compatible: Ubuntu 22.04+ / Odoo 15.0+                     │
# ╰────────────────────────────────────────────────────────────╯

clear

echo "╭────────────────────────────────────────────────────────────╮"
echo "│ ODOO MIGRATION TOOL                                        │
echo "│ Autor: Bitsys | GT                                         │
echo "│ Soporte: https://bitsys.odoo.com                           │
echo "│ Compatible: Ubuntu 22.04+ / Odoo 15.0+                     │
echo "╰────────────────────────────────────────────────────────────╯"

# Función para limpiar caracteres especiales
clean_input() {
    echo "$1" | tr -cd '[:alnum:]._-'
}

# Función para verificar si una versión de Odoo está instalada
is_version_installed() {
    local version=$1
    if systemctl list-unit-files | grep -q "odoo${version}.service"; then
        return 0
    else
        return 1
    fi
}

# Función para obtener información de instalación de una versión
get_installation_info() {
    local version=$1
    local config_file="/etc/odoo${version}.conf"
    
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

# Paso 2: Obtener información de la versión actual (si es posible)
read -p "🔹 Ingrese la versión actual de Odoo (ej: 16.0): " CURRENT_VERSION
CURRENT_VERSION=$(clean_input "$CURRENT_VERSION")

# Paso 3: Obtener versión objetivo
read -p "🔹 Ingrese la versión objetivo de Odoo (ej: 17.0): " TARGET_VERSION
TARGET_VERSION=$(clean_input "$TARGET_VERSION")

# Paso 4: Verificar si la versión objetivo está instalada
TARGET_VERSION_SHORT=$(echo "$TARGET_VERSION" | cut -d. -f1)
INSTALL_REQUIRED=1

if is_version_installed "$TARGET_VERSION_SHORT"; then
    echo "✅ Odoo ${TARGET_VERSION_SHORT} ya está instalado."
    INSTALL_REQUIRED=0
    
    # Obtener información de la instalación existente
    INSTALL_INFO=$(get_installation_info "$TARGET_VERSION_SHORT")
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    IFS=',' read -r TARGET_DB_USER TARGET_DB_PASSWORD TARGET_PORT TARGET_ADDONS_PATH <<< "$INSTALL_INFO"
else
    echo "ℹ️ Odoo ${TARGET_VERSION_SHORT} no está instalado. Se procederá a instalarlo."
fi

# Paso 5: Crear respaldo de la base de datos
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

# Paso 6: Ejecutar herramienta de actualización de Odoo como postgres
echo "🔄 Ejecutando herramienta de actualización de Odoo..."

# Primero verificar si la base de datos está registrada
REGISTRATION_CHECK=$(sudo -u postgres psql -d "$DB_NAME" -t -c "SELECT value FROM ir_config_parameter WHERE key = 'database.enterprise_code';" | tr -d ' ')

if [ -z "$REGISTRATION_CHECK" ]; then
    echo "⚠️ La base de datos no está registrada. Necesita un código de suscripción."
    read -p "🔹 Ingrese el código de contrato (subscription code) o deje vacío para omitir: " CONTRACT_CODE
    CONTRACT_CODE=$(clean_input "$CONTRACT_CODE")
    
    if [ -z "$CONTRACT_CODE" ]; then
        echo "❌ No se puede continuar sin código de suscripción."
        echo "   Visite https://www.odoo.com/documentation/user/administration/maintain/on_premise.html para más información."
        exit 1
    fi
    
    UPGRADE_CMD="python3 <(curl -s https://upgrade.odoo.com/upgrade) test -d $DB_NAME -t $TARGET_VERSION --contract $CONTRACT_CODE"
else
    UPGRADE_CMD="python3 <(curl -s https://upgrade.odoo.com/upgrade) test -d $DB_NAME -t $TARGET_VERSION"
fi

# Crear un script temporal para ejecutar como postgres
TEMP_SCRIPT=$(mktemp)
echo "#!/bin/bash" > "$TEMP_SCRIPT"
echo "cd ~" >> "$TEMP_SCRIPT"
echo "$UPGRADE_CMD" >> "$TEMP_SCRIPT"
chmod +x "$TEMP_SCRIPT"

# Ejecutar como postgres
UPGRADE_OUTPUT=$(sudo -u postgres bash "$TEMP_SCRIPT")
rm "$TEMP_SCRIPT"

if [[ "$UPGRADE_OUTPUT" != *"Your database is now ready"* ]]; then
    echo "❌ Error durante la actualización:"
    echo "$UPGRADE_OUTPUT"
    exit 1
fi

echo "✅ Actualización completada con éxito."

# Resto del script permanece igual...
[El resto del script permanece igual desde el Paso 7 en adelante]