# Instalador Servidor ODK

![Tipo](https://img.shields.io/badge/Tipo-Proyecto%20Educativo-blue)
![Estado](https://img.shields.io/badge/Estado-Estable-green)
![Licencia](https://img.shields.io/badge/Licencia-GPL--3.0-orange)

Script de instalación automatizada de ODK Central diseñado para entornos Raspberry Pi y distribuciones Debian.

## ¿Qué hace?

Este script despliega una instancia de ODK Central completamente configurada, incluyendo:

- **Docker Engine y Docker Compose:** Instalación y configuración automática de los contenedores necesarios.
- **Archivo .env preconfigurado:** Ajustes predeterminados para localhost y gestión de certificados SSL upstream.
- **Usuario administrador:** Creación automática de la cuenta de administrador inicial para acceso inmediato.

## Requisitos

Antes de ejecutar la instalación, asegúrese de cumplir con las siguientes especificaciones:

- **Memoria RAM:** 2 GB mínimo (4 GB recomendados para un rendimiento óptimo).
- **Almacenamiento:** 10 GB de espacio disponible en disco.
- **Conectividad:** Conexión a Internet activa para la descarga de imágenes y dependencias.
- **Sistema Operativo:** Compatible con Debian, Ubuntu, Mint y distribuciones derivadas de Debian.

## Instalación

Siga los siguientes pasos para clonar el repositorio y ejecutar el script de instalación:

```bash
# Clonar repositorio
git clone https://github.com/TU_USUARIO/Instalador-Servidor-ODK.git
cd Instalador-Servidor-ODK

# Dar permisos de ejecución al script
chmod +x install_odk.sh

# Ejecutar instalador como superusuario
sudo ./install_odk.sh
