# 🏗️ Architecture Documentation - POC-04-A

## Overview

POC-04-A demonstrates a **custom Keycloak Protocol Mapper** that fetches user roles from an **external PostgreSQL database** and injects them into JWT tokens as a custom claim.

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Client Application                        │
│                    (Browser / Postman / curl)                    │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │ 1. POST /token (username/password)
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Keycloak Server                             │
│                    (Port 8080, Container)                        │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐    │
│  │              Authentication Flow                        │    │
│  │  1. Validate credentials (native user store)           │    │
│  │  2. Create user session                                │    │
│  │  3. Generate base token                                │    │
│  └─────────────────┬──────────────────────────────────────┘    │
│                    │                                             │
│                    │ 4. Token generation event                   │
│                    ▼                                             │
│  ┌────────────────────────────────────────────────────────┐    │
│  │      Custom Protocol Mapper (OUR CODE)                 │    │
│  │                                                         │    │
│  │  ExternalRolesProtocolMapper.java                      │    │
│  │  - Implements: OIDCAccessTokenMapper                   │    │
│  │  - Implements: OIDCIDTokenMapper                       │    │
│  │  - Implements: UserInfoTokenMapper                     │    │
│  │                                                         │    │
│  │  setClaim() method:                                    │    │
│  │    1. Extract username from UserSessionModel           │    │
│  │    2. Call RoleRepository.getRolesForUser()            │    │
│  │    3. Add "external_roles" claim to token              │    │
│  └─────────────────┬──────────────────────────────────────┘    │
│                    │                                             │
└────────────────────┼─────────────────────────────────────────────┘
                     │
                     │ 5. JDBC query via HikariCP
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│            RoleRepository.java (OUR CODE)                        │
│                                                                  │
│  - HikariCP Connection Pool (10 max connections)                │
│  - Query: SELECT role_name FROM user_roles WHERE username = ?   │
│  - Returns: List<String> of role names                          │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │ 6. PostgreSQL query
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│             PostgreSQL: roles-db (Container)                     │
│                     Port 5433:5432                               │
│                                                                  │
│  Database: roles                                                 │
│  Table: user_roles                                               │
│    - id (serial)                                                 │
│    - username (varchar)                                          │
│    - role_name (varchar)                                         │
│    - created_at (timestamp)                                      │
│                                                                  │
│  Indexes:                                                        │
│    - idx_user_roles_username (for fast lookups)                 │
│    - unique_user_role (username, role_name)                     │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │ 7. Returns roles
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                         JWT Token                                │
│                                                                  │
│  {                                                               │
│    "sub": "abc123-def456-...",                                  │
│    "preferred_username": "alan.turing",                     │
│    "email": "alan.turing@example.com",                        │
│    "external_roles": [           ◄── OUR CUSTOM CLAIM           │
│      "ADMIN",                                                    │
│      "ARCHITECT",                                                │
│      "DEVELOPER"                                                 │
│    ],                                                            │
│    "exp": 1234567890,                                           │
│    "iat": 1234567890,                                           │
│    ...                                                           │
│  }                                                               │
└─────────────────────────────────────────────────────────────────┘
```

---

## Component Details

### 1. Keycloak Server

**Technology**: Keycloak 23.0.7 (Quarkus-based)

**Responsibilities**:
- User authentication (native users in POC-04-A)
- Token generation (JWT)
- Protocol Mapper orchestration
- Admin Console

**Configuration**:
- Realm: `example-poc`
- Client: `spring-client` (confidential)
- User: `alan.turing` / `test123`

**Database**: PostgreSQL `keycloak-db` (internal data)

---

### 2. Custom Protocol Mapper

**Location**: `keycloak-roles-mapper/src/main/java/com/example/keycloak/mapper/`

#### ExternalRolesProtocolMapper.java

**Type**: Keycloak SPI Extension (Protocol Mapper)

**Implements**:
- `AbstractOIDCProtocolMapper` (base class)
- `OIDCAccessTokenMapper` (access tokens)
- `OIDCIDTokenMapper` (ID tokens)
- `UserInfoTokenMapper` (UserInfo endpoint)

**Key Methods**:

```java
@Override
public String getId() {
    return "external-roles-protocol-mapper";
}

