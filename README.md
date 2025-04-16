# OdooInstallScript - Bit Systems, S.A.

## 🚀 Descripción

Este repositorio contiene un script de instalación automatizado para **Odoo 18** en **Ubuntu 24.04 LTS**. El script incluye la instalación de Odoo, configuración de PostgreSQL, entorno Python, creación de un servicio **systemd**, y la configuración de **Nginx** con **Certbot** para habilitar HTTPS.

## 🔥 Características

- Instalación automatizada de Odoo 18.
- Configuración de base de datos PostgreSQL.
- Creación de un servicio systemd para Odoo.
- Instalación de **Nginx** y **Certbot (Let’s Encrypt)** para asegurar tu instalación con HTTPS.

## 📥 Cómo descargar el repositorio

Puedes descargar este repositorio utilizando `wget` directamente desde tu servidor:


```bash
# Este script instala Odoo 18 y lo configura en tu servidor.
wget https://raw.githubusercontent.com/BITSYSGT/OdooInstallScript/18.0/odoo_installer.sh
sudo chmod +x odoo_installer.sh
sudo ./odoo_installer.sh
```
```bash
# Este script desinstala Odoo 18 y elimina los componentes relacionados.
wget wget https://raw.githubusercontent.com/BITSYSGT/OdooInstallScript/18.0/odoo_uninstall.sh
sudo chmod +x odoo_uninstall.sh
sudo ./odoo_uninstall.sh
```



