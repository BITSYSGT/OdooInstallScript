
# OdooInstallScript - Bit Systems, S.A.

## 🚀 Descripción
Este repositorio contiene un script de instalación automatizado para **Odoo** (versiones 15, 16, 17 y 18) en **Ubuntu**. El script gestiona la instalación completa de Odoo, configuraciones de PostgreSQL, entorno Python, creación de un servicio systemd y la configuración de **Nginx** con **Certbot** para habilitar HTTPS.

Este script soporta **instalaciones multiinstancia**, lo que significa que puedes tener varias versiones de Odoo instaladas simultáneamente sin conflictos.

## 🧩 Características

- Instalación automatizada de Odoo 15, 16, 17 o 18.
- **Instalaciones multiinstancia** (cada versión de Odoo se instala de manera independiente).
- Verificación del sistema operativo (**Ubuntu 22.04 LTS** y **24.04 LTS** son compatibles).
- Soporte para **Community y Enterprise** (requiere token de GitHub para instalar la versión Enterprise).
- Creación de un **servicio systemd** independiente para cada versión.
- Configuración de **PostgreSQL** por versión.
- Configuración opcional de **Nginx** y **Certbot** para habilitar HTTPS.
- **Desinstalación completa** de una instancia de Odoo sin afectar otras.
- Instalación de dependencias necesarias como python3-dev, build-essential, nginx, y más.

## ⚙️ Requisitos

- **Ubuntu 22.04 LTS** o **24.04 LTS**.
- Acceso a **sudo** o usuario root para realizar instalaciones.
- Para la instalación de **Odoo Enterprise**, necesitarás un token de GitHub autorizado por Odoo.

---

## 📂 Instalación

### 1. Descargar y ejecutar el script de instalación
Durante la ejecución, se te pedirá que selecciones la versión de Odoo (15, 16, 17, 18). Además, podrás optar por instalar la versión **Enterprise** (requiere tu token de GitHub).

El script también sugerirá un puerto por defecto basado en la versión de Odoo (por ejemplo, 8071 para Odoo 18). Puedes elegir otro puerto si lo deseas.

```bash
wget https://raw.githubusercontent.com/BITSYSGT/OdooInstallScript/allinone-multitenant-nginx/odoo_installer.sh
chmod +x odoo_installer.sh
sudo ./odoo_installer.sh
```

### 2. Ingresar el dominio para Nginx y Certbot
Durante la instalación, se te pedirá ingresar el dominio para configurar el servidor web Nginx y habilitar HTTPS mediante Certbot. El script intentará configurar Let's Encrypt si el dominio es válido.

### 3. Completado
Una vez que el script termine, se mostrará un resumen con la URL de acceso a Odoo, la configuración de PostgreSQL, el estado de la instalación de la versión Enterprise (si se instaló) y otros detalles útiles.

---

## 🔄 Comandos para gestionar Odoo

- **Iniciar Odoo**:  
  `sudo systemctl start odoo<versión>`

- **Detener Odoo**:  
  `sudo systemctl stop odoo<versión>`

- **Reiniciar Odoo**:  
  `sudo systemctl restart odoo<versión>`

- **Ver el estado de Odoo**:  
  `sudo systemctl status odoo<versión>`

- **Ver logs**:  
  `tail -f /var/log/odoo<versión>/odoo.log`

---

## ⏹️ Desinstalación de una instancia de Odoo

Si necesitas desinstalar una instancia de Odoo, el script te permitirá elegir qué versión eliminar. También puedes eliminar PostgreSQL, Nginx y Certbot si lo deseas. Esto no afectará a las otras instancias de Odoo instaladas en tu sistema.

```bash
wget https://raw.githubusercontent.com/BITSYSGT/OdooInstallScript/allinone-multitenant-nginx/odoo_uninstall.sh
chmod +x odoo_uninstall.sh
sudo ./odoo_uninstall.sh
```

---

## 🌐 URL de acceso

Una vez completada la instalación, podrás acceder a Odoo desde la siguiente URL:

```text
http://<IP_del_servidor>:<PUERTO>
```

Si configuraste **Nginx** y **Certbot**, podrás acceder con **HTTPS** en la siguiente URL:

```text
https://<DOMINIO>
```

---

## 🛠️ Notas adicionales

- **Nginx y Certbot**: Si el dominio proporcionado es válido, el script configurará automáticamente un servidor web Nginx y generará un certificado SSL utilizando Certbot. Si el dominio no es válido, el script solo configurará Nginx y dejará la validación de Certbot para después.

- **Multiinstancia**: Cada versión de Odoo se instala independientemente, por lo que puedes tener varias versiones de Odoo funcionando en el mismo servidor sin interferencias.

---

## 🏢 Desarrollado por Bit Systems, S.A.
[https://bitsys.odoo.com](https://bitsys.odoo.com) | Guatemala 🇬🇹
