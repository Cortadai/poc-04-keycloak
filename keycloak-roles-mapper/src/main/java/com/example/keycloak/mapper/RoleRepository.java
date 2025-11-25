package com.example.keycloak.mapper;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Repository for fetching user roles from external PostgreSQL database.
 * Uses HikariCP connection pooling for efficient database connectivity.
 */
public class RoleRepository {

    private static final Logger logger = LoggerFactory.getLogger(RoleRepository.class);

    private static final String QUERY_ROLES = "SELECT role_name FROM user_roles WHERE username = ? ORDER BY role_name";

    private static volatile HikariDataSource dataSource;

    /**
     * Initialize the HikariCP data source (singleton pattern with double-checked locking).
     * Configuration is read from environment variables for flexibility.
     */
    private static HikariDataSource getDataSource() {
        if (dataSource == null) {
            synchronized (RoleRepository.class) {
                if (dataSource == null) {
                    logger.info("Initializing HikariCP DataSource for external roles database");

                    HikariConfig config = new HikariConfig();

                    // Database connection properties from environment variables
                    config.setJdbcUrl(getEnvOrDefault("ROLES_DB_URL", "jdbc:postgresql://roles-db:5432/roles"));
                    config.setUsername(getEnvOrDefault("ROLES_DB_USER", "keycloak"));
                    config.setPassword(getEnvOrDefault("ROLES_DB_PASSWORD", "keycloak"));
                    config.setDriverClassName("org.postgresql.Driver");

                    // Connection pool settings
                    config.setMaximumPoolSize(Integer.parseInt(getEnvOrDefault("ROLES_DB_POOL_SIZE", "10")));
                    config.setMinimumIdle(Integer.parseInt(getEnvOrDefault("ROLES_DB_MIN_IDLE", "2")));
                    config.setConnectionTimeout(Long.parseLong(getEnvOrDefault("ROLES_DB_CONN_TIMEOUT", "30000")));
                    config.setIdleTimeout(Long.parseLong(getEnvOrDefault("ROLES_DB_IDLE_TIMEOUT", "600000")));
                    config.setMaxLifetime(Long.parseLong(getEnvOrDefault("ROLES_DB_MAX_LIFETIME", "1800000")));

                    // Connection validation
                    config.setConnectionTestQuery("SELECT 1");
                    config.setValidationTimeout(5000);

                    // Pool name for monitoring
                    config.setPoolName("KeycloakExternalRolesPool");

                    dataSource = new HikariDataSource(config);
                    logger.info("HikariCP DataSource initialized successfully");
                }
            }
        }
        return dataSource;
    }

    /**
     * Fetch roles for a given username from external database.
     *
     * @param username the username to fetch roles for
     * @return list of role names, empty list if none found or on error
     */
    public static List<String> getRolesForUser(String username) {
        if (username == null || username.trim().isEmpty()) {
            logger.warn("getRolesForUser called with null or empty username");
            return Collections.emptyList();
        }

        List<String> roles = new ArrayList<>();
        long startTime = System.currentTimeMillis();

        try (Connection conn = getDataSource().getConnection();
             PreparedStatement stmt = conn.prepareStatement(QUERY_ROLES)) {

            stmt.setString(1, username);

            try (ResultSet rs = stmt.executeQuery()) {
                while (rs.next()) {
                    String roleName = rs.getString("role_name");
                    if (roleName != null && !roleName.trim().isEmpty()) {
                        roles.add(roleName);
                    }
                }
            }

            long duration = System.currentTimeMillis() - startTime;
            logger.debug("Fetched {} roles for user '{}' in {}ms", roles.size(), username, duration);

        } catch (SQLException e) {
            logger.error("Error fetching roles for user '{}': {}", username, e.getMessage(), e);
            // Return empty list on error - allows authentication to proceed without external roles
            return Collections.emptyList();
        }

        return roles;
    }

    /**
     * Get environment variable with default fallback.
     */
    private static String getEnvOrDefault(String key, String defaultValue) {
        String value = System.getenv(key);
        return (value != null && !value.trim().isEmpty()) ? value : defaultValue;
    }

    /**
     * Shutdown the connection pool (called during application shutdown).
     */
    public static void shutdown() {
        if (dataSource != null && !dataSource.isClosed()) {
            logger.info("Shutting down HikariCP DataSource");
            dataSource.close();
        }
    }
}
