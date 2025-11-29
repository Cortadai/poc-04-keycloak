# POC-04-B: Keycloak SAML2 Federation + External Roles

Proof of Concept que demuestra:
1. **Federación SAML2**: Keycloak SP recibe usuarios desde Keycloak IdP via SAML
2. **Roles externos**: Custom Protocol Mapper consulta PostgreSQL para añadir roles al JWT

## Arquitectura

```
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│  ┌─────────────────┐       SAML2        ┌─────────────────┐            │
│  │  Keycloak IdP   │  ───────────────►  │  Keycloak SP    │            │
│  │  (puerto 8180)  │     Assertion      │  (puerto 8080)  │            │
│  │                 │                    │                 │            │
│  │  Usuarios:      │                    │  + JAR Custom   │            │
│  │  - alan.turing  │                    │                 │            │
│  │  - test.user    │                    └────────┬────────┘            │
│  └────────┬────────┘                             │                     │
│           │                                      │ JDBC                │
│           ▼                                      ▼                     │
│  ┌─────────────────┐                    ┌─────────────────┐            │
│  │ keycloak-idp-db │                    │    roles-db     │            │
│  │   (PostgreSQL)  │                    │  (PostgreSQL)   │            │
│  │   Puerto: 5434  │                    │  Puerto: 5433   │            │
│  └─────────────────┘                    │                 │            │
│                                         │  alan.turing:   │            │
│                                         │  - ADMIN        │            │
│                                         │  - ARCHITECT    │            │
│                                         │  - DEVELOPER    │            │
│                                         └─────────────────┘            │
└─────────────────────────────────────────────────────────────────────────┘
```

## Servicios y Puertos

| Servicio | Puerto | Descripción |
|----------|--------|-------------|
| keycloak-idp | 8180 | Identity Provider (usuarios nativos) |
| keycloak-sp | 8080 | Service Provider (usuarios federados + JAR custom) |
| keycloak-idp-db | 5434 | PostgreSQL para Keycloak IdP |
| keycloak-sp-db | 5432 | PostgreSQL para Keycloak SP |
| roles-db | 5433 | PostgreSQL con roles externos |

## Quick Start

### 1. Build y arranque

```bash
./build.sh --start
```

O manualmente:
```bash
cd keycloak-roles-mapper && mvn clean package && cd ..
docker-compose up -d --build
```

### 2. Esperar a que los servicios estén healthy (~2 min)

```bash
docker-compose ps
```

Todos los contenedores deben mostrar "healthy".

---

## Configuración

### Paso 1: Configurar Keycloak IdP (puerto 8180)

Acceder a http://localhost:8180 con `admin/admin`

#### 1.1 Crear Realm
- Click en el dropdown "master" → **Create realm**
- Realm name: `idp-realm`
- Click **Create**

#### 1.2 Crear Usuarios
- **Users** → **Add user**
- Username: `alan.turing`
- Email: `alan.turing@example.com`
- First Name: `Alan`
- Last Name: `Turing`
- **Email verified**: ON
- Click **Create**
- Pestaña **Credentials** → **Set password**
  - Password: `test123`
  - Temporary: **OFF**
  - Click **Save**

(Opcional: repetir para `test.user`)

#### 1.3 Crear Client SAML para el SP
- **Clients** → **Create client**
- Client type: `SAML`
- Client ID: `http://localhost:8080/realms/sp-realm`
- Click **Next** → **Save**

Configurar el client:
- **Settings**:
  - Root URL: `http://localhost:8080/realms/sp-realm`
  - Valid redirect URIs: `http://localhost:8080/realms/sp-realm/broker/forti-simulator/endpoint/*`
  - Name ID Format: `username`
  - Force Name ID Format: **ON**
- **Keys**:
  - Client signature required: **OFF**
- Click **Save**

---

### Paso 2: Configurar Keycloak SP (puerto 8080)

Acceder a http://localhost:8080 con `admin/admin`

#### 2.1 Crear Realm
- Click en el dropdown "master" → **Create realm**
- Realm name: `sp-realm`
- Click **Create**

#### 2.2 Configurar Identity Provider SAML
- **Identity Providers** → **Add provider** → **SAML v2.0**
- Alias: `forti-simulator`
- Display name: `Login con FortiAuth (Simulado)`
- **SAML entity descriptor**: `http://keycloak-idp:8080/realms/idp-realm/protocol/saml/descriptor`
  - (Esperar a que aparezca el check verde)

Verificar que las URLs importadas muestren `localhost:8180` (NO `keycloak-idp:8080`):
- Identity provider entity ID: `http://localhost:8180/realms/idp-realm`
- Single Sign-On service URL: `http://localhost:8180/realms/idp-realm/protocol/saml`

Configurar opciones de firma:
- **Want AuthnRequests signed**: **OFF**
- **Validate Signatures**: **OFF**

Click **Add**