@Override
protected void setClaim(IDToken token, ProtocolMapperModel mappingModel,
                        UserSessionModel userSession, KeycloakSession keycloakSession,
                        ClientSessionContext clientSessionCtx) {
    String username = userSession.getUser().getUsername();
    List<String> roles = RoleRepository.getRolesForUser(username);
    token.getOtherClaims().put("external_roles", roles);
}
```

**Registration**: `META-INF/services/org.keycloak.protocol.ProtocolMapper`

---

### 3. Role Repository

**Location**: `keycloak-roles-mapper/src/main/java/com/example/keycloak/mapper/RoleRepository.java`

**Type**: Data Access Layer

**Features**:
- **HikariCP Connection Pooling** (high performance)
- **Singleton DataSource** (shared across all requests)
- **Environment-based Configuration** (12-factor app)
- **Error handling** (returns empty list on failure)

**Configuration** (via environment variables):
```properties
ROLES_DB_URL=jdbc:postgresql://roles-db:5432/roles
ROLES_DB_USER=keycloak
ROLES_DB_PASSWORD=keycloak
ROLES_DB_POOL_SIZE=10
ROLES_DB_MIN_IDLE=2
ROLES_DB_CONN_TIMEOUT=30000
ROLES_DB_IDLE_TIMEOUT=600000
ROLES_DB_MAX_LIFETIME=1800000
```

**Query**:
```sql
SELECT role_name
FROM user_roles
WHERE username = ?
ORDER BY role_name
```

---

### 4. External Roles Database

**Container**: `roles-db` (PostgreSQL 16 Alpine)

**Schema**:
```sql
CREATE TABLE user_roles (
    id SERIAL PRIMARY KEY,
    username VARCHAR(255) NOT NULL,
    role_name VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_user_role UNIQUE (username, role_name)
);

CREATE INDEX idx_user_roles_username ON user_roles(username);
CREATE INDEX idx_user_roles_role_name ON user_roles(role_name);
```

**Test Data**:
```sql
INSERT INTO user_roles (username, role_name) VALUES
    ('alan.turing', 'DEVELOPER'),
    ('alan.turing', 'ARCHITECT'),
    ('alan.turing', 'ADMIN'),
    ('test.user', 'DEVELOPER'),
    ('test.user', 'TESTER'),
    ('john.doe', 'VIEWER');
```

**Access**:
- Internal: `roles-db:5432`
- External: `localhost:5433`

---

### 5. Keycloak Internal Database

**Container**: `keycloak-db` (PostgreSQL 16 Alpine)

**Purpose**: Stores Keycloak's internal data
- Realms
- Clients
- Users (in POC-04-A)
- Sessions
- Configurations

**Access**:
- Internal: `keycloak-db:5432`
- External: `localhost:5432`

---

## Data Flow Sequence

### Token Request Flow

```
1. Client → Keycloak: POST /realms/example-poc/protocol/openid-connect/token
   Body: {
     client_id: "spring-client",
     client_secret: "...",
     username: "alan.turing",
     password: "test123",
     grant_type: "password"
   }

2. Keycloak: Validate credentials
   - Query keycloak-db for user
   - Verify password hash
   - Create UserSessionModel

3. Keycloak: Generate base token
   - Standard claims: sub, iss, aud, exp, iat, etc.
   - User info: preferred_username, email, etc.

4. Keycloak: Invoke Protocol Mappers
   - Loop through registered mappers for client
   - Invoke ExternalRolesProtocolMapper.setClaim()

5. ExternalRolesProtocolMapper: Fetch roles
   - Extract username: "alan.turing"
   - Call RoleRepository.getRolesForUser("alan.turing")

6. RoleRepository: Query database
   - Get connection from HikariCP pool
   - Execute: SELECT role_name FROM user_roles WHERE username = 'alan.turing'
   - Return connection to pool
   - Return: ["ADMIN", "ARCHITECT", "DEVELOPER"]

7. ExternalRolesProtocolMapper: Add claim
   - token.getOtherClaims().put("external_roles", ["ADMIN", "ARCHITECT", "DEVELOPER"])

8. Keycloak: Sign token
   - Sign with RS256 (default)
   - Return JWT to client

9. Client: Receives token
   {
     "access_token": "eyJhbGc...",
     "refresh_token": "eyJhbGc...",
     "expires_in": 300,
     "token_type": "Bearer"
   }
```

---

## Build and Deployment Flow

### Build Process

```
1. Developer runs: ./build.sh start

2. Build Script:
   ├─ cd keycloak-roles-mapper
   ├─ mvn clean package
   │  ├─ Compile Java sources
   │  ├─ Maven Shade Plugin: Bundle dependencies (PostgreSQL driver, HikariCP)
   │  └─ Output: target/keycloak-roles-mapper.jar
   │
   ├─ Copy JAR to docker/keycloak/keycloak-roles-mapper.jar
   │
   ├─ docker-compose build keycloak
   │  ├─ Dockerfile: FROM quay.io/keycloak/keycloak:23.0.7
   │  ├─ COPY keycloak-roles-mapper.jar → /opt/keycloak/providers/
   │  └─ RUN /opt/keycloak/bin/kc.sh build (register provider)
   │
   └─ docker-compose up -d
      ├─ Start: roles-db
      ├─ Start: keycloak-db
      └─ Start: keycloak (depends on both DBs)
