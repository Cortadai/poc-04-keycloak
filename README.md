# POC-04-B: Keycloak SAML2 Federation with External Roles

Proof of Concept que demuestra:
1. **Federación SAML2**: Keycloak SP recibe usuarios desde Keycloak IdP via SAML
2. **Roles externos**: Custom Protocol Mapper consulta PostgreSQL para añadir roles al JWT

## Arquitectura

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  ┌─────────────────┐         SAML2          ┌─────────────────┐            │
│  │                 │       Assertion        │                 │            │
│  │  Keycloak IdP   │ ──────────────────────▶│  Keycloak SP    │            │
│  │  (puerto 8180)  │                        │  (puerto 8080)  │            │
│  │                 │                        │                 │            │
│  │  Usuarios:      │                        │  Sin usuarios   │            │
│  │  - alan.turing  │                        │  locales        │            │
│  │  - test.user    │                        │                 │            │
│  └────────┬────────┘                        └────────┬────────┘            │
│           │                                          │                      │
│           │                                          │ JDBC                 │
│           ▼                                          ▼                      │
│  ┌─────────────────┐                        ┌─────────────────┐            │
│  │ keycloak-idp-db │                        │    roles-db     │            │
│  │   (PostgreSQL)  │                        │  (PostgreSQL)   │            │
│  └─────────────────┘                        │                 │            │
│                                             │  user_roles:    │            │
│                                             │  alan.turing →  │            │
│                                             │    DEVELOPER    │            │
│                                             │    ARCHITECT    │            │
│                                             │    ADMIN        │            │
│                                             └─────────────────┘            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Flujo de Autenticación

```
1. Usuario accede a app protegida por Keycloak SP
2. SP no tiene sesión → muestra login con botón "forti-simulator"
3. Click → redirección a Keycloak IdP (8180)
4. Usuario introduce credenciales en IdP
5. IdP genera SAML assertion con username
6. Redirección de vuelta a SP con la assertion
7. SP valida assertion y crea usuario federado
8. Custom Protocol Mapper consulta PostgreSQL
9. JWT generado con claim "external_roles"
```

## Quick Start

### 1. Build y arranque

```bash
# Compilar JAR y arrancar todo
./build.sh --start

# O paso a paso:
cd keycloak-roles-mapper && mvn clean package && cd ..
docker-compose up -d --build
```

### 2. Esperar a que los servicios estén healthy

```bash
docker-compose ps
docker-compose logs -f
```

### 3. Configurar Keycloak IdP (puerto 8180)

Acceder a http://localhost:8180 con admin/admin

#### 3.1 Crear Realm
- Crear nuevo realm: `idp-realm`

#### 3.2 Crear Usuarios
- Users → Add user
- Username: `alan.turing`
- Email: `alan.turing@example.com`
- First Name: `Alan`
- Last Name: `Turing`
- Enabled: ON
- Credentials → Set password: `test123` (Temporary: OFF)

Repetir para `test.user` con password `test123`

#### 3.3 Crear Client SAML para el SP
- Clients → Create client
- Client type: `SAML`
- Client ID: `http://localhost:8080/realms/sp-realm`
- Name: `Keycloak SP`
- Save

Configurar el client:
- Settings:
  - Root URL: `http://localhost:8080/realms/sp-realm`
  - Valid redirect URIs: `http://localhost:8080/realms/sp-realm/broker/forti-simulator/endpoint/*`
  - Master SAML Processing URL: `http://localhost:8080/realms/sp-realm/broker/forti-simulator/endpoint`
  - Name ID Format: `username`
  - Force Name ID Format: ON
- Keys:
  - Client signature required: OFF (para simplificar la POC)

#### 3.4 Copiar URL de metadata del IdP
- Realm Settings → General → Endpoints → SAML 2.0 Identity Provider Metadata
- Copiar URL: `http://localhost:8180/realms/idp-realm/protocol/saml/descriptor`

### 4. Configurar Keycloak SP (puerto 8080)

Acceder a http://localhost:8080 con admin/admin

#### 4.1 Crear Realm
- Crear nuevo realm: `sp-realm`