#### 2.3 Crear Client OpenID Connect
- **Clients** → **Create client**
- Client type: `OpenID Connect`
- Client ID: `spring-client`
- Click **Next**
- Client authentication: **ON**
- Click **Next**
- Valid redirect URIs: `*`
- Web origins: `*`
- Click **Save**

**Copiar el Client Secret**:
- Pestaña **Credentials** → Copiar el **Client secret** (lo necesitarás para probar)

#### 2.4 Añadir Protocol Mapper Custom
- **Clients** → **spring-client** → Pestaña **Client scopes**
- Click en **spring-client-dedicated**
- **Add mapper** → **By configuration** → **External Database Roles Mapper**
- Name: `external-roles-mapper`
- Token Claim Name: `external_roles`
- Add to ID token: **ON**
- Add to access token: **ON**
- Add to userinfo: **ON**
- Click **Save**

---

## Probar el Flujo

### Opción A: Test Manual (Navegador)

#### 1. Iniciar el flujo de autenticación

Abrir en el navegador:
```
http://localhost:8080/realms/sp-realm/protocol/openid-connect/auth?client_id=spring-client&response_type=code&redirect_uri=http://localhost:8080/&scope=openid
```

#### 2. Click en "Login con FortiAuth (Simulado)"

#### 3. Introducir credenciales en el IdP
- Username: `alan.turing`
- Password: `test123`

#### 4. Completar "Update Account Information" (primera vez)
- Rellenar campos requeridos
- Click **Submit**

#### 5. Copiar el code de la URL
Serás redirigido a:
```
http://localhost:8080/?code=XXXXX...&session_state=...
```

#### 6. Intercambiar code por token
```bash
curl -X POST "http://localhost:8080/realms/sp-realm/protocol/openid-connect/token" \
  -d "client_id=spring-client" \
  -d "client_secret=<TU_CLIENT_SECRET>" \
  -d "grant_type=authorization_code" \
  -d "code=<EL_CODE_DE_LA_URL>" \
  -d "redirect_uri=http://localhost:8080/"
```

#### 7. Verificar el token
Decodificar el `access_token` en https://jwt.io

Debe contener:
```json
{
  "external_roles": ["ADMIN", "ARCHITECT", "DEVELOPER"],
  "preferred_username": "alan.turing",
  ...
}
```

### Opción B: Test con Script

```bash
./test-flow.sh <CLIENT_SECRET>
```

---

## Troubleshooting

### Error: "Invalid requester" o "Invalid signature" en IdP

**Causa**: El IdP está verificando firmas del SP.

**Solución**: En el IdP, editar el client SAML → Keys → **Client signature required: OFF**

### Error: "IDENTITY_PROVIDER_RESPONSE_ERROR invalid_signature" en SP

**Causa**: El SP no puede verificar la firma del IdP (certificados no coinciden).

**Solución**: En el SP, editar Identity Provider → **Validate Signatures: OFF**

### Las URLs del metadata muestran "keycloak-idp:8080" en vez de "localhost:8180"

**Causa**: El IdP no tiene configurado el hostname correctamente.

**Solución**: Verificar que docker-compose.yml tiene estas variables en keycloak-idp:
```yaml
KC_HOSTNAME: localhost
KC_HOSTNAME_PORT: "8180"
KC_HOSTNAME_STRICT_HTTPS: "false"
```

Luego: `docker-compose up -d --build keycloak-idp`

### El mapper no encuentra roles (external_roles vacío)

Verificar datos en la base de datos:
```bash
docker-compose exec roles-db psql -U keycloak -d roles -c "SELECT * FROM user_roles WHERE username = 'alan.turing';"
```

### Ver logs

```bash
# Logs del IdP
docker-compose logs -f keycloak-idp

# Logs del SP
docker-compose logs -f keycloak-sp

# Filtrar errores
docker-compose logs keycloak-sp 2>&1 | grep -i error
```

---

## Datos de Prueba

La base de datos `roles-db` viene precargada con:

| Username | Roles |
|----------|-------|
| alan.turing | ADMIN, ARCHITECT, DEVELOPER |
| test.user | DEVELOPER, TESTER |
| john.doe | VIEWER |

---

## Limpieza

```bash
# Parar todo
docker-compose down

# Parar y eliminar volúmenes (reset completo)
docker-compose down -v
```

---

## Estructura del Proyecto

```
keycloak-experiment/
├── docker-compose.yml          # Definición de servicios
├── build.sh                    # Script de build
├── docker/
│   ├── keycloak-idp/          # Dockerfile IdP (vanilla)
│   └── keycloak-sp/           # Dockerfile SP (con JAR custom)
├── keycloak-roles-mapper/     # Código del Protocol Mapper
│   └── src/main/java/com/example/keycloak/mapper/
│       ├── ExternalRolesProtocolMapper.java
│       └── RoleRepository.java
└── init-db/                   # Scripts inicialización PostgreSQL
    └── 01-schema.sql
```
