#!/bin/bash

################################################################################
# Script de Instalación de ODK Central
################################################################################

set -e  # Detener el script si algún comando falla

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables de configuración
ODK_DIR="/opt/odk-central"
ENV_FILE="${ODK_DIR}/.env"
MIN_DOCKER_VERSION="23.0.0"
MIN_COMPOSE_VERSION="2.16.0"
ADMIN_EMAIL="admin@email.com"

################################################################################
# Funciones de utilidad
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

################################################################################
# 1. Verificar conexión a Internet
################################################################################

check_internet_connection() {
    log_info "Verificando conexión a Internet..."
    
    if ping -c 3 -W 5 www.unilibre.edu.co > /dev/null 2>&1; then
        log_success "Conexión a Internet verificada"
        return 0
    elif ping -c 3 -W 5 8.8.8.8 > /dev/null 2>&1; then
        log_success "Conexión a Internet verificada (vía DNS alternativo)"
        return 0
    else
        log_error "No hay conexión a Internet. El script no puede continuar."
        exit 1
    fi
}

################################################################################
# 2. Verificar e instalar Docker Engine
################################################################################

check_docker_installed() {
    if command -v docker &> /dev/null; then
        return 0
    else
        return 1
    fi
}

get_docker_version() {
    docker --version | grep -oP '\d+\.\d+\.\d+' | head -1
}

get_compose_version() {
    docker compose version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || \
    docker-compose --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1
}

version_compare() {
    local version_actual=$1
    local version_minima=$2
    
    if [[ "$version_actual" == "$version_minima" ]]; then
        return 0
    elif [[ "$version_actual" > "$version_minima" ]]; then
        return 0
    else
        return 1
    fi
}

install_docker() {
    log_info "Instalando Docker Engine desde el repositorio oficial..."
    
    log_info "Eliminando versiones conflictivas de Docker..."
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    log_info "Actualizando lista de paquetes..."
    sudo apt-get update
    
    log_info "Instalando dependencias..."
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    
    log_info "Agregando clave GPG de Docker..."
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    log_info "Configurando repositorio de Docker..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    log_info "Instalando Docker Engine..."
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    log_info "Iniciando servicio Docker..."
    sudo systemctl start docker
    sudo systemctl enable docker
    
    if ! groups $USER | grep -q docker; then
        log_info "Agregando usuario al grupo docker..."
        sudo usermod -aG docker $USER
        log_warning "Debes cerrar sesión y volver a entrar para que los cambios de grupo surtan efecto"
    fi
    
    log_success "Docker Engine instalado correctamente"
}

verify_docker_installation() {
    log_info "Verificando instalación de Docker..."
    
    if ! check_docker_installed; then
        log_error "Docker no está instalado"
        return 1
    fi
    
    local docker_version=$(get_docker_version)
    log_info "Versión de Docker: $docker_version"
    
    if version_compare "$docker_version" "$MIN_DOCKER_VERSION"; then
        log_success "Versión de Docker es adecuada (>= $MIN_DOCKER_VERSION)"
    else
        log_warning "Versión de Docker ($docker_version) es menor que la mínima requerida ($MIN_DOCKER_VERSION)"
        log_info "Considera actualizar Docker para mejor compatibilidad"
    fi
    
    return 0
}

################################################################################
# 3. Verificar Docker Compose
################################################################################

check_docker_compose() {
    log_info "Verificando Docker Compose..."
    
    if docker compose version &> /dev/null; then
        local compose_version=$(get_compose_version)
        log_info "Versión de Docker Compose: $compose_version"
        
        if version_compare "$compose_version" "$MIN_COMPOSE_VERSION"; then
            log_success "Docker Compose versión adecuada (>= $MIN_COMPOSE_VERSION)"
            return 0
        else
            log_warning "Docker Compose ($compose_version) es menor que la mínima requerida ($MIN_COMPOSE_VERSION)"
            return 1
        fi
    elif docker-compose --version &> /dev/null; then
        log_warning "Usando docker-compose standalone (versión antigua)"
        return 0
    else
        log_error "Docker Compose no está instalado"
        return 1
    fi
}

################################################################################
# 4. Configurar archivo .env para ODK Central
################################################################################

