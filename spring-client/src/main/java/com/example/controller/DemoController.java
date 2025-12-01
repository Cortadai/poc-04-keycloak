package com.example.controller;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.core.oidc.user.OidcUser;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * Demo controller to test OAuth2/OIDC authentication with Keycloak
 * and external roles authorization.
 */
@RestController
public class DemoController {

    @GetMapping("/")
    public String home() {
        return """
            <html>
            <head><title>Spring Client - Keycloak SAML Federation</title></head>
            <body>
                <h1>Spring Client</h1>
                <p>Public page - no authentication required</p>
                <ul>
                    <li><a href="/protected">Protected endpoint</a> (requires login)</li>
                    <li><a href="/admin">Admin endpoint</a> (requires ARCHITECT role)</li>
                    <li><a href="/api/token">Get Access Token (JSON)</a> (for API testing)</li>
                </ul>
            </body>
            </html>
            """;
    }

    @GetMapping("/protected")
    public String protectedEndpoint(@AuthenticationPrincipal OidcUser user) {
        String username = user.getPreferredUsername();
        List<String> externalRoles = user.getClaimAsStringList("external_roles");

        return """
            <html>
            <head><title>Protected - Spring Client</title></head>
            <body>
                <h1>Protected Endpoint</h1>
                <p>Hello, <strong>%s</strong>!</p>
                <h2>Your External Roles:</h2>
                <ul>%s</ul>
                <h2>All Authorities:</h2>
                <pre>%s</pre>
                <p><a href="/">Back to home</a> | <a href="/admin">Try admin</a> | <a href="/logout">Logout</a></p>
            </body>
            </html>
            """.formatted(
                username,
                externalRoles != null ? externalRoles.stream().map(r -> "<li>" + r + "</li>").reduce("", String::concat) : "<li>No external roles</li>",
                user.getAuthorities()
            );
    }

    @GetMapping("/admin")
    @PreAuthorize("hasRole('ARCHITECT')")
    public String adminEndpoint(@AuthenticationPrincipal OidcUser user) {
        return """
            <html>
            <head><title>Admin - Spring Client</title></head>
            <body>
                <h1>Admin Endpoint</h1>
                <p>Welcome, <strong>%s</strong>!</p>
                <p>You have the <strong>ARCHITECT</strong> role and can access this restricted area.</p>
                <p><a href="/">Back to home</a> | <a href="/logout">Logout</a></p>
            </body>
            </html>
            """.formatted(user.getPreferredUsername());
    }
}
