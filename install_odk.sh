#!/bin/bash

################################################################################
# Script de Instalación de ODK Central para Raspberry Pi con Debian
################################################################################

set -e  # Se detiene el script si algún comando falla

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Variables de configuración
ODK_DIR="central"
ENV_FILE="./.env"
MIN_DOCKER_VERSION="23.0.0"
MIN_COMPOSE_VERSION="2.16.0"
ADMIN_EMAIL="admin@email.com"
ADMIN_PASSWORD="1234567890"
STARTUP_WAIT_TIME=240
MAX_RETRIES=5

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

log_step() {
    echo -e "${PURPLE}================================================================${NC}"
    echo -e "${PURPLE}  $1${NC}"
    echo -e "${PURPLE}================================================================${NC}"
}

################################################################################
# 1. Verificar conexión a Internet
################################################################################

check_internet_connection() {
    log_step "Paso 1: Se verifica la conexión a Internet"
    log_info "Se realiza ping a https://www.unilibre.edu.co/..."
    
    if ping -c 3 -W 5 www.unilibre.edu.co > /dev/null 2>&1; then
        log_success "Conexión a Internet verificada correctamente"
        return 0
    elif ping -c 3 -W 5 8.8.8.8 > /dev/null 2>&1; then
        log_success "Conexión a Internet verificada (via DNS alternativo)"
        return 0
    else
        log_error "No hay conexión a Internet. El script no puede continuar."
        exit 1
    fi
}

################################################################################
# 2. Verificar versiones de Docker y Docker Compose
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
    
    if [[ "$version_actual" == "$version_minima" ]]; then
        return 0
    elif [[ "$version_actual" > "$version_minima" ]]; then
        return 0
    else
        return 1
    fi
}

check_docker_and_compose_versions() {
    log_step "Paso 2: Se verifican las versiones de Docker y Docker Compose"
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker no está instalado. Se procede a instalarlo..."
        install_docker
    fi
    
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose no está instalado. Se procede a instalarlo..."
        install_docker_compose
    fi
    
    log_info "Se ejecuta: docker --version && docker compose version"
    docker --version && docker compose version
    
    local docker_version=$(get_docker_version)
    local compose_version=$(get_compose_version)
    
    log_info "Version de Docker: $docker_version"
    log_info "Version de Docker Compose: $compose_version"
    
    if version_compare "$docker_version" "$MIN_DOCKER_VERSION"; then
        log_success "Version de Docker es adecuada (>= $MIN_DOCKER_VERSION)"
    else
        log_warning "Version de Docker ($docker_version) es menor que la mínima requerida ($MIN_DOCKER_VERSION)"
        log_info "Se recomienda actualizar Docker para mejor compatibilidad"
    fi
    
    if version_compare "$compose_version" "$MIN_COMPOSE_VERSION"; then
        log_success "Version de Docker Compose es adecuada (>= $MIN_COMPOSE_VERSION)"
    else
        log_warning "Version de Docker Compose ($compose_version) es menor que la mínima requerida ($MIN_COMPOSE_VERSION)"
        log_info "Se recomienda actualizar Docker Compose para mejor compatibilidad"
    fi
}

################################################################################
# 3. Instalar Docker Engine (si no existe)
################################################################################

install_docker() {
    log_info "Se instala Docker Engine desde el repositorio oficial..."
    
    log_info "Se eliminan versiones conflictivas de Docker..."
    apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    log_info "Se actualiza la lista de paquetes..."
    apt-get update
    
    log_info "Se instalan dependencias necesarias..."
    apt-get install -y ca-certificates curl gnupg lsb-release
    
    log_info "Se agrega la clave GPG de Docker..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    log_info "Se configura el repositorio de Docker..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    log_info "Se instala Docker Engine..."
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    log_info "Se habilita el servicio Docker para inicio automático..."
    systemctl enable docker
    
    log_success "Docker Engine se instaló correctamente"
}

install_docker_compose() {
    log_info "Se instala Docker Compose..."
    apt-get install -y docker-compose-plugin
    log_success "Docker Compose se instaló correctamente"
}

################################################################################
# 4. Iniciar servicio Docker
################################################################################