#### 4.2 Configurar Identity Provider SAML
- Identity Providers → Add provider → SAML v2.0
- Alias: `forti-simulator`
- Display name: `Login con FortiAuth (Simulado)`
- Import from URL: pegar la URL de metadata del IdP
  - NOTA: Cambiar `localhost` por `keycloak-idp` en la URL para red Docker:
  - `http://keycloak-idp:8080/realms/idp-realm/protocol/saml/descriptor`
- Save

Configurar el Identity Provider:
- Settings:
  - Service provider entity ID: `http://localhost:8080/realms/sp-realm`
  - Single Sign-On Service URL: `http://keycloak-idp:8080/realms/idp-realm/protocol/saml`
  - Principal Type: `Subject NameID`
  - Principal Attribute: (dejar vacío)
  - First Login Flow: `first broker login`

#### 4.3 Crear Client para aplicación
- Clients → Create client
- Client type: `OpenID Connect`
- Client ID: `spring-client`
- Client authentication: ON
- Authorization: OFF
- Save

Configurar:
- Valid redirect URIs: `*`
- Web origins: `*`
- Copiar el Client Secret de la pestaña Credentials

#### 4.4 Añadir Protocol Mapper custom
- Clients → spring-client → Client scopes → spring-client-dedicated
- Add mapper → By configuration → External Database Roles Mapper
- Name: `external-roles-mapper`
- Token Claim Name: `external_roles`
- Add to ID token: ON
- Add to access token: ON
- Add to userinfo: ON
- Save

### 5. Probar el flujo SAML

#### Opción A: Navegador (Authorization Code Flow)

1. Abrir en navegador:
```
http://localhost:8080/realms/sp-realm/protocol/openid-connect/auth?client_id=spring-client&response_type=code&redirect_uri=http://localhost:8080/&scope=openid
```

2. Click en "forti-simulator"
3. Introducir credenciales en IdP (alan.turing / test123)
4. Serás redirigido con un code en la URL
5. Intercambiar code por token:

```bash
CODE="<el_code_de_la_url>"
CLIENT_SECRET="<tu_client_secret>"

curl -X POST http://localhost:8080/realms/sp-realm/protocol/openid-connect/token \
  -d "client_id=spring-client" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "grant_type=authorization_code" \
  -d "code=$CODE" \
  -d "redirect_uri=http://localhost:8080/"
```

#### Opción B: Direct Grant (solo testing)

Esto NO funcionará hasta que el usuario haya iniciado sesión al menos una vez via SAML (para crear el usuario federado en el SP).

### 6. Verificar resultado

Decodificar el access_token en https://jwt.io

Debe contener:
```json
{
  "external_roles": ["ADMIN", "ARCHITECT", "DEVELOPER"],
  "preferred_username": "alan.turing",
  ...
}
```

## Verificar usuario federado

En Keycloak SP Admin Console:
- Users → View all users
- Debe aparecer `alan.turing` con:
  - Federation link: `forti-simulator`
  - Sin password local

## Troubleshooting

### Ver logs de ambos Keycloaks
```bash
docker-compose logs -f keycloak-idp keycloak-sp
```

### Verificar datos en roles-db
```bash
docker-compose exec roles-db psql -U keycloak -d roles -c "SELECT * FROM user_roles;"
```

### El mapper no encuentra roles
- Verificar que el username en SAML assertion coincide exactamente con user_roles.username
- Revisar logs del SP: `docker-compose logs keycloak-sp | grep -i external`

### Error de conexión SAML entre IdP y SP
- Los contenedores se comunican por nombre de servicio (`keycloak-idp`, `keycloak-sp`)
- Las URLs de metadata/endpoints deben usar estos nombres internos
- Las URLs del navegador usan `localhost:8180` y `localhost:8080`

## Servicios y Puertos

| Servicio | Puerto | Descripción |
|----------|--------|-------------|
| keycloak-idp | 8180 | Identity Provider (usuarios nativos) |
| keycloak-sp | 8080 | Service Provider (usuarios federados + JAR) |
| roles-db | 5433 | PostgreSQL con roles externos |
| keycloak-idp-db | 5434 | PostgreSQL para Keycloak IdP |
| keycloak-sp-db | 5432 | PostgreSQL para Keycloak SP |

## Limpieza

```bash
# Parar todo y eliminar volúmenes
docker-compose down -v

# O usar el script
./build.sh --clean
```
