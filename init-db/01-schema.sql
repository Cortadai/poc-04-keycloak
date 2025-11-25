-- ============================================================================
-- POC-04-A: External Roles Database Schema
-- ============================================================================
-- This script initializes the external PostgreSQL database that stores
-- user role mappings outside of Keycloak's internal database.
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
COMMENT ON COLUMN user_roles.username IS 'Keycloak username (must match exactly)';
COMMENT ON COLUMN user_roles.role_name IS 'Role identifier to be added to JWT';

-- ============================================================================
-- Test Data - Using individual INSERTs for compatibility
-- ============================================================================

-- Primary test user (alan.turing)
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
INSERT INTO user_roles (username, role_name) VALUES ('bob.johnson', 'ADMIN');
INSERT INTO user_roles (username, role_name) VALUES ('alice.williams', 'VIEWER');

-- ============================================================================
-- Verify data insertion
-- ============================================================================
SELECT username, COUNT(*) AS role_count, STRING_AGG(role_name, ', ' ORDER BY role_name) AS roles
FROM user_roles
GROUP BY username
ORDER BY username;
