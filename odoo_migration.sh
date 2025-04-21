#!/bin/bash

# ╭────────────────────────────────────────────────────────────╮
# │ ODOO MIGRATION TOOL                                        │
# │ Autor: Bit Systems, S.A.                                   │
# │ Soporte: https://bitsys.odoo.com                           │
# │ Compatible: Ubuntu 22.04+ / Odoo 15.0+                     │
# ╰────────────────────────────────────────────────────────────╯

clear

echo "╭────────────────────────────────────────────────────────────╮"
echo "│ ODOO MIGRATION TOOL                                        │"
echo "│ Autor: Bitsys | GT                                         │"
echo "│ Soporte: https://bitsys.odoo.com                           │"
echo "│ Compatible: Ubuntu 22.04+ / Odoo 15.0+                     │"
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

# Paso 6: Ejecutar herramienta de actualización de Odoo
echo "🔄 Ejecutando herramienta de actualización de Odoo..."
UPGRADE_OUTPUT=$(python3 <(curl -s https://upgrade.odoo.com/upgrade) test -d "$DB_NAME" -t "$TARGET_VERSION")

if [[ "$UPGRADE_OUTPUT" != *"Your database is now ready"* ]]; then
    echo "❌ Error durante la actualización:"
    echo "$UPGRADE_OUTPUT"
    exit 1
fi

echo "✅ Actualización completada con éxito."

# Paso 7: Instalar versión objetivo si es necesario
if [ $INSTALL_REQUIRED -eq 1 ]; then
    echo "🔧 Instalando Odoo ${TARGET_VERSION_SHORT}..."
    
    # Llamar al script de instalación original
    /bin/bash /ruta/al/script_de_instalacion_original.sh
    
    # Obtener información de la nueva instalación
    INSTALL_INFO=$(get_installation_info "$TARGET_VERSION_SHORT")
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    IFS=',' read -r TARGET_DB_USER TARGET_DB_PASSWORD TARGET_PORT TARGET_ADDONS_PATH <<< "$INSTALL_INFO"
fi

# Paso 8: Cambiar el propietario de la base de datos si es necesario
CURRENT_OWNER=$(sudo -u postgres psql -t -c "SELECT pg_catalog.pg_get_userbyid(d.datdba) FROM pg_catalog.pg_database d WHERE d.datname = '$DB_NAME';" | tr -d ' ')

if [ "$CURRENT_OWNER" != "$TARGET_DB_USER" ]; then
    echo "🔧 Cambiando propietario de la base de datos a ${TARGET_DB_USER}..."
    sudo -u postgres psql -c "ALTER DATABASE \"$DB_NAME\" OWNER TO \"$TARGET_DB_USER\";"
    
    # Cambiar propietario de todos los esquemas y tablas
    sudo -u postgres psql -d "$DB_NAME" -c "REASSIGN OWNED BY \"$CURRENT_OWNER\" TO \"$TARGET_DB_USER\";"
fi

# Paso 9: Configurar la instancia de Odoo para usar la base de datos migrada
echo "🔧 Configurando la instancia de Odoo ${TARGET_VERSION_SHORT}..."
TARGET_CONFIG_FILE="/etc/odoo${TARGET_VERSION_SHORT}.conf"

# Actualizar el archivo de configuración
sudo sed -i "s/^db_name = .*/db_name = $DB_NAME/" "$TARGET_CONFIG_FILE"

# Reiniciar el servicio
echo "🔄 Reiniciando servicio Odoo ${TARGET_VERSION_SHORT}..."
sudo systemctl restart "odoo${TARGET_VERSION_SHORT}.service"

# Paso 10: Mostrar resumen de la migración
echo ""
echo "╭───────────────────────────────────────────────────────────────────────────────╮"
echo "│ 🎉 MIGRACIÓN COMPLETA DE ODOO $CURRENT_VERSION a $TARGET_VERSION"
echo "├───────────────────────────────────────────────────────────────────────────────┤"
echo "│ 🔹 Base de datos original:  $DB_NAME"
echo "│ 🔹 Versión origen:         $CURRENT_VERSION"
echo "│ 🔹 Versión destino:        $TARGET_VERSION"
echo "│ 🔹 Respaldo creado:        $BACKUP_FILE"
echo "│ 🔹 Nuevo propietario DB:   $TARGET_DB_USER"
echo "│ 🔹 Puerto de acceso:       $TARGET_PORT"
echo "├───────────────────────────────────────────────────────────────────────────────┤"
echo "│ 🔗 Accesos:"
echo "│    - Directo:             http://$(hostname -I | awk '{print $1}'):$TARGET_PORT"
echo "│    - Web:                 https://$(grep 'server_name' /etc/nginx/sites-available/odoo${TARGET_VERSION_SHORT} | awk '{print $2}' | head -1)"
echo "├───────────────────────────────────────────────────────────────────────────────┤"
echo "│ ⚙️  Comandos útiles:"
echo "│    - Ver logs:            journalctl -u odoo${TARGET_VERSION_SHORT} -f"
echo "│    - Reiniciar servicio:  sudo systemctl restart odoo${TARGET_VERSION_SHORT}"
echo "╰───────────────────────────────────────────────────────────────────────────────╯"
echo ""
echo "⚠️ IMPORTANTE: Verifique que todos los módulos estén correctamente actualizados ⚠️"