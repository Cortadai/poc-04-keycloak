-- ============================================================================
-- POC-04-B: External Roles Database Schema
-- ============================================================================
-- PostgreSQL database for external user roles.
-- Used by the custom Protocol Mapper JAR in Keycloak SP.
-- The username must match exactly the federated user's username from SAML.
-- ============================================================================

-- Drop existing table if re-running (for idempotency)
DROP TABLE IF EXISTS user_roles CASCADE;

-- Create user_roles table
CREATE TABLE user_roles (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) NOT NULL,
    role_name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_user_role UNIQUE (username, role_name)
);

-- Create indexes for fast lookups
CREATE INDEX idx_user_roles_username ON user_roles(username);
CREATE INDEX idx_user_roles_role_name ON user_roles(role_name);

-- Add comments
COMMENT ON TABLE user_roles IS 'External roles storage for Keycloak custom mapper';
COMMENT ON COLUMN user_roles.username IS 'Username from SAML assertion (must match federated user)';
COMMENT ON COLUMN user_roles.role_name IS 'Role identifier to be added to JWT';

-- ============================================================================
-- Test Data
-- ============================================================================
-- These usernames must match the usernames created in Keycloak IdP
-- and that come through SAML assertions.
-- ============================================================================

-- Primary test user
INSERT INTO user_roles (username, role_name) VALUES ('alan.turing', 'DEVELOPER');
INSERT INTO user_roles (username, role_name) VALUES ('alan.turing', 'ARCHITECT');
INSERT INTO user_roles (username, role_name) VALUES ('alan.turing', 'ADMIN');

-- Secondary test user
INSERT INTO user_roles (username, role_name) VALUES ('test.user', 'DEVELOPER');
INSERT INTO user_roles (username, role_name) VALUES ('test.user', 'TESTER');

-- Additional test users
INSERT INTO user_roles (username, role_name) VALUES ('john.doe', 'VIEWER');
INSERT INTO user_roles (username, role_name) VALUES ('jane.smith', 'DEVELOPER');
INSERT INTO user_roles (username, role_name) VALUES ('jane.smith', 'TEAM_LEAD');

-- ============================================================================
-- Verify data insertion
-- ============================================================================
SELECT username, COUNT(*) AS role_count, STRING_AGG(role_name, ', ' ORDER BY role_name) AS roles
FROM user_roles
GROUP BY username
ORDER BY username;
