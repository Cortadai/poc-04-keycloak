# ============================================================================
# Keycloak IdP (Identity Provider) - Vanilla
# ============================================================================
# Keycloak vanilla que actúa como Identity Provider SAML2.
# Simula FortiAuthenticator u otro IdP externo.
# Contiene usuarios nativos que se federan al SP.
# ============================================================================

FROM quay.io/keycloak/keycloak:23.0.7

WORKDIR /opt/keycloak

# Build Keycloak optimizado para PostgreSQL
RUN /opt/keycloak/bin/kc.sh build --db=postgres --health-enabled=true --metrics-enabled=true

# Runtime configuration
ENV KC_HTTP_ENABLED=true
ENV KC_HOSTNAME_STRICT=false

EXPOSE 8080 8443

HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/health/ready || exit 1

ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
