# 🚀 Quick Start Guide - POC-04-A

**Get up and running in 5 minutes!**

---

## Prerequisites Check

```bash
# Verify installations
java -version          # Should be 17+
mvn -version           # Should be 3.8+
docker --version       # Any recent version
docker-compose version # V2 preferred
```

---

## 1. Build and Start (1 command)

### Linux/Mac:
```bash
./build.sh start
```

### Windows:
```cmd
build.bat start
```

**Wait for**: "Keycloak 23.0.7 started" in logs
```bash
docker-compose logs -f keycloak
```

---

## 2. Configure Keycloak (5 minutes)

### Open Admin Console
**URL**: http://localhost:8080
**Login**: `admin` / `admin`

### Create Realm
1. Click **"Master"** dropdown (top-left) → **Create Realm**
2. Name: `example-poc`
3. Click **Create**

### Create Client
1. **Clients** → **Create client**
2. Client ID: `spring-client`
3. **Next**
4. Client authentication: **ON**
5. Direct access grants: **✓**
6. **Save**
7. Go to **Credentials** tab → Copy **Client secret** (save it!)

### Create User
1. **Users** → **Add user**
2. Username: `alan.turing`
3. Email verified: **ON**
4. **Create**
5. **Credentials** tab → **Set password**
6. Password: `test123`
7. Temporary: **OFF**
8. **Save**

### Add Custom Mapper
1. **Clients** → `spring-client` → **Client scopes** tab
2. Click `spring-client-dedicated`
3. **Add mapper** → **By configuration**
4. Select **"External Database Roles Mapper"** ✨
5. Name: `external-roles-mapper`
6. All toggles: **ON**
7. **Save**

---

## 3. Test It! (30 seconds)

### Get Token
```bash
# Replace YOUR_SECRET with the client secret from step 2
curl -X POST "http://localhost:8080/realms/example-poc/protocol/openid-connect/token" \
  -d "client_id=spring-client" \
  -d "client_secret=YOUR_SECRET" \
  -d "username=alan.turing" \
  -d "password=test123" \
  -d "grant_type=password"
```

### Or Use the Test Script
```bash
./test-token.sh YOUR_SECRET
```

### Verify JWT
1. Copy the `access_token` from response
2. Go to **https://jwt.io**
3. Paste token
4. Look for:
```json
{
  "external_roles": [
    "ADMIN",
    "ARCHITECT",
    "DEVELOPER"
  ]
}
```

---

## ✅ Success Criteria

**You should see**:
- ✅ Token obtained successfully
- ✅ `external_roles` claim present in JWT
- ✅ Roles: `["ADMIN", "ARCHITECT", "DEVELOPER"]`

**If not**, see [README.md](README.md#troubleshooting) troubleshooting section.

---

## 🧪 What's Happening?

```
User Login
    ↓
Keycloak authenticates (native user)
    ↓
Custom Protocol Mapper triggered
    ↓
Query: SELECT role_name FROM user_roles WHERE username = 'alan.turing'
    ↓
PostgreSQL returns: ["ADMIN", "ARCHITECT", "DEVELOPER"]
    ↓
Mapper adds "external_roles" claim to JWT
    ↓
Token issued with external roles! 🎉
```

---

## 📊 Inspect the Database

### View User Roles
```bash
docker-compose exec roles-db psql -U keycloak -d roles -c "SELECT * FROM user_roles;"
```

### Add a New Role
```bash
docker-compose exec roles-db psql -U keycloak -d roles -c \
  "INSERT INTO user_roles (username, role_name) VALUES ('alan.turing', 'SUPERUSER');"
```

**Then get a new token** and verify the new role appears!

---

## 🛑 Stop Everything

```bash
docker-compose down       # Stop containers (data persists)
docker-compose down -v    # Stop + remove data
```

---

## 🔍 Debug Commands

```bash
# View all logs
docker-compose logs -f

# View only Keycloak logs
docker-compose logs -f keycloak

# View only roles database logs
docker-compose logs -f roles-db

# Check container health
docker-compose ps

# Access Keycloak shell
docker-compose exec keycloak bash

# Access database
docker-compose exec roles-db psql -U keycloak -d roles
```

---

## 📚 Next Steps

- Read full [README.md](README.md) for deep dive
- Customize roles in `init-db/01-schema.sql`
- Build a Spring Boot client to validate JWTs
- Explore POC-04-B (User Storage SPI)

---

**Questions?** Check the [README.md](README.md) troubleshooting section!

**Happy Keycloaking!** 🔑🚀