start_docker_service() {
    log_step "Paso 3: Se inicia el servicio Docker"
    log_info "Se ejecuta: systemctl start docker"
    systemctl start docker
    
    if systemctl is-active --quiet docker; then
        log_success "Servicio Docker se inició correctamente"
    else
        log_error "No se pudo iniciar el servicio Docker"
        exit 1
    fi
    
    echo ""
    log_info "Ahora mismo se están iniciando los servicios de Docker, por favor esperar unos segundos :-)"
    sleep 10
    log_success "Se completó la espera de Docker"
    echo ""
}

################################################################################
# 5. Desactivar UFW (firewall)
################################################################################

disable_ufw() {
    log_step "Paso 4: Se desactiva el firewall UFW"
    log_info "Se ejecuta: ufw disable"
    
    if command -v ufw &> /dev/null; then
        ufw disable
        log_success "Firewall UFW se desactivó correctamente"
    else
        log_info "UFW no está instalado, se omite este paso"
    fi
}

################################################################################
# 6. Clonar repositorio ODK Central
################################################################################

clone_odk_central() {
    log_step "Paso 5: Se clona el repositorio de ODK Central"
    log_info "Se ejecuta: umask 022; git clone https://github.com/getodk/central"
    
    if [ -d "$ODK_DIR" ]; then
        log_warning "El directorio 'central' ya existe"
        log_info "¿Deseas eliminarlo y clonar nuevamente? (s/n)"
        read -r response
        if [[ "$response" =~ ^[Ss]$ ]]; then
            rm -rf "$ODK_DIR"
            log_info "Se elimina el directorio existente..."
        else
            log_info "Se utiliza el directorio existente..."
            return 0
        fi
    fi
    
    umask 022
    git clone https://github.com/getodk/central
    log_success "Repositorio de ODK Central se clonó correctamente"
}

################################################################################
# 7. Actualizar submódulos
################################################################################

update_submodules() {
    log_step "Paso 6: Se actualizan los submódulos"
    log_info "Se ejecuta: git submodule update --init"
    
    git submodule update --init
    
    log_success "Submódulos se actualizaron correctamente"
}

################################################################################
# 8. Configurar archivo .env
################################################################################

configure_env_file() {
    log_step "Paso 7: Se configura el archivo .env"
    log_info "Se ejecuta: cp .env.template .env"
    
    if [ ! -f ".env" ]; then
        cp .env.template .env
        log_success "Archivo .env se creó desde la plantilla"
    else
        log_info "Archivo .env ya existe, se procede a modificar..."
    fi
    
    log_info "Se modifica DOMAIN a localhost..."
    if grep -q "^DOMAIN=" .env; then
        sed -i 's/^DOMAIN=.*/DOMAIN=localhost/' .env
    else
        sed -i '1i DOMAIN=localhost' .env
    fi
    log_success "DOMAIN se configuró como localhost"
    
    log_info "Se configura SYSADMIN_EMAIL..."
    if grep -q "^SYSADMIN_EMAIL=" .env; then
        sed -i "s/^SYSADMIN_EMAIL=.*/SYSADMIN_EMAIL=admin@email.com/" .env
    else
        sed -i '/^DOMAIN=/a SYSADMIN_EMAIL=admin@email.com' .env
    fi
    log_success "SYSADMIN_EMAIL se configuró como admin@email.com"
    
    log_info "Se modifica SSL_TYPE a upstream..."
    if grep -q "^SSL_TYPE=" .env; then
        sed -i 's/^SSL_TYPE=.*/SSL_TYPE=upstream/' .env
    else
        sed -i '/^SYSADMIN_EMAIL=/a SSL_TYPE=upstream' .env
    fi
    log_success "SSL_TYPE se configuró como upstream"
    
    echo ""
    log_info "Configuración actual del .env (primeras líneas):"
    echo -e "${CYAN}"
    head -n 10 .env | grep -E "^(DOMAIN|SYSADMIN_EMAIL|SSL_TYPE|#)" || head -n 10 .env
    echo -e "${NC}"
    echo ""
    
    log_success "Archivo .env se configuró correctamente"
}

################################################################################
# 9. Permitir upgrade de PostgreSQL
################################################################################

