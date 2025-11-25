#!/bin/bash

# ============================================================================
# Token Test Script for POC-04-A
# ============================================================================
# Quick script to obtain and decode JWT token from Keycloak
#
# Prerequisites:
# - Keycloak running (docker-compose up -d)
# - Realm 'example-poc' configured
# - Client 'spring-client' configured
# - User 'alan.turing' created with password 'test123'
#
# Usage:
#   ./test-token.sh <CLIENT_SECRET>
#
# Example:
#   ./test-token.sh "abc123-xyz789-secret"
# ============================================================================

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
KEYCLOAK_URL="http://localhost:8080"
REALM="example-poc"
CLIENT_ID="spring-client"
USERNAME="alan.turing"
PASSWORD="test123"

# Parse arguments
if [ -z "$1" ]; then
    echo -e "${RED}Error: CLIENT_SECRET required${NC}"
    echo ""
    echo "Usage: $0 <CLIENT_SECRET>"
    echo ""
    echo "Get the client secret from:"
    echo "  Keycloak Admin Console → Clients → spring-client → Credentials tab"
    exit 1
fi

CLIENT_SECRET="$1"

# ============================================================================
# Functions
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

decode_jwt() {
    local token="$1"
    local part="$2"  # 0=header, 1=payload, 2=signature

    # Extract part (header.payload.signature)
    local jwt_part=$(echo "$token" | cut -d. -f$((part + 1)))

    # Add padding if needed (JWT base64url encoding)
    local padding=$((4 - ${#jwt_part} % 4))
    if [ $padding -ne 4 ]; then
        jwt_part="${jwt_part}$(printf '%*s' $padding | tr ' ' '=')"
    fi

    # Decode (replace base64url chars with base64)
    echo "$jwt_part" | tr '_-' '/+' | base64 -d 2>/dev/null | jq '.' 2>/dev/null || echo "$jwt_part"
}

# ============================================================================
# Main
# ============================================================================

print_header "POC-04-A: Token Test"

# Step 1: Request token
print_info "Requesting token from Keycloak..."
echo ""

TOKEN_RESPONSE=$(curl -s -X POST \
    "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=${CLIENT_ID}" \
    -d "client_secret=${CLIENT_SECRET}" \
    -d "username=${USERNAME}" \
    -d "password=${PASSWORD}" \
    -d "grant_type=password")

# Check for errors
if echo "$TOKEN_RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
    print_error "Token request failed!"
    echo ""
    echo "Error details:"
    echo "$TOKEN_RESPONSE" | jq '.'
    exit 1
fi

# Extract tokens
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token')
ID_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.id_token')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
    print_error "Failed to extract access token"
    echo ""
    echo "Response:"
    echo "$TOKEN_RESPONSE" | jq '.'
    exit 1
fi

print_success "Token obtained successfully!"
echo ""

# Step 2: Display token info
print_header "Token Information"
echo ""

print_info "Token Type: $(echo "$TOKEN_RESPONSE" | jq -r '.token_type')"
print_info "Expires In: $(echo "$TOKEN_RESPONSE" | jq -r '.expires_in') seconds"
print_info "Scope: $(echo "$TOKEN_RESPONSE" | jq -r '.scope')"
echo ""

# Step 3: Decode and display payload
print_header "Access Token Payload"
echo ""

PAYLOAD=$(decode_jwt "$ACCESS_TOKEN" 1)
echo "$PAYLOAD" | jq '.'
echo ""

# Step 4: Check for external_roles claim
print_header "External Roles Verification"
echo ""

EXTERNAL_ROLES=$(echo "$PAYLOAD" | jq -r '.external_roles')

if [ "$EXTERNAL_ROLES" = "null" ]; then
    print_error "external_roles claim NOT FOUND in token!"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Verify Protocol Mapper is configured in Keycloak"
    echo "  2. Check Keycloak logs: docker-compose logs keycloak | grep external"
    echo "  3. Verify mapper is added to client scope"
    exit 1
fi

if [ "$EXTERNAL_ROLES" = "[]" ]; then
    print_error "external_roles claim is empty!"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check if user exists in roles database:"
    echo "     docker-compose exec roles-db psql -U keycloak -d roles -c \"SELECT * FROM user_roles WHERE username = '$USERNAME';\""
    echo "  2. Verify database connectivity from Keycloak"
    echo "  3. Check Keycloak logs for errors"
    exit 1
fi

print_success "external_roles claim found!"
echo ""
echo "Roles for user '$USERNAME':"
echo "$PAYLOAD" | jq -r '.external_roles[]' | while read role; do
    echo "  • $role"
done
echo ""

# Step 5: Display full token for manual inspection
print_header "Full Access Token (for jwt.io)"
echo ""
echo "$ACCESS_TOKEN"
echo ""
print_info "Copy the token above and paste it into https://jwt.io to inspect"
echo ""

# Step 6: Save tokens to file
print_header "Saving Tokens"
echo ""

OUTPUT_FILE="tokens.json"
cat > "$OUTPUT_FILE" <<EOF
{
  "access_token": "$ACCESS_TOKEN",
  "refresh_token": "$REFRESH_TOKEN",
  "id_token": "$ID_TOKEN",
  "token_type": "$(echo "$TOKEN_RESPONSE" | jq -r '.token_type')",
  "expires_in": $(echo "$TOKEN_RESPONSE" | jq -r '.expires_in'),
  "scope": "$(echo "$TOKEN_RESPONSE" | jq -r '.scope')"
}
EOF

print_success "Tokens saved to $OUTPUT_FILE"
echo ""

print_header "Test Complete!"
print_success "All checks passed! External roles mapper is working correctly."
echo ""
