package com.example.keycloak.mapper;

import org.keycloak.models.ClientSessionContext;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.ProtocolMapperModel;
import org.keycloak.models.UserSessionModel;
import org.keycloak.protocol.oidc.mappers.AbstractOIDCProtocolMapper;
import org.keycloak.protocol.oidc.mappers.OIDCAccessTokenMapper;
import org.keycloak.protocol.oidc.mappers.OIDCAttributeMapperHelper;
import org.keycloak.protocol.oidc.mappers.OIDCIDTokenMapper;
import org.keycloak.protocol.oidc.mappers.UserInfoTokenMapper;
import org.keycloak.provider.ProviderConfigProperty;
import org.keycloak.representations.IDToken;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.ArrayList;
import java.util.List;

/**
 * Custom Keycloak Protocol Mapper that fetches user roles from an external PostgreSQL database
 * and adds them to the JWT token as a custom claim.
 *
 * This mapper implements three interfaces to ensure the external roles are added to:
 * - Access tokens (OIDCAccessTokenMapper)
 * - ID tokens (OIDCIDTokenMapper)
 * - UserInfo endpoint responses (UserInfoTokenMapper)
 */
public class ExternalRolesProtocolMapper extends AbstractOIDCProtocolMapper
        implements OIDCAccessTokenMapper, OIDCIDTokenMapper, UserInfoTokenMapper {

    private static final Logger logger = LoggerFactory.getLogger(ExternalRolesProtocolMapper.class);

    // Unique identifier for this mapper
    public static final String PROVIDER_ID = "external-roles-protocol-mapper";

    // Claim name in JWT
    private static final String CLAIM_NAME = "external_roles";

    // Display name in Keycloak Admin Console
    private static final String DISPLAY_NAME = "External Database Roles Mapper";

    // Help text for admin users
    private static final String HELP_TEXT = "Fetches user roles from external PostgreSQL database and adds them to tokens";

    /**
     * Return the unique provider ID for this mapper.
     */
    @Override
    public String getId() {
        return PROVIDER_ID;
    }

    /**
     * Return the display name shown in Keycloak Admin Console.
     */
    @Override
    public String getDisplayType() {
        return DISPLAY_NAME;
    }

    /**
     * Return the category for grouping in Admin Console.
     */
    @Override
    public String getDisplayCategory() {
        return TOKEN_MAPPER_CATEGORY;
    }

    /**
     * Return help text displayed in Admin Console.
     */
    @Override
    public String getHelpText() {
        return HELP_TEXT;
    }

    /**
     * Define configuration properties visible in Admin Console.
     * Adds standard toggle switches for controlling which tokens include the claim.
     */
    @Override
    public List<ProviderConfigProperty> getConfigProperties() {
        List<ProviderConfigProperty> properties = new ArrayList<>();

        // Add standard "Add to ID token", "Add to access token", "Add to userinfo" toggles
        OIDCAttributeMapperHelper.addIncludeInTokensConfig(properties, ExternalRolesProtocolMapper.class);

        return properties;
    }

    /**
     * Core method: Add the external roles claim to the token.
     * This is called for access tokens, ID tokens, and UserInfo responses.
     */
    @Override
    protected void setClaim(IDToken token, ProtocolMapperModel mappingModel,
                            UserSessionModel userSession, KeycloakSession keycloakSession,
                            ClientSessionContext clientSessionCtx) {

        System.out.println("🔥 [EXTERNAL-ROLES-MAPPER] Mapper is executing!");
        logger.info("🔥 External Roles Mapper executing for token generation");

        // Get username from the authenticated user
        String username = userSession.getUser().getUsername();

        if (username == null || username.trim().isEmpty()) {
            System.err.println("❌ [EXTERNAL-ROLES-MAPPER] Username is null or empty");
            logger.warn("Cannot fetch external roles: username is null or empty");
            return;
        }

        System.out.println("🔥 [EXTERNAL-ROLES-MAPPER] Fetching roles for user: " + username);
        logger.info("Fetching external roles for user: {}", username);

        try {
            // Fetch roles from external database
            List<String> externalRoles = RoleRepository.getRolesForUser(username);

            // Add roles to token as a custom claim
            if (externalRoles != null && !externalRoles.isEmpty()) {
                token.getOtherClaims().put(CLAIM_NAME, externalRoles);
                System.out.println("✅ [EXTERNAL-ROLES-MAPPER] Added " + externalRoles.size() + " roles: " + externalRoles);
                logger.info("Added {} external roles for user '{}' to token: {}", externalRoles.size(), username, externalRoles);
            } else {
                // Add empty array to indicate no roles found (vs error)
                token.getOtherClaims().put(CLAIM_NAME, new ArrayList<String>());
                System.out.println("⚠️ [EXTERNAL-ROLES-MAPPER] No roles found for user: " + username);
                logger.info("No external roles found for user '{}'", username);
            }

        } catch (Exception e) {
            System.err.println("❌ [EXTERNAL-ROLES-MAPPER] Error: " + e.getMessage());
            e.printStackTrace();
            logger.error("Unexpected error fetching external roles for user '{}': {}",
                    username, e.getMessage(), e);

            // Add empty array on error to allow authentication to proceed
            token.getOtherClaims().put(CLAIM_NAME, new ArrayList<String>());
        }
    }
}
