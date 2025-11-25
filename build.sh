#!/bin/bash

# ============================================================================
# Build Script for POC-04-B: Keycloak SAML2 Federation
# ============================================================================
# This script:
# 1. Builds the custom Keycloak protocol mapper JAR
# 2. Builds Docker images (IdP vanilla + SP with JAR)
# 3. Optionally starts Docker containers
#
# Usage:
#   ./build.sh              # Build JAR only
#   ./build.sh --docker     # Build JAR + Docker images
#   ./build.sh --start      # Build JAR + Docker images + start containers
#   ./build.sh --clean      # Clean all build artifacts
# ============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Directories
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAPPER_DIR="$PROJECT_ROOT/keycloak-roles-mapper"
TARGET_JAR="$MAPPER_DIR/target/keycloak-roles-mapper.jar"

# ============================================================================
# Helper Functions
# ============================================================================

print_header() {
    echo -e "${BLUE}============================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}============================================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# ============================================================================
# Build Functions
# ============================================================================

build_jar() {
    print_header "Building Keycloak Roles Mapper JAR"

    cd "$MAPPER_DIR"

    # Clean previous build
    print_info "Cleaning previous build..."
    mvn clean

    # Build JAR with shaded dependencies
    print_info "Compiling and packaging JAR..."
    mvn package -DskipTests

    # Verify JAR was created
    if [ ! -f "$TARGET_JAR" ]; then
        print_error "JAR build failed: $TARGET_JAR not found"
        exit 1
    fi

    # Show JAR info
    JAR_SIZE=$(du -h "$TARGET_JAR" | cut -f1)
    print_success "JAR built successfully: $TARGET_JAR ($JAR_SIZE)"

    cd "$PROJECT_ROOT"
}

build_docker_images() {
    print_header "Building Docker Images"

    cd "$PROJECT_ROOT"

    print_info "Building Keycloak IdP (vanilla)..."
    docker-compose build keycloak-idp

    print_info "Building Keycloak SP (with custom provider)..."
    docker-compose build keycloak-sp

    print_success "Docker images built successfully"
}

start_containers() {
    print_header "Starting Docker Containers"

    cd "$PROJECT_ROOT"

    print_info "Starting containers in detached mode..."
    docker-compose up -d

    print_info "Waiting for services to be healthy..."
    echo ""
    echo "Checking service status:"
    docker-compose ps

    echo ""
    print_header "Access URLs"
    print_info "Keycloak IdP: http://localhost:8180 (admin/admin)"
    print_info "Keycloak SP:  http://localhost:8080 (admin/admin)"
    echo ""
    print_info "Follow logs with: docker-compose logs -f"
}

clean_all() {
    print_header "Cleaning All Build Artifacts"

    cd "$PROJECT_ROOT"

    # Clean Maven builds
    print_info "Cleaning Maven projects..."
    cd "$MAPPER_DIR" && mvn clean
    cd "$PROJECT_ROOT"

    # Stop and remove Docker containers
    print_info "Stopping Docker containers..."
    docker-compose down -v

    print_success "Cleanup complete"
}

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Build script for POC-04-B Keycloak SAML2 Federation

Options:
    (no args)       Build JAR only
    --docker        Build JAR + Docker images
    --start         Build JAR + Docker images + start containers
    --clean         Clean all build artifacts and stop containers
    --help          Show this help message

Examples:
    $0                  # Build JAR only
    $0 --docker         # Build JAR and Docker images
    $0 --start          # Full build and start
    $0 --clean          # Clean everything

After starting containers:
    - Keycloak IdP: http://localhost:8180 (admin/admin) - Create users here
    - Keycloak SP:  http://localhost:8080 (admin/admin) - Configure SAML here
    - Roles DB: localhost:5433 (keycloak/keycloak/roles)

EOF
}

# ============================================================================
# Main Script
# ============================================================================

main() {
    print_header "POC-04-B: Keycloak SAML2 Federation - Build Script"

    case "${1:-}" in
        --clean)
            clean_all
            ;;
        --docker)
            build_jar
            build_docker_images
            ;;
        --start)
            build_jar
            build_docker_images
            start_containers
            ;;
        --help)
            show_usage
            ;;
        "")
            # Default: just build JAR
            build_jar
            print_success "Build complete! Run '$0 --docker' to build Docker images."
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac

    echo ""
    print_success "Done!"
}

# Run main
main "$@"
