#!/bin/bash

# ============================================================================
# SAML Flow Test Script for POC-04-B
# ============================================================================
# Tests the complete SAML federation flow:
# 1. Shows authorization URL to open in browser
# 2. User authenticates via SAML IdP
# 3. Script exchanges code for token
# 4. Displays decoded token with external_roles
#
# Usage:
#   ./test-flow.sh <CLIENT_SECRET>
# ============================================================================

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
KEYCLOAK_URL="http://localhost:8080"
REALM="sp-realm"
CLIENT_ID="spring-client"
REDIRECT_URI="http://localhost:8080/"

# ============================================================================
# Functions
# ============================================================================

print_header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}→ $1${NC}"
}

decode_jwt_payload() {
    local token="$1"
    # Extract payload (second part)
    local payload=$(echo "$token" | cut -d. -f2)
    # Add padding if needed
    local padding=$((4 - ${#payload} % 4))
    if [ $padding -ne 4 ]; then
        payload="${payload}$(printf '%*s' $padding | tr ' ' '=')"
    fi
    # Decode
    echo "$payload" | tr '_-' '/+' | base64 -d 2>/dev/null
}

# ============================================================================
# Main
# ============================================================================

# Check arguments
if [ -z "$1" ]; then
    echo -e "${RED}Error: CLIENT_SECRET required${NC}"
    echo ""
    echo "Usage: $0 <CLIENT_SECRET>"
    echo ""
    echo "Get the client secret from:"
    echo "  SP Admin Console (8080) → Clients → spring-client → Credentials"
    exit 1
fi

CLIENT_SECRET="$1"

print_header "POC-04-B: SAML Federation Test"

# Build authorization URL
AUTH_URL="${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/auth?client_id=${CLIENT_ID}&response_type=code&redirect_uri=${REDIRECT_URI}&scope=openid"

echo -e "${CYAN}Paso 1: Abre esta URL en tu navegador:${NC}"
echo ""
echo -e "${YELLOW}$AUTH_URL${NC}"
echo ""
echo -e "${CYAN}Paso 2: Click en 'Login con FortiAuth (Simulado)'${NC}"
echo ""
echo -e "${CYAN}Paso 3: Autentícate con:${NC}"
echo "         Username: alan.turing"
echo "         Password: test123"
echo ""
echo -e "${CYAN}Paso 4: Serás redirigido a una URL como:${NC}"
echo "         http://localhost:8080/?code=XXXXX...&session_state=..."
echo ""

# Prompt for code
echo -e "${GREEN}Pega aquí el 'code' de la URL (solo el valor después de 'code='):${NC}"
read -r AUTH_CODE

# Clean the code (remove trailing slash or extra params)
AUTH_CODE=$(echo "$AUTH_CODE" | sed 's/[&/].*//')

if [ -z "$AUTH_CODE" ]; then
    print_error "No se proporcionó ningún código"
    exit 1
fi

print_header "Intercambiando código por token..."

# Exchange code for token
TOKEN_RESPONSE=$(curl -s -X POST \
    "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=${CLIENT_ID}" \
    -d "client_secret=${CLIENT_SECRET}" \
    -d "grant_type=authorization_code" \
    -d "code=${AUTH_CODE}" \
    -d "redirect_uri=${REDIRECT_URI}")

# Check for errors
if echo "$TOKEN_RESPONSE" | grep -q '"error"'; then
    print_error "Error al obtener token:"
    echo "$TOKEN_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$TOKEN_RESPONSE"
    exit 1
fi

# Extract access token
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('access_token', ''))" 2>/dev/null)

if [ -z "$ACCESS_TOKEN" ]; then
    print_error "No se pudo extraer el access_token"
    echo "$TOKEN_RESPONSE"
    exit 1
fi

print_success "Token obtenido correctamente!"

print_header "Contenido del Token (Payload)"

# Decode and display
PAYLOAD=$(decode_jwt_payload "$ACCESS_TOKEN")
echo "$PAYLOAD" | python3 -m json.tool 2>/dev/null || echo "$PAYLOAD"

print_header "Verificación de external_roles"

# Check for external_roles
EXTERNAL_ROLES=$(echo "$PAYLOAD" | python3 -c "import sys, json; roles = json.load(sys.stdin).get('external_roles', []); print(roles if roles else 'NOT_FOUND')" 2>/dev/null)

if [ "$EXTERNAL_ROLES" = "NOT_FOUND" ] || [ "$EXTERNAL_ROLES" = "[]" ] || [ -z "$EXTERNAL_ROLES" ]; then
    print_error "external_roles NO encontrado o vacío"
    echo ""
    echo "Verifica:"
    echo "  1. El Protocol Mapper está configurado en spring-client"
    echo "  2. La base de datos roles-db tiene datos para el usuario"
    echo "  3. Los logs del SP: docker-compose logs keycloak-sp | grep -i external"
    exit 1
fi

print_success "external_roles encontrado!"
echo ""
echo "Roles del usuario:"
echo "$PAYLOAD" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for role in data.get('external_roles', []):
    print(f'  • {role}')
print()
print(f\"Usuario: {data.get('preferred_username', 'N/A')}\")
print(f\"Nombre: {data.get('name', 'N/A')}\")
print(f\"Email: {data.get('email', 'N/A')}\")
" 2>/dev/null

print_header "Test Completado"
print_success "El flujo SAML + External Roles funciona correctamente!"
echo ""