allow_postgres_upgrade() {
    log_step "Paso 8: Se permite el upgrade de PostgreSQL 14"
    log_info "Se ejecuta: touch ./files/allow-postgres14-upgrade"
    
    if [ ! -d "./files" ]; then
        mkdir -p ./files
    fi
    
    touch ./files/allow-postgres14-upgrade
    log_success "Archivo allow-postgres14-upgrade se creó correctamente"
}

################################################################################
# 10. Obtener imágenes Docker (pull en lugar de build)
################################################################################

build_docker_images() {
    log_step "Paso 9: Se obtienen las imágenes Docker"
    log_info "Intentando descargar imágenes pre-construidas (más rápido y menos recursos)..."
    
    if docker compose pull 2>/dev/null; then
        log_success "Imágenes pre-construidas descargadas correctamente"
    else
        log_warning "No se pudieron descargar imágenes pre-construidas"
        log_info "Intentando construir imágenes localmente (esto puede tardar 30+ minutos)..."
        log_warning "RECOMENDACIÓN: Agrega swap de 4GB si tienes menos de 4GB de RAM"
        docker compose build
        log_success "Imágenes construidas localmente"
    fi
}

################################################################################
# 11. Iniciar ODK Central
################################################################################

start_odk_central() {
    log_step "Paso 10: Se inician los contenedores de ODK Central"
    log_info "Se ejecuta: docker compose up -d"
    
    docker compose up -d
    
    echo ""
    log_info "Esperando 10 segundos iniciales para que los contenedores arranquen..."
    sleep 10
    log_success "Se completó la espera inicial de Docker Compose"
    echo ""
    
    log_success "Contenedores de ODK Central se iniciaron correctamente"
}

################################################################################
# 12. Esperar a que ODK Central esté completamente listo
################################################################################

wait_for_odk_ready() {
    log_step "Paso 11: Se espera a que ODK Central esté completamente listo"
    log_info "ODK Central necesita aproximadamente ${STARTUP_WAIT_TIME} segundos para iniciar todos sus servicios..."
    log_info "Esto incluye: PostgreSQL, migraciones de base de datos, nginx, service, etc."
    echo ""
    
    local elapsed=0
    local interval=10
    
    while [ $elapsed -lt $STARTUP_WAIT_TIME ]; do
        echo -ne "  Tiempo transcurrido: ${elapsed}/${STARTUP_WAIT_TIME} segundos\r"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    echo ""
    log_success "Se completó la espera de ${STARTUP_WAIT_TIME} segundos"
    echo ""
    
    # Verificar que los contenedores estén running
    log_info "Verificando estado de los contenedores..."
    docker compose ps
    
    echo ""
}

################################################################################
# 13. Verificar si el servicio está realmente listo para aceptar comandos
################################################################################

wait_for_service_ready() {
    log_info "Verificando que el servicio de ODK esté listo para aceptar comandos..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        # Verificar que el contenedor esté Up
        if docker compose ps service 2>/dev/null | grep -q "Up"; then
            # Intentar ejecutar un comando simple para verificar que responde
            if docker compose exec -T service odk-cmd --help >/dev/null 2>&1; then
                log_success "Servicio de ODK está listo y respondiendo"
                return 0
            fi
        fi
        
        echo -ne "  Esperando servicio (intento ${attempt}/${max_attempts})...\r"
        sleep 10
        attempt=$((attempt + 1))
    done
    
    echo ""
    log_error "El servicio no respondió después de ${max_attempts} intentos"
    return 1
}

################################################################################
# 14. Verificar si el usuario administrador ya existe
################################################################################

check_admin_user_exists() {
    if docker compose exec -T service odk-cmd --list-users 2>/dev/null | grep -q "${ADMIN_EMAIL}"; then
        return 0
    else
        return 1
    fi
}

################################################################################
# 15. Crear credenciales de administrador (CON REINTENTOS AUTOMÁTICOS)
################################################################################

