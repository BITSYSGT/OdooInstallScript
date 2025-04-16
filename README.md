# OdooInstallScript - Bit Systems, S.A.

## 🚀 Descripción

Este repositorio contiene un script de instalación automatizado para **Odoo** (versiones 15, 16, 17 y 18) en **Ubuntu**. El script incluye la instalación de Odoo, configuración de PostgreSQL, entorno Python, creación de un servicio **systemd**, y la configuración de **Nginx** con **Certbot** para habilitar HTTPS.

## 🔥 Características

- Instalación automatizada de Odoo 15, 16, 17 o 18.
- Verificación de compatibilidad con el sistema operativo (Ubuntu 24.04 LTS recomendado).
- Soporte para Community y Enterprise (requiere token de GitHub).
- Configuración de base de datos PostgreSQL.
- Creación de un servicio systemd para Odoo.
- Instalación de **Nginx** y **Certbot (Let’s Encrypt)** para asegurar tu instalación con HTTPS.
- Script de desinstalación incluido.

## 📅 Cómo descargar el repositorio

Puedes descargar este repositorio utilizando `wget` directamente desde tu servidor:

### ▶️ Instalación de Odoo
```bash
wget https://raw.githubusercontent.com/BITSYSGT/OdooInstallScript/all-in-one/odoo_installer.sh
sudo chmod +x odoo_installer.sh
sudo ./odoo_installer.sh
```

### ⏹️ Desinstalación de Odoo
```bash
wget https://raw.githubusercontent.com/BITSYSGT/OdooInstallScript/all-in-one/odoo_uninstall.sh
sudo chmod +x odoo_uninstall.sh
sudo ./odoo_uninstall.sh
```