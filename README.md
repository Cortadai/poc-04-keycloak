# POC-04-A: Keycloak Custom Roles Provider

**Custom Protocol Mapper for Keycloak that fetches user roles from an external PostgreSQL database and injects them into JWT tokens.**

---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Keycloak Configuration](#keycloak-configuration)
- [Testing the Implementation](#testing-the-implementation)
- [Troubleshooting](#troubleshooting)
- [Advanced Configuration](#advanced-configuration)
- [Next Steps](#next-steps)

---

## 🎯 Overview

### Context and Motivation

This POC replicates the real-world scenario where:
- Keycloak obtains users from **FortiAuthenticator via SAML2** (which pulls from LDAP)
- Roles come from an **external database via custom JAR**

**Goal**: Gain deep understanding and confidence in this architectural pattern by implementing a simplified version first.

### Design Decision

Split into two progressive POCs instead of tackling everything at once:

**POC-04-A** (this project):
- Keycloak with **native users** (no SAML yet)
- Custom JAR queries roles from **PostgreSQL external database**
- Simple approach: 1-2 Java classes
- Objective: Master Keycloak's extension mechanism

**POC-04-B** (future):
- Full User Storage SPI implementation
- Roles visible in Keycloak Admin Console
- More classes, deeper Keycloak integration

### Success Criteria

✅ Login with `alan.turing` → JWT contains claim:
```json
{
  "external_roles": ["DEVELOPER", "ARCHITECT", "ADMIN"]
}
```

These roles are fetched from PostgreSQL, **not** from Keycloak's internal database.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        User Login                            │
│                  (alan.turing / test123)                 │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                      Keycloak                                │
│  - Native users (no SAML in POC-04-A)                       │
│  - Realm: example-poc                                          │
│  - Client: spring-client                                     │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           │ Token generation triggers mapper
                           ▼
┌─────────────────────────────────────────────────────────────┐
│       Custom Protocol Mapper (JAR)                           │
│  ExternalRolesProtocolMapper.java                            │
│  - Invoked during token creation                             │
│  - Extracts username from UserSessionModel                   │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           │ JDBC query via HikariCP
                           ▼
┌─────────────────────────────────────────────────────────────┐
│       External PostgreSQL Database                           │
│  Container: roles-db                                         │
│  Table: user_roles (username, role_name)                     │
│  Query: SELECT role_name WHERE username = ?                  │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           │ Returns: ["DEVELOPER", "ARCHITECT", "ADMIN"]
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    JWT Token                                 │
│  {                                                           │
│    "sub": "alan.turing",                                 │
│    "external_roles": ["DEVELOPER", "ARCHITECT", "ADMIN"],    │
│    ...                                                       │
│  }                                                           │
└─────────────────────────────────────────────────────────────┘
```

### Components

1. **keycloak-roles-mapper** (Maven module)
   - `ExternalRolesProtocolMapper`: Keycloak SPI implementation
   - `RoleRepository`: JDBC access layer with HikariCP
   - SPI descriptor: Registers the mapper with Keycloak

2. **roles-db** (PostgreSQL container)
   - Stores user-role mappings
   - Initialized with test data via `init-db/01-schema.sql`

3. **keycloak-db** (PostgreSQL container)
   - Keycloak's internal database (realms, users, clients, etc.)

4. **keycloak** (Custom Docker image)
   - Based on `quay.io/keycloak/keycloak:23.0.7`
   - Includes the custom mapper JAR in `/opt/keycloak/providers/`

---

## 📁 Project Structure

```
keycloak-experiment/
├── pom.xml                              # Parent POM (multi-module)
├── build.sh / build.bat                 # Build scripts (Linux/Windows)
├── docker-compose.yml                   # Orchestrates 3 containers
│
├── keycloak-roles-mapper/               # Maven module: Custom mapper
│   ├── pom.xml                          # Dependencies: Keycloak SPI, PostgreSQL, HikariCP
│   └── src/main/
│       ├── java/com/example/keycloak/mapper/
│       │   ├── ExternalRolesProtocolMapper.java    # Main mapper logic
│       │   └── RoleRepository.java                 # Database access
│       └── resources/META-INF/services/
│           └── org.keycloak.protocol.ProtocolMapper  # SPI registration
│
├── spring-client/                       # Maven module: Optional test client
│   ├── pom.xml
│   └── src/main/java/com/example/
│       └── KeycloakExperimentApplication.java
│
├── docker/
│   └── keycloak/
│       ├── Dockerfile                   # Keycloak + custom provider
│       └── keycloak-roles-mapper.jar    # Copied here by build script
│
└── init-db/
    └── 01-schema.sql                    # PostgreSQL schema + test data
```

---

## 🔧 Prerequisites

- **Java 17** or higher
- **Maven 3.8+** (or use included Maven wrapper: `./mvnw`)
- **Docker** and **Docker Compose**
- **curl** (for testing) or **Postman**
- **Optional**: Database client (DBeaver, pgAdmin) for inspecting databases

---

## 🚀 Quick Start

### 1. Build the Project

#### On Linux/Mac:
```bash
chmod +x build.sh
./build.sh start
```

#### On Windows:
```cmd
build.bat start
```

This will:
1. Compile the custom mapper JAR
2. Copy it to the Docker context
3. Build the Keycloak Docker image with the provider
4. Start all containers (roles-db, keycloak-db, keycloak)

### 2. Wait for Keycloak to Start

Monitor the logs:
```bash
docker-compose logs -f keycloak
```

Wait for:
```
Keycloak 23.0.7 started
Listening on: http://0.0.0.0:8080
```

### 3. Access Keycloak Admin Console

Open: **http://localhost:8080**

Login:
- **Username**: `admin`
- **Password**: `admin`

---

## ⚙️ Keycloak Configuration

### Step 1: Create Realm

1. In Admin Console, hover over "Master" (top-left) → **Create Realm**
2. **Realm name**: `example-poc`
3. Click **Create**

### Step 2: Create Client

1. Navigate to **Clients** → **Create client**
2. **Client ID**: `spring-client`
3. **Client type**: `OpenID Connect`
4. Click **Next**
5. **Client authentication**: `ON` (confidential)
6. **Authorization**: `OFF`
7. **Authentication flow**: Enable:
   - ✅ Standard flow
   - ✅ Direct access grants (for testing with password grant)
8. Click **Save**

### Step 3: Note Client Secret

1. Go to **Clients** → `spring-client` → **Credentials** tab
2. Copy the **Client secret** (you'll need this for testing)

### Step 4: Create User

1. Navigate to **Users** → **Add user**
2. **Username**: `alan.turing`
3. **Email**: `alan.turing@example.com` (optional)
4. **Email verified**: `ON`
5. Click **Create**
6. Go to **Credentials** tab
7. Click **Set password**
8. **Password**: `test123`
9. **Temporary**: `OFF`
10. Click **Save**

### Step 5: Add Custom Protocol Mapper

1. Go to **Clients** → `spring-client` → **Client scopes** tab
2. Click on `spring-client-dedicated` (the dedicated scope)
3. Click **Add mapper** → **By configuration**
4. Select **External Database Roles Mapper** (this is your custom mapper!)
5. Configuration (default values are fine):
   - **Name**: `external-roles-mapper`
   - **Add to ID token**: `ON`
   - **Add to access token**: `ON`
   - **Add to userinfo**: `ON`
6. Click **Save**

---

## 🧪 Testing the Implementation

### Method 1: Get Token via curl

```bash
curl -X POST "http://localhost:8080/realms/example-poc/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=spring-client" \
  -d "client_secret=YOUR_CLIENT_SECRET_HERE" \
  -d "username=alan.turing" \
  -d "password=test123" \
  -d "grant_type=password"
```

**Replace** `YOUR_CLIENT_SECRET_HERE` with the secret from Step 3 above.

### Method 2: Get Token via Postman

1. **POST** `http://localhost:8080/realms/example-poc/protocol/openid-connect/token`
2. **Body**: `x-www-form-urlencoded`
   - `client_id`: `spring-client`
   - `client_secret`: `<YOUR_SECRET>`
   - `username`: `alan.turing`
   - `password`: `test123`
   - `grant_type`: `password`
3. Send request

### Method 3: Decode and Verify JWT

1. Copy the `access_token` from the response
2. Go to **https://jwt.io**
3. Paste the token
4. Verify the payload contains:

```json
{
  "exp": 1234567890,
  "iat": 1234567890,
  "sub": "abc123-def456...",
  "preferred_username": "alan.turing",
  "external_roles": [
    "ADMIN",
    "ARCHITECT",
    "DEVELOPER"
  ]
}
```

✅ **Success!** The `external_roles` claim proves the mapper is working.

---

## 🔍 Troubleshooting

### Issue: Mapper doesn't appear in Keycloak Admin Console

**Symptoms**: "External Database Roles Mapper" not listed when adding mapper.

**Solutions**:
1. Check JAR was built and copied:
   ```bash
   ls -lh docker/keycloak/keycloak-roles-mapper.jar
   ```
2. Rebuild Keycloak image:
   ```bash
   docker-compose down
   ./build.sh docker
   docker-compose up -d
   ```
3. Check Keycloak logs for provider registration:
   ```bash
   docker-compose logs keycloak | grep -i "external.*role"
   ```

### Issue: JWT doesn't contain `external_roles` claim

**Symptoms**: Token is valid but missing the custom claim.

**Solutions**:
1. Verify mapper is configured in client scope:
   - Clients → spring-client → Client scopes → spring-client-dedicated
   - Should see "external-roles-mapper" in the list
2. Check mapper is enabled for access token:
   - Edit mapper → "Add to access token" = ON
3. Check database connectivity:
   ```bash
   docker-compose logs keycloak | grep -i "hikaricp"
   docker-compose logs keycloak | grep -i "roles"
   ```

### Issue: Empty `external_roles` array

**Symptoms**: Claim exists but `external_roles: []`

**Possible causes**:
1. Username doesn't exist in roles database:
   ```bash
   docker-compose exec roles-db psql -U keycloak -d roles -c "SELECT * FROM user_roles WHERE username = 'alan.turing';"
   ```
2. Database connection error (check logs)
3. Username case mismatch (PostgreSQL is case-sensitive)

### Issue: Database connection timeout

**Symptoms**: Logs show "Connection timeout" or "SQLException"

**Solutions**:
1. Verify roles-db is healthy:
   ```bash
   docker-compose ps
   docker-compose logs roles-db
   ```
2. Check environment variables:
   ```bash
   docker-compose exec keycloak env | grep ROLES_DB
   ```
3. Test database connectivity from Keycloak container:
   ```bash
   docker-compose exec keycloak bash
   apt update && apt install -y postgresql-client
   psql -h roles-db -U keycloak -d roles -c "SELECT 1"
   ```

---

## 🔧 Advanced Configuration

### Environment Variables for Roles Database

You can customize the database connection in `docker-compose.yml`:

```yaml
environment:
  ROLES_DB_URL: jdbc:postgresql://roles-db:5432/roles
  ROLES_DB_USER: keycloak
  ROLES_DB_PASSWORD: keycloak
  ROLES_DB_POOL_SIZE: 10           # HikariCP max pool size
  ROLES_DB_MIN_IDLE: 2             # HikariCP min idle connections
  ROLES_DB_CONN_TIMEOUT: 30000     # Connection timeout (ms)
  ROLES_DB_IDLE_TIMEOUT: 600000    # Idle timeout (ms)
  ROLES_DB_MAX_LIFETIME: 1800000   # Max connection lifetime (ms)
```

### Custom Logging

Enable debug logging for the mapper:

```yaml
environment:
  QUARKUS_LOG_CATEGORY__COM_EXAMPLE_KEYCLOAK__LEVEL: debug
```

View detailed logs:
```bash
docker-compose logs -f keycloak | grep "com.example.keycloak"
```

### Persistent vs Ephemeral Data

**Current setup**: Persistent (data survives `docker-compose down`)

**To make ephemeral** (useful for testing):
```yaml
volumes:
  roles-db-data:
    # Comment out or remove this volume
```

Then restart:
```bash
docker-compose down -v  # -v removes volumes
docker-compose up -d
```

---

## 🎯 Next Steps

### Immediate Enhancements (within POC-04-A)

1. **Add more test users**:
   - Edit `init-db/01-schema.sql`
   - Add INSERT statements
   - Rebuild: `docker-compose down -v && ./build.sh start`

2. **Implement JWT validation in Spring Client**:
   - Add Spring Security + OAuth2 Resource Server
   - Validate JWT signature
   - Extract and use `external_roles` for authorization

3. **Add health check endpoint**:
   - Verify database connectivity from mapper
   - Expose via custom REST endpoint in Keycloak

### POC-04-B: User Storage SPI

Evolve to full User Storage SPI implementation:
- Roles visible in Keycloak Admin Console
- Support for role assignments via Admin UI
- Integration with Keycloak's role model
- Caching and performance optimization

---

## 📚 Resources

- [Keycloak Documentation](https://www.keycloak.org/docs/latest/)
- [Keycloak SPI Development Guide](https://www.keycloak.org/docs/latest/server_development/)
- [HikariCP GitHub](https://github.com/brettwooldridge/HikariCP)
- [JWT.io Debugger](https://jwt.io/)
