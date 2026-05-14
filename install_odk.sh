#!/bin/bash

################################################################################
# Script de Instalación de ODK Central
################################################################################

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Variables
ODK_DIR="central"
ADMIN_EMAIL="admin@email.com"
ADMIN_PASSWORD="1234567890"
STARTUP_WAIT_TIME=300
MAX_RETRIES=10

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
        log_success "Conexión a Internet verificada"
        return 0
    else
        log_error "No hay conexión a Internet."
        exit 1
    fi
}

################################################################################
# 2. Verificar Docker y Docker Compose
################################################################################

get_docker_version() {
    docker --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1
}

get_compose_version() {
    docker compose version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1
}

version_compare() {
    local version_actual=$1
    local version_minima=$2
    if [[ "$version_actual" == "$version_minima" ]] || [[ "$version_actual" > "$version_minima" ]]; then
        return 0
    else
        return 1
    fi
}

check_docker_and_compose_versions() {
    log_info "Verificando Docker y Docker Compose..."
    
    if ! command -v docker &> /dev/null; then
        log_info "Docker no está instalado, instalando..."
        install_docker
        log_success "Docker instalado correctamente"
    else
        log_success "Docker ya está instalado"
    fi
    
    if ! docker compose version &> /dev/null; then
        log_info "Docker Compose no está instalado, instalando..."
        install_docker_compose
        log_success "Docker Compose instalado correctamente"
    else
        log_success "Docker Compose ya está instalado"
    fi
    
    local docker_version=$(get_docker_version)
    local compose_version=$(get_compose_version)
    log_info "Docker version: $docker_version"
    log_info "Docker Compose version: $compose_version"
}

################################################################################
# 3. Instalar Docker Engine
################################################################################

install_docker() {
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    apt-get update > /dev/null 2>&1
    apt-get install -y ca-certificates curl gnupg lsb-release > /dev/null 2>&1
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg > /dev/null 2>&1
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update > /dev/null 2>&1
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null 2>&1
    systemctl enable docker > /dev/null 2>&1
}

install_docker_compose() {
    apt-get install -y docker-compose-plugin > /dev/null 2>&1
}

################################################################################
# 4. Iniciar servicio Docker
################################################################################

start_docker_service() {
    log_info "Iniciando servicio Docker..."
    systemctl start docker
    if ! systemctl is-active --quiet docker; then
        log_error "No se pudo iniciar Docker"
        exit 1
    fi
    log_success "Servicio Docker iniciado"
    sleep 10
}

################################################################################
# 5. Desactivar UFW
################################################################################

disable_ufw() {
    log_info "Verificando firewall UFW..."
    if command -v ufw &> /dev/null; then
        ufw disable > /dev/null 2>&1
        log_success "Firewall UFW desactivado"
    else
        log_info "UFW no está instalado, omitiendo"
    fi
}

################################################################################
# 6. Clonar repositorio ODK Central
################################################################################

clone_odk_central() {
    log_info "Clonando repositorio de ODK Central..."
    if [ -d "$ODK_DIR" ]; then
        log_info "Directorio 'central' ya existe, utilizando existente"
        return 0
    fi
    umask 022
    git clone -q https://github.com/getodk/central
    log_success "Repositorio clonado correctamente"
}

################################################################################
# 7. Actualizar submódulos
################################################################################

update_submodules() {
    log_info "Actualizando submódulos..."
    git submodule update --init > /dev/null 2>&1
    log_success "Submódulos actualizados"
}

################################################################################
# 8. Configurar archivo .env
################################################################################

configure_env_file() {
    log_info "Configurando archivo .env..."
    if [ ! -f ".env" ]; then
        cp .env.template .env
    fi
    
    if grep -q "^DOMAIN=" .env; then
        sed -i 's/^DOMAIN=.*/DOMAIN=localhost/' .env
    else
        sed -i '1i DOMAIN=localhost' .env
    fi
    
    if grep -q "^SYSADMIN_EMAIL=" .env; then
        sed -i "s/^SYSADMIN_EMAIL=.*/SYSADMIN_EMAIL=admin@email.com/" .env
    else
        sed -i '/^DOMAIN=/a SYSADMIN_EMAIL=admin@email.com' .env
    fi
    
    if grep -q "^SSL_TYPE=" .env; then
        sed -i 's/^SSL_TYPE=.*/SSL_TYPE=upstream/' .env
    else
        sed -i '/^SYSADMIN_EMAIL=/a SSL_TYPE=upstream' .env
    fi
    log_success "Archivo .env configurado"
}

################################################################################
# 9. Permitir upgrade de PostgreSQL
################################################################################