setup_odk_directory() {
    log_info "Configurando directorio de ODK Central..."
    
    if [ ! -d "$ODK_DIR" ]; then
        log_info "Clonando repositorio de ODK Central..."
        sudo mkdir -p "$ODK_DIR"
        sudo chown $USER:$USER "$ODK_DIR"
        cd "$ODK_DIR"
        
        git clone https://github.com/getodk/central.git . 2>/dev/null || {
            log_error "No se pudo clonar el repositorio de ODK Central"
            exit 1
        }
        
        log_info "Inicializando submódulos..."
        git submodule update --init --recursive
    else
        log_info "Directorio de ODK Central ya existe"
        cd "$ODK_DIR"
    fi
    
    # GUARDAR la ruta actual para usarla después
    export ODK_CURRENT_DIR="$(pwd)"
    log_info "Directorio actual: $ODK_CURRENT_DIR"
}

configure_env_file() {
    log_info "Configurando archivo .env..."
    
    if [ ! -f "$ENV_FILE" ]; then
        if [ -f "${ODK_DIR}/.env.template" ]; then
            cp "${ODK_DIR}/.env.template" "$ENV_FILE"
            log_success "Archivo .env creado desde plantilla"
        else
            log_error "No se encontró .env.template"
            exit 1
        fi
    fi
    
    log_info "Cambiando DOMAIN a localhost..."
    if grep -q "^DOMAIN=" "$ENV_FILE"; then
        sed -i 's/^DOMAIN=.*/DOMAIN=localhost/' "$ENV_FILE"
    else
        echo "DOMAIN=localhost" >> "$ENV_FILE"
    fi
    log_success "DOMAIN configurado como localhost"
    
    log_info "Configurando SYSADMIN_EMAIL..."
    if grep -q "^SYSADMIN_EMAIL=" "$ENV_FILE"; then
        sed -i 's/^SYSADMIN_EMAIL=.*/SYSADMIN_EMAIL=administrator@email.com/' "$ENV_FILE"
    else
        sed -i '/^DOMAIN=/a SYSADMIN_EMAIL=administrator@email.com' "$ENV_FILE"
    fi
    log_success "SYSADMIN_EMAIL configurado como administrator@email.com"
    
    log_info "Configurando SSL_TYPE..."
    if grep -q "^SSL_TYPE=" "$ENV_FILE"; then
        sed -i 's/^SSL_TYPE=.*/SSL_TYPE=upstream/' "$ENV_FILE"
    else
        sed -i '/^SYSADMIN_EMAIL=/a SSL_TYPE=upstream' "$ENV_FILE"
    fi
    log_success "SSL_TYPE configurado como upstream"
    
    log_info "Configurando puertos..."
    if ! grep -q "^HTTP_PORT=" "$ENV_FILE"; then
        echo "HTTP_PORT=80" >> "$ENV_FILE"
    fi
    if ! grep -q "^HTTPS_PORT=" "$ENV_FILE"; then
        echo "HTTPS_PORT=443" >> "$ENV_FILE"
    fi
    
    log_success "Archivo .env configurado correctamente"
    
    log_info "Configuración actual del .env:"
    grep -E "^(DOMAIN|SYSADMIN_EMAIL|SSL_TYPE|HTTP_PORT|HTTPS_PORT)=" "$ENV_FILE" | while read line; do
        echo "  $line"
    done
}

################################################################################
# 5. Arreglo del postgres
################################################################################

allow_postgres_upgrade() {
    log_info "Creando archivo allow-postgres14-upgrade..."
    
    # Usar la ruta guardada explícitamente
    cd "$ODK_CURRENT_DIR"
    
    # Crear directorio files si no existe
    if [ ! -d "${ODK_CURRENT_DIR}/files" ]; then
        mkdir -p "${ODK_CURRENT_DIR}/files"
    fi
    
    # Crear el archivo con ruta absoluta
    touch "${ODK_CURRENT_DIR}/files/allow-postgres14-upgrade"
    
    # Verificar que se creó correctamente
    if [ -f "${ODK_CURRENT_DIR}/files/allow-postgres14-upgrade" ]; then
        log_success "Archivo allow-postgres14-upgrade creado en: ${ODK_CURRENT_DIR}/files/"
        ls -la "${ODK_CURRENT_DIR}/files/"
    else
        log_error "No se pudo crear el archivo allow-postgres14-upgrade"
        exit 1
    fi
}

################################################################################
# 6. Iniciar Docker y ODK Central
################################################################################

