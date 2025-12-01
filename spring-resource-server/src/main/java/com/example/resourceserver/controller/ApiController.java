package com.example.resourceserver.controller;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * API Controller for the Resource Server.
 * Demonstrates JWT validation and role-based access control using external_roles.
 */
@RestController
@RequestMapping("/api")
public class ApiController {

    /**
     * Public endpoint - no authentication required.
     * Useful for health checks.
     */
    @GetMapping("/hello")
    public Map<String, Object> hello() {
        return Map.of(
            "message", "Hello from Resource Server!",
            "status", "public",
            "timestamp", System.currentTimeMillis()
        );
    }

    /**
     * Protected endpoint - requires valid JWT token.
     * Returns user information extracted from the token.
     */
    @GetMapping("/userinfo")
    public Map<String, Object> userInfo(@AuthenticationPrincipal Jwt jwt) {
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("message", "Authenticated user info");
        response.put("subject", jwt.getSubject());
        response.put("preferred_username", jwt.getClaimAsString("preferred_username"));
        response.put("email", jwt.getClaimAsString("email"));
        response.put("external_roles", jwt.getClaimAsStringList("external_roles"));
        response.put("issuer", jwt.getIssuer().toString());
        response.put("expires_at", jwt.getExpiresAt().toString());
        return response;
    }

    /**
     * Admin endpoint - requires ARCHITECT role.
     * Demonstrates @PreAuthorize with external_roles mapped to Spring authorities.
     */
    @GetMapping("/admin")
    @PreAuthorize("hasRole('ARCHITECT')")
    public Map<String, Object> admin(@AuthenticationPrincipal Jwt jwt) {
        List<String> externalRoles = jwt.getClaimAsStringList("external_roles");

        return Map.of(
            "message", "Welcome to the admin area!",
            "user", jwt.getClaimAsString("preferred_username"),
            "external_roles", externalRoles != null ? externalRoles : List.of(),
            "access_level", "ARCHITECT",
            "note", "You have access because your external_roles include ARCHITECT"
        );
    }

    /**
     * Developer endpoint - requires DEVELOPER role.
     */
    @GetMapping("/developer")
    @PreAuthorize("hasRole('DEVELOPER')")
    public Map<String, Object> developer(@AuthenticationPrincipal Jwt jwt) {
        return Map.of(
            "message", "Developer resources",
            "user", jwt.getClaimAsString("preferred_username"),
            "access_level", "DEVELOPER"
        );
    }
}