```

### Keycloak Provider Registration

When Keycloak starts:

```
1. Scan /opt/keycloak/providers/ directory
2. Load JARs and search for SPI descriptors
3. Read: META-INF/services/org.keycloak.protocol.ProtocolMapper
4. Find: com.example.keycloak.mapper.ExternalRolesProtocolMapper
5. Instantiate and register mapper
6. Make available in Admin Console under "Add mapper" → "By configuration"
```

---

## Technology Stack

### Java Backend
- **Java 17** (LTS)
- **Keycloak 23.0.7** (latest stable at POC creation)
- **HikariCP 5.1.0** (connection pooling)
- **PostgreSQL JDBC Driver 42.7.3**
- **SLF4J 2.0.12** (logging)

### Build Tools
- **Maven 3.9+**
- **Maven Shade Plugin 3.5.2** (fat JAR creation)

### Infrastructure
- **Docker** & **Docker Compose**
- **PostgreSQL 16 Alpine** (lightweight)

### Standards
- **OpenID Connect (OIDC)**
- **OAuth 2.0**
- **JWT (RFC 7519)**

---

## Security Considerations

### Current Implementation (POC)

⚠️ **For development/testing only!**

- Hardcoded credentials (`admin/admin`)
- Plain HTTP (no TLS)
- Shared database passwords
- No secrets management

### Production Recommendations

1. **Secrets Management**
   - Use Vault, AWS Secrets Manager, or similar
   - Never commit secrets to Git
   - Rotate credentials regularly

2. **Network Security**
   - Enable HTTPS/TLS for Keycloak
   - Use PostgreSQL SSL connections
   - Network isolation (private subnets)

3. **Database Access**
   - Read-only user for RoleRepository
   - Principle of least privilege
   - Connection encryption

4. **Monitoring**
   - Enable Keycloak metrics
   - Database query logging
   - Alert on connection pool exhaustion

5. **High Availability**
   - Cluster Keycloak (multiple instances)
   - Managed PostgreSQL (AWS RDS, etc.)
   - Load balancer with health checks

---

## Performance Characteristics

### HikariCP Connection Pool

**Configuration**:
- Max connections: 10
- Min idle: 2
- Connection timeout: 30s
- Idle timeout: 10m
- Max lifetime: 30m

**Expected Performance**:
- Query latency: <5ms (local network)
- Token generation overhead: <10ms
- Concurrent users: 100+ (with default pool)

**Bottlenecks**:
- Database query time (optimize with proper indexes)
- Network latency (Keycloak ↔ roles-db)
- Pool exhaustion (increase `ROLES_DB_POOL_SIZE` if needed)

---

## Extensibility

### Future Enhancements (POC-04-B)

1. **User Storage SPI**
   - Roles visible in Keycloak Admin Console
   - Support role assignments via UI
   - Cache roles for performance

2. **SAML Integration**
   - Replace native users with SAML federation
   - FortiAuthenticator as IdP
   - User attributes from LDAP

3. **Role Hierarchies**
   - Parent-child role relationships
   - Inherited permissions

4. **Dynamic Configuration**
   - Configure DB connection via Admin Console
   - Multiple role sources (LDAP, REST API, etc.)

---

## Testing Strategy

### Unit Tests (TODO)

```java
@Test
void testRoleRepositoryReturnsRoles() {
    List<String> roles = RoleRepository.getRolesForUser("alan.turing");
    assertThat(roles).containsExactly("ADMIN", "ARCHITECT", "DEVELOPER");
}

@Test
void testMapperAddsClaimToToken() {
    // Mock UserSessionModel, KeycloakSession
    // Invoke setClaim()
    // Assert token.getOtherClaims().containsKey("external_roles")
}
```

### Integration Tests

```bash
# 1. Start full stack
./build.sh start

# 2. Configure Keycloak (manual or Terraform)

# 3. Run token test
./test-token.sh <CLIENT_SECRET>

# 4. Verify JWT contains external_roles
```

### Load Testing (TODO)

```bash
# JMeter scenario:
# - 100 concurrent users
# - Each obtains token every 5 minutes
# - Monitor: HikariCP pool usage, query latency, token generation time
```

---

## Troubleshooting Guide

See [README.md](README.md#troubleshooting) for detailed troubleshooting steps.

**Quick diagnostics**:

```bash
# Check all services are healthy
docker-compose ps

# View logs
docker-compose logs -f keycloak | grep -i "external\|hikari\|role"

# Test database connectivity
docker-compose exec roles-db psql -U keycloak -d roles -c "SELECT * FROM user_roles;"

# Verify JAR is present
docker-compose exec keycloak ls -lh /opt/keycloak/providers/

# Check provider registration
docker-compose logs keycloak | grep -i "protocol.*mapper"
```

---

## References

- [Keycloak Server Development Guide](https://www.keycloak.org/docs/latest/server_development/)
- [Protocol Mapper SPI](https://www.keycloak.org/docs-api/23.0.7/javadocs/org/keycloak/protocol/oidc/mappers/package-summary.html)
- [HikariCP Documentation](https://github.com/brettwooldridge/HikariCP)
- [OpenID Connect Core 1.0](https://openid.net/specs/openid-connect-core-1_0.html)

---

**Architecture complete!** For step-by-step usage, see [QUICKSTART.md](QUICKSTART.md).
