package com.example.controller;

import org.springframework.security.oauth2.client.OAuth2AuthorizedClient;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientService;
import org.springframework.security.oauth2.client.authentication.OAuth2AuthenticationToken;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Controller that exposes the access token for testing purposes.
 * Simulates what an SPA would do: obtain the JWT and store it for API calls.
 */
@RestController
@RequestMapping("/api")
public class TokenController {

    private final OAuth2AuthorizedClientService authorizedClientService;

    public TokenController(OAuth2AuthorizedClientService authorizedClientService) {
        this.authorizedClientService = authorizedClientService;
    }

    /**
     * Returns the current user's access token.
     * In a real SPA, this token would be stored in localStorage/sessionStorage
     * and used for Authorization: Bearer headers.
     */
    @GetMapping("/token")
    public Map<String, Object> getToken(OAuth2AuthenticationToken authentication) {
        OAuth2AuthorizedClient client = authorizedClientService.loadAuthorizedClient(
            authentication.getAuthorizedClientRegistrationId(),
            authentication.getName()
        );

        if (client == null || client.getAccessToken() == null) {
            return Map.of("error", "No access token available");
        }

        return Map.of(
            "access_token", client.getAccessToken().getTokenValue(),
            "token_type", "Bearer",
            "expires_at", client.getAccessToken().getExpiresAt() != null
                ? client.getAccessToken().getExpiresAt().toString()
                : "unknown",
            "scopes", client.getAccessToken().getScopes()
        );
    }
}
