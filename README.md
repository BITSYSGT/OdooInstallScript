# OdooInstallScript - Bit Systems, S.A.

## 🚀 Descripción

Este repositorio contiene un script de instalación automatizado para **Odoo** (versiones 15, 16, 17 y 18) en **Ubuntu**. El script incluye la instalación de Odoo, configuración de PostgreSQL, entorno Python, creación de un servicio **systemd**, y la configuración de **Nginx** con **Certbot** para habilitar HTTPS.

## 🧩 Características

- Instalación automatizada de Odoo 15, 16, 17 o 18.
- Instalaciones multiinstancia basadas en la versión (no interfiere con otras versiones instaladas).
- Verificación del sistema operativo (Ubuntu 22.04 y 24.04 compatibles).
- Soporte para Community y Enterprise (requiere token de GitHub para Enterprise).
- Creación de un servicio independiente por versión.
- Configuración de PostgreSQL por versión.
- Configuración opcional de Nginx y Certbot (HTTPS).
- Script de desinstalación incluido para remover una instancia específica sin afectar otras.

## ⚙️ Requisitos

- Ubuntu 22.04 LTS o 24.04 LTS
- Acceso como `sudo` o usuario root
- Para Enterprise, acceso a tu cuenta de GitHub autorizada por Odoo

---

## ▶️ Instalación de Odoo
Durante la instalación:
Se te pedirá elegir la versión de Odoo (15, 16, 17, 18).
Puedes optar por instalar la versión Enterprise (requiere token).
El script sugiere un puerto basado en la versión (por ejemplo, 8015 para Odoo 15).

```bash
wget https://raw.githubusercontent.com/BITSYSGT/OdooInstallScript/allinone-multitenant/odoo_installer.sh
chmod +x odoo_installer.sh
sudo ./odoo_installer.sh

```




### ⏹️ Desinstalación de una instancia de Odoo
El script te preguntará qué versión de Odoo deseas eliminar (ej. 18) y luego te permitirá eliminar también PostgreSQL, Nginx y Certbot si lo deseas.
```bash
wget https://raw.githubusercontent.com/BITSYSGT/OdooInstallScript/allinone-multitenant/odoo_uninstall.sh
chmod +x odoo_uninstall.sh
sudo ./odoo_uninstall.sh
```
🏢 Desarrollado por
Bit Systems, S.A.
https://bitsys.odoo.com | Guatemala 🇬🇹