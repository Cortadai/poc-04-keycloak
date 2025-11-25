# ============================================================================
# Keycloak with Custom External Roles Provider
# ============================================================================
# This Dockerfile builds a Keycloak image with the custom protocol mapper
# that fetches roles from an external PostgreSQL database.
#
# Build process:
# 1. Start from official Keycloak image
# 2. Copy custom provider JAR to providers directory
# 3. Run kc.sh build to optimize and register the provider
# ============================================================================

FROM quay.io/keycloak/keycloak:23.0.7

# Set working directory
WORKDIR /opt/keycloak

# Copy custom provider JAR directly from Maven target directory
# (build context is project root, so we can access keycloak-roles-mapper/target/)
COPY keycloak-roles-mapper/target/keycloak-roles-mapper.jar /opt/keycloak/providers/

# Build Keycloak with the custom provider
# This step:
# - Scans and registers providers from /opt/keycloak/providers/
# - Configures PostgreSQL as database (build-time property)
# - Enables health and metrics endpoints
# - Optimizes startup performance
# - Validates provider configuration
RUN /opt/keycloak/bin/kc.sh build --db=postgres --health-enabled=true --metrics-enabled=true

# Environment variables for Keycloak (runtime configuration)
# Note: KC_DB, KC_HEALTH_ENABLED, KC_METRICS_ENABLED are already set at build time
ENV KC_HTTP_ENABLED=true
ENV KC_HOSTNAME_STRICT=false

# Environment variables for external roles database
# These can be overridden in docker-compose.yml
ENV ROLES_DB_URL=jdbc:postgresql://roles-db:5432/roles
ENV ROLES_DB_USER=keycloak
ENV ROLES_DB_PASSWORD=keycloak
ENV ROLES_DB_POOL_SIZE=10
ENV ROLES_DB_MIN_IDLE=2

# Expose ports
# 8080: HTTP
# 8443: HTTPS (if configured)
# 9000: Management/metrics (if needed)
EXPOSE 8080 8443 9000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/health/ready || exit 1

# Entry point
ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]