start_docker_service() {
    log_info "Verificando servicio Docker..."
    
    if ! sudo systemctl is-active --quiet docker; then
        log_info "Iniciando servicio Docker..."
        sudo systemctl start docker
        sudo systemctl enable docker
        log_success "Servicio Docker iniciado"
    else
        log_success "Servicio Docker ya está activo"
    fi
}

start_odk_central() {
    log_info "Iniciando ODK Central..."
    
    # Asegurar que estamos en el directorio correcto
    cd "$ODK_CURRENT_DIR"
    log_info "Directorio actual: $(pwd)"
    
    # Verificar que el archivo existe antes de continuar
    if [ ! -f "${ODK_CURRENT_DIR}/files/allow-postgres14-upgrade" ]; then
        log_error "El archivo allow-postgres14-upgrade no existe. No se puede continuar."
        exit 1
    fi
    
    if ! docker compose version &> /dev/null; then
        log_error "docker compose no está disponible"
        exit 1
    fi
    
    log_info "Ejecutando docker compose up -d..."
    sudo docker compose up -d
    
    log_info "Esperando 180 segundos para que los servicios de ODK Central inicien completamente..."
    log_info "Esto incluye: PostgreSQL, migraciones, nginx, service, etc."
    echo ""
    
    local elapsed=0
    local interval=10
    
    while [ $elapsed -lt 180 ]; do
        echo -ne "  Tiempo transcurrido: ${elapsed}/180 segundos\r"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo -e "  Tiempo transcurrido: ${elapsed}/180 segundos [OK]"
    echo ""
    
    log_success "ODK Central iniciado correctamente"
}

################################################################################
# 7. Crear usuario administrador
################################################################################

create_admin_user() {
    log_info "Creando usuario administrador..."
    
    cd "$ODK_CURRENT_DIR"
    
    log_info "Ejecutando comando para crear usuario..."
    sudo docker compose exec service odk-cmd --email ${ADMIN_EMAIL} user-create
    
    log_success "Usuario creado correctamente"
}

################################################################################
# 8. Verificar estado de la instalación
################################################################################

verify_installation() {
    log_info "Verificando estado de los contenedores..."
    
    sudo docker compose ps
    
    log_info "Para verificar el estado completo, ejecuta:"
    echo "  cd $ODK_DIR && sudo docker compose ps"
    echo ""
    log_info "Para ver los logs:"
    echo "  cd $ODK_DIR && sudo docker compose logs -f"
}

################################################################################
# Función principal
################################################################################

main() {
    echo ""
    echo "========================================"
    echo "  Instalador de ODK Central para RPi"
    echo "========================================"
    echo ""
    
    check_internet_connection
    
    if check_docker_installed; then
        log_success "Docker ya está instalado"
        verify_docker_installation
    else
        log_warning "Docker no está instalado, procediendo con la instalación..."
        install_docker
        verify_docker_installation
    fi
    
    check_docker_compose
    
    setup_odk_directory
    configure_env_file
    
    # Crear archivo allow-postgres14-upgrade
    allow_postgres_upgrade
    
    start_docker_service
    start_odk_central
    
    create_admin_user
    
    verify_installation
    
    echo ""
    echo "========================================"
    log_success "¡Instalación completada!"
    echo "========================================"
    echo ""
    echo "Accede a ODK Central en: http://localhost"
    echo "Directorio de instalación: $ODK_DIR"
    echo ""
    echo "========================================"
    echo "  PROMOVER USUARIO A ADMINISTRADOR"
    echo "========================================"
    echo ""
    echo "Para completar la configuración, debes promover el usuario a administrador:"
    echo ""
    echo "1. Ejecuta el siguiente comando:"
    echo ""
    echo "   docker compose exec service odk-cmd --email admin@email.com user-promote"
    echo ""
    echo "2. Selecciona el comando de la línea anterior con Ctrl + Shift + C"
    echo ""
    echo "3. Ahora ejecuta:"
    echo "   cd central"
    echo ""
    echo "4. Presiona Ctrl + Shift + V y dale Enter"
    echo ""
    echo "========================================"
    echo ""
    echo "Comandos útiles:"
    echo "  cd $ODK_DIR && sudo docker compose ps      # Ver estado"
    echo "  cd $ODK_DIR && sudo docker compose logs -f # Ver logs"
    echo "  cd $ODK_DIR && sudo docker compose down    # Detener"
    echo "  cd $ODK_DIR && sudo docker compose up -d   # Iniciar"
    echo ""
}

main "$@"
