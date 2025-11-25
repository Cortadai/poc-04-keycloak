# ============================================================================
# Keycloak SP (Service Provider) with Custom Roles Mapper
# ============================================================================
# Keycloak que actúa como Service Provider SAML2.
# Recibe usuarios federados del IdP via SAML assertions.
# Incluye el JAR custom que consulta roles externos en PostgreSQL.
# ============================================================================

FROM quay.io/keycloak/keycloak:23.0.7

WORKDIR /opt/keycloak

# Copy custom provider JAR from Maven target directory
COPY keycloak-roles-mapper/target/keycloak-roles-mapper.jar /opt/keycloak/providers/

# Build Keycloak with custom provider
RUN /opt/keycloak/bin/kc.sh build --db=postgres --health-enabled=true --metrics-enabled=true

# Runtime configuration
ENV KC_HTTP_ENABLED=true
ENV KC_HOSTNAME_STRICT=false

# External roles database defaults (overridden in docker-compose.yml)
ENV ROLES_DB_URL=jdbc:postgresql://roles-db:5432/roles
ENV ROLES_DB_USER=keycloak
ENV ROLES_DB_PASSWORD=keycloak
ENV ROLES_DB_POOL_SIZE=10
ENV ROLES_DB_MIN_IDLE=2

EXPOSE 8080 8443

HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/health/ready || exit 1

ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