create_admin_credentials() {
    log_step "Paso 12: Se crean las credenciales de administrador"
    echo ""
    
    # Esperar a que el servicio esté realmente listo
    if ! wait_for_service_ready; then
        log_error "No se pudo conectar al servicio de ODK"
        log_info "Los contenedores están corriendo, puedes crear las credenciales manualmente después"
        return 1
    fi
    echo ""
    
    local retry=1
    local credentials_created=false
    
    while [ $retry -le $MAX_RETRIES ] && [ "$credentials_created" = false ]; do
        log_info "Intento ${retry}/${MAX_RETRIES} para crear credenciales..."
        echo ""
        
        # VERIFICACIÓN: ¿El usuario ya existe?
        if check_admin_user_exists; then
            log_success "El usuario ${ADMIN_EMAIL} YA EXISTE. Configuración completada."
            credentials_created=true
            break
        fi
        
        # Crear usuario
        log_info "Creando usuario administrador..."
        if docker compose exec -T service odk-cmd --email ${ADMIN_EMAIL} user-create 2>/dev/null; then
            log_success "Usuario administrador creado correctamente"
        else
            log_warning "No se pudo crear el usuario (intento ${retry}/${MAX_RETRIES})"
            sleep 5
            retry=$((retry + 1))
            continue
        fi
        
        # Promover a administrador
        log_info "Promoviendo usuario a administrador..."
        if docker compose exec -T service odk-cmd --email ${ADMIN_EMAIL} user-promote 2>/dev/null; then
            log_success "Usuario promovido a administrador correctamente"
        else
            log_warning "No se pudo promover el usuario (intento ${retry}/${MAX_RETRIES})"
            sleep 5
            retry=$((retry + 1))
            continue
        fi
        
        # Establecer contraseña
        log_info "Estableciendo contraseña del administrador..."
        if echo "${ADMIN_PASSWORD}" | docker compose exec -T service odk-cmd --email ${ADMIN_EMAIL} user-set-password 2>/dev/null; then
            log_success "Contraseña establecida correctamente"
            credentials_created=true
        else
            log_warning "No se pudo establecer la contraseña (intento ${retry}/${MAX_RETRIES})"
            sleep 5
            retry=$((retry + 1))
            continue
        fi
    done
    
    if [ "$credentials_created" = true ]; then
        echo ""
        echo -e "${GREEN}================================================================${NC}"
        echo -e "${GREEN}  CREDENCIALES DE ADMINISTRADOR${NC}"
        echo -e "${GREEN}================================================================${NC}"
        echo -e "${CYAN}  Email: ${ADMIN_EMAIL}${NC}"
        echo -e "${CYAN}  Contraseña: ${ADMIN_PASSWORD}${NC}"
        echo -e "${GREEN}================================================================${NC}"
        echo ""
        log_success "Credenciales creadas exitosamente"
        return 0
    else
        log_error "No se pudieron crear las credenciales después de ${MAX_RETRIES} intentos"
        return 1
    fi
}

################################################################################
# 16. Verificar estado de la instalación
################################################################################

verify_installation() {
    log_step "Paso 13: Se verifica el estado de la instalación"
    log_info "Se muestra el estado final de los contenedores..."
    echo ""
    
    docker compose ps
    
    echo ""
    log_success "Instalación se completó correctamente"
}

################################################################################
# Función principal
################################################################################

main() {
    echo ""
    echo -e "${GREEN}================================================================${NC}"
    echo -e "${GREEN}  Instalador de ODK Central${NC}"
    echo -e "${GREEN}================================================================${NC}"
    echo ""
    
    check_internet_connection
    check_docker_and_compose_versions
    start_docker_service
    disable_ufw
    clone_odk_central
    
    cd "$ODK_DIR"
    
    update_submodules
    configure_env_file
    allow_postgres_upgrade
    build_docker_images
    start_odk_central
    wait_for_odk_ready
    create_admin_credentials
    verify_installation
    
    echo ""
    echo -e "${GREEN}================================================================${NC}"
    echo -e "${GREEN}  INSTALACIÓN COMPLETADA!!!${NC}"
    echo -e "${GREEN}================================================================${NC}"
    echo ""
    echo -e "Accede a ODK Central en: ${CYAN}http://localhost${NC}"
    echo -e "Directorio de instalación: ${CYAN}$(pwd)${NC}"
    echo ""
    echo -e "${BLUE}Comandos útiles:${NC}"
    echo " sudo docker compose ps      # Ver estado de contenedores"
    echo " sudo docker compose logs -f # Ver logs en tiempo real"
    echo " sudo docker compose down    # Detener contenedores"
    echo " sudo docker compose up -d   # Iniciar contenedores"
    echo ""
}

main "$@"