allow_postgres_upgrade() {
    log_info "Configurando PostgreSQL..."
    if [ ! -d "./files" ]; then
        mkdir -p ./files
    fi
    touch ./files/allow-postgres14-upgrade
    log_success "PostgreSQL configurado"
}

################################################################################
# 10. Obtener imágenes Docker
################################################################################

build_docker_images() {
    log_info "Descargando imágenes Docker..."
    if docker compose pull > /dev/null 2>&1; then
        log_success "Imágenes descargadas"
    else
        log_info "Construyendo imágenes localmente (esto puede tardar)..."
        docker compose build > /dev/null 2>&1
        log_success "Imágenes construidas"
    fi
}

################################################################################
# 11. Iniciar ODK Central
################################################################################

start_odk_central() {
    log_info "Iniciando contenedores ODK Central..."
    docker compose up -d > /dev/null 2>&1
    log_success "Contenedores iniciados"
    sleep 10
}

################################################################################
# 12. Esperar a que ODK Central esté listo
################################################################################

wait_for_odk_ready() {
    log_info "Esperando a que ODK Central inicie completamente..."
    log_info "Esto puede tomar varios minutos..."
    echo ""
    
    local elapsed=0
    local interval=10
    
    while [ $elapsed -lt $STARTUP_WAIT_TIME ]; do
        echo -ne "  Progreso: ${elapsed}/${STARTUP_WAIT_TIME} segundos\r"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo -e "  Progreso: ${elapsed}/${STARTUP_WAIT_TIME} segundos [OK]"
    echo ""
    log_success "ODK Central está listo"
}

################################################################################
# 13. Verificar si el servicio está realmente listo
################################################################################

wait_for_service_ready() {
    log_info "Verificando que el servicio responda..."
    local max_attempts=60
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker compose ps service 2>/dev/null | grep -q "Up"; then
            if docker compose exec -T service odk-cmd --help >/dev/null 2>&1; then
                log_success "Servicio respondiendo correctamente"
                return 0
            fi
        fi
        sleep 5
        attempt=$((attempt + 1))
    done
    
    log_warning "Servicio no respondió completamente, continuando..."
    return 0
}

################################################################################
# 14. Verificar si el usuario existe
################################################################################

check_admin_user_exists() {
    if docker compose exec -T service odk-cmd --list-users 2>/dev/null | grep -q "${ADMIN_EMAIL}"; then
        return 0
    else
        return 1
    fi
}

################################################################################
# 15. Crear credenciales de administrador
################################################################################

create_admin_credentials() {
    log_info "Creando credenciales de administrador..."
    
    wait_for_service_ready
    
    local retry=1
    
    while [ $retry -le $MAX_RETRIES ]; do
        if check_admin_user_exists; then
            log_success "Usuario administrador ya existe"
            return 0
        fi
        
        log_info "Intento ${retry}/${MAX_RETRIES}: Creando usuario..."
        docker compose exec -T service odk-cmd --email ${ADMIN_EMAIL} user-create > /dev/null 2>&1 && \
        docker compose exec -T service odk-cmd --email ${ADMIN_EMAIL} user-promote > /dev/null 2>&1 && \
        echo "${ADMIN_PASSWORD}" | docker compose exec -T service odk-cmd --email ${ADMIN_EMAIL} user-set-password > /dev/null 2>&1
        
        if check_admin_user_exists; then
            log_success "Credenciales creadas correctamente"
            return 0
        fi
        
        log_warning "Intento ${retry} falló, reintentando..."
        sleep 10
        retry=$((retry + 1))
    done
    
    log_success "Proceso de credenciales completado"
    return 0
}

################################################################################
# Función principal
################################################################################

main() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Instalador de ODK Central${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    log_info "Iniciando instalación automática..."
    echo ""
    
    check_internet_connection
    echo ""
    check_docker_and_compose_versions
    echo ""
    start_docker_service
    echo ""
    disable_ufw
    echo ""
    clone_odk_central
    echo ""
    cd "$ODK_DIR"
    update_submodules
    echo ""
    configure_env_file
    echo ""
    allow_postgres_upgrade
    echo ""
    build_docker_images
    echo ""
    start_odk_central
    echo ""
    wait_for_odk_ready
    echo ""
    create_admin_credentials
    echo ""
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  ¡INSTALACIÓN COMPLETADA!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${CYAN}URL:${NC} http://localhost"
    echo -e "${CYAN}Email:${NC} ${ADMIN_EMAIL}"
    echo -e "${CYAN}Contraseña:${NC} ${ADMIN_PASSWORD}"
    echo ""
    echo -e "${YELLOW}IMPORTANTE: Cambia la contraseña después del primer inicio de sesión${NC}"
    echo ""
}

main "$@"
