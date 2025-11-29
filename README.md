# POC-04-A: Keycloak Custom Roles Provider

**Protocol Mapper personalizado para Keycloak que obtiene roles de usuario desde una base de datos PostgreSQL externa y los inyecta en los tokens JWT.**

---

## 📋 Tabla de Contenidos

- [Descripción General](#descripción-general)
- [Arquitectura](#arquitectura)
- [Estructura del Proyecto](#estructura-del-proyecto)
- [Prerrequisitos](#prerrequisitos)
- [Inicio Rápido](#inicio-rápido)
- [Configuración de Keycloak](#configuración-de-keycloak)
- [Probando la Implementación](#probando-la-implementación)
- [Solución de Problemas](#solución-de-problemas)
- [Configuración Avanzada](#configuración-avanzada)
- [Próximos Pasos](#próximos-pasos)

---

## 🎯 Descripción General

### Contexto y Motivación

Este POC replica el escenario real donde:
- Keycloak obtiene usuarios de **FortiAuthenticator vía SAML2** (que a su vez los obtiene de LDAP)
- Los roles vienen de una **base de datos externa mediante un JAR personalizado**

**Objetivo**: Obtener un conocimiento profundo y confianza en este patrón arquitectónico implementando primero una versión simplificada.

### Decisión de Diseño

División en dos POCs progresivos en lugar de abordar todo de una vez:

**POC-04-A** (este proyecto):
- Keycloak con **usuarios nativos** (sin SAML todavía)
- JAR personalizado que consulta roles desde **base de datos PostgreSQL externa**
- Enfoque simple: 1-2 clases Java
- Objetivo: Dominar el mecanismo de extensión de Keycloak

**POC-04-B** (futuro):
- Implementación completa del User Storage SPI
- Roles visibles en la Consola de Administración de Keycloak
- Más clases, integración más profunda con Keycloak

### Criterios de Éxito

✅ Login con `alan.turing` → JWT contiene el claim:
```json
{
  "external_roles": ["DEVELOPER", "ARCHITECT", "ADMIN"]
}
```

Estos roles se obtienen de PostgreSQL, **no** de la base de datos interna de Keycloak.

---

## 🏗️ Arquitectura

```
┌─────────────────────────────────────────────────────────────┐
│                      Login de Usuario                        │
│                  (alan.turing / test123)                     │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                        Keycloak                              │
│  - Usuarios nativos (sin SAML en POC-04-A)                  │
│  - Realm: example-poc                                        │
│  - Client: spring-client                                     │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           │ La generación del token dispara el mapper
                           ▼
┌─────────────────────────────────────────────────────────────┐
│       Custom Protocol Mapper (JAR)                           │
│  ExternalRolesProtocolMapper.java                            │
│  - Invocado durante la creación del token                    │
│  - Extrae el username del UserSessionModel                   │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           │ Consulta JDBC vía HikariCP
                           ▼
┌─────────────────────────────────────────────────────────────┐
│       Base de Datos PostgreSQL Externa                       │
│  Contenedor: roles-db                                        │
│  Tabla: user_roles (username, role_name)                     │
│  Query: SELECT role_name WHERE username = ?                  │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           │ Devuelve: ["DEVELOPER", "ARCHITECT", "ADMIN"]
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                      Token JWT                               │
│  {                                                           │
│    "sub": "alan.turing",                                     │
│    "external_roles": ["DEVELOPER", "ARCHITECT", "ADMIN"],    │
│    ...                                                       │
│  }                                                           │
└─────────────────────────────────────────────────────────────┘
```

### Componentes

1. **keycloak-roles-mapper** (módulo Maven)
   - `ExternalRolesProtocolMapper`: Implementación del SPI de Keycloak
   - `RoleRepository`: Capa de acceso a datos con HikariCP
   - Descriptor SPI: Registra el mapper en Keycloak

2. **roles-db** (contenedor PostgreSQL)
   - Almacena las asignaciones usuario-rol
   - Inicializado con datos de prueba vía `init-db/01-schema.sql`

3. **keycloak-db** (contenedor PostgreSQL)
   - Base de datos interna de Keycloak (realms, usuarios, clients, etc.)

4. **keycloak** (imagen Docker personalizada)
   - Basada en `quay.io/keycloak/keycloak:23.0.7`
   - Incluye el JAR del mapper personalizado en `/opt/keycloak/providers/`

---

## 📁 Estructura del Proyecto

```
keycloak-experiment/
├── pom.xml                              # POM padre (multi-módulo)
├── build.sh / build.bat                 # Scripts de compilación (Linux/Windows)
├── docker-compose.yml                   # Orquesta los 3 contenedores
│
├── keycloak-roles-mapper/               # Módulo Maven: Mapper personalizado
│   ├── pom.xml                          # Dependencias: Keycloak SPI, PostgreSQL, HikariCP
│   └── src/main/
│       ├── java/com/example/keycloak/mapper/
│       │   ├── ExternalRolesProtocolMapper.java    # Lógica principal del mapper
│       │   └── RoleRepository.java                 # Acceso a base de datos
│       └── resources/META-INF/services/
│           └── org.keycloak.protocol.ProtocolMapper  # Registro del SPI
│
├── spring-client/                       # Módulo Maven: Cliente de prueba opcional
│   ├── pom.xml
│   └── src/main/java/com/example/
│       └── KeycloakExperimentApplication.java
│
├── docker/
│   └── keycloak/
│       ├── Dockerfile                   # Keycloak + provider personalizado
│       └── keycloak-roles-mapper.jar    # Copiado aquí por el script de build
│
└── init-db/
    └── 01-schema.sql                    # Esquema PostgreSQL + datos de prueba
```

---

## 🔧 Prerrequisitos

- **Java 17** o superior
- **Maven 3.8+** (o usar el Maven wrapper incluido: `./mvnw`)
- **Docker** y **Docker Compose**
- **curl** (para pruebas) o **Postman**
- **Opcional**: Cliente de base de datos (DBeaver, pgAdmin) para inspeccionar las bases de datos

---

## 🚀 Inicio Rápido

### 1. Compilar el Proyecto

#### En Linux/Mac:
```bash
chmod +x build.sh
./build.sh start
```

#### En Windows:
```cmd
build.bat start
```

Esto realizará:
1. Compilar el JAR del mapper personalizado
2. Copiarlo al contexto de Docker
3. Construir la imagen Docker de Keycloak con el provider
4. Iniciar todos los contenedores (roles-db, keycloak-db, keycloak)

### 2. Esperar a que Keycloak Inicie

Monitorizar los logs:
```bash
docker-compose logs -f keycloak
```

Esperar hasta ver:
```
Keycloak 23.0.7 started
Listening on: http://0.0.0.0:8080
```

### 3. Acceder a la Consola de Administración de Keycloak

Abrir: **http://localhost:8080**

Credenciales:
- **Usuario**: `admin`
- **Contraseña**: `admin`

---

## ⚙️ Configuración de Keycloak

### Paso 1: Crear el Realm

1. En la Consola de Administración, pasar el cursor sobre "Master" (arriba a la izquierda) → **Create Realm**
2. **Realm name**: `example-poc`
3. Clic en **Create**

### Paso 2: Crear el Client

1. Navegar a **Clients** → **Create client**
2. **Client ID**: `spring-client`
3. **Client type**: `OpenID Connect`
4. Clic en **Next**
5. **Client authentication**: `ON` (confidential)
6. **Authorization**: `OFF`
7. **Authentication flow**: Habilitar:
   - ✅ Standard flow
   - ✅ Direct access grants (para pruebas con password grant)
8. Clic en **Save**

### Paso 3: Anotar el Client Secret

1. Ir a **Clients** → `spring-client` → pestaña **Credentials**
2. Copiar el **Client secret** (lo necesitarás para las pruebas)

### Paso 4: Crear el Usuario

1. Navegar a **Users** → **Add user**
2. **Username**: `alan.turing`
3. **Email**: `alan.turing@example.com` (opcional)
4. **Email verified**: `ON`
5. Clic en **Create**
6. Ir a la pestaña **Credentials**
7. Clic en **Set password**
8. **Password**: `test123`
9. **Temporary**: `OFF`
10. Clic en **Save**

### Paso 5: Añadir el Protocol Mapper Personalizado

1. Ir a **Clients** → `spring-client` → pestaña **Client scopes**
2. Clic en `spring-client-dedicated` (el scope dedicado)
3. Clic en **Add mapper** → **By configuration**
4. Seleccionar **External Database Roles Mapper** (¡este es tu mapper personalizado!)
5. Configuración (los valores por defecto están bien):
   - **Name**: `external-roles-mapper`
   - **Add to ID token**: `ON`
   - **Add to access token**: `ON`
   - **Add to userinfo**: `ON`
6. Clic en **Save**

---

## 🧪 Probando la Implementación

### Método 1: Obtener Token vía curl

```bash
curl -X POST "http://localhost:8080/realms/example-poc/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=spring-client" \
  -d "client_secret=TU_CLIENT_SECRET_AQUI" \
  -d "username=alan.turing" \
  -d "password=test123" \
  -d "grant_type=password"
```

**Reemplaza** `TU_CLIENT_SECRET_AQUI` con el secret del Paso 3.

### Método 2: Obtener Token vía Postman

1. **POST** `http://localhost:8080/realms/example-poc/protocol/openid-connect/token`
2. **Body**: `x-www-form-urlencoded`
   - `client_id`: `spring-client`
   - `client_secret`: `<TU_SECRET>`
   - `username`: `alan.turing`
   - `password`: `test123`
   - `grant_type`: `password`
3. Enviar petición

### Método 3: Decodificar y Verificar el JWT

1. Copiar el `access_token` de la respuesta
2. Ir a **https://jwt.io**
3. Pegar el token
4. Verificar que el payload contiene:

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

✅ **¡Éxito!** El claim `external_roles` demuestra que el mapper está funcionando.

---

## 🔍 Solución de Problemas

### Problema: El mapper no aparece en la Consola de Administración de Keycloak

**Síntomas**: "External Database Roles Mapper" no aparece en la lista al añadir un mapper.

**Soluciones**:
1. Verificar que el JAR se compiló y copió:
   ```bash
   ls -lh docker/keycloak/keycloak-roles-mapper.jar
   ```
2. Reconstruir la imagen de Keycloak:
   ```bash
   docker-compose down
   ./build.sh docker
   docker-compose up -d
   ```
3. Revisar los logs de Keycloak buscando el registro del provider:
   ```bash
   docker-compose logs keycloak | grep -i "external.*role"
   ```

### Problema: El JWT no contiene el claim `external_roles`

**Síntomas**: El token es válido pero falta el claim personalizado.

**Soluciones**:
1. Verificar que el mapper está configurado en el client scope:
   - Clients → spring-client → Client scopes → spring-client-dedicated
   - Debería aparecer "external-roles-mapper" en la lista
2. Comprobar que el mapper está habilitado para el access token:
   - Editar mapper → "Add to access token" = ON
3. Revisar la conectividad con la base de datos:
   ```bash
   docker-compose logs keycloak | grep -i "hikaricp"
   docker-compose logs keycloak | grep -i "roles"
   ```

### Problema: Array `external_roles` vacío

**Síntomas**: El claim existe pero `external_roles: []`

**Posibles causas**:
1. El username no existe en la base de datos de roles:
   ```bash
   docker-compose exec roles-db psql -U keycloak -d roles -c "SELECT * FROM user_roles WHERE username = 'alan.turing';"
   ```
2. Error de conexión a la base de datos (revisar logs)
3. Diferencia de mayúsculas/minúsculas en el username (PostgreSQL es case-sensitive)

### Problema: Timeout de conexión a la base de datos

**Síntomas**: Los logs muestran "Connection timeout" o "SQLException"

**Soluciones**:
1. Verificar que roles-db está healthy:
   ```bash
   docker-compose ps
   docker-compose logs roles-db
   ```
2. Comprobar las variables de entorno:
   ```bash
   docker-compose exec keycloak env | grep ROLES_DB
   ```
3. Probar la conectividad desde el contenedor de Keycloak:
   ```bash
   docker-compose exec keycloak bash
   apt update && apt install -y postgresql-client
   psql -h roles-db -U keycloak -d roles -c "SELECT 1"
   ```

---

## 🔧 Configuración Avanzada

### Variables de Entorno para la Base de Datos de Roles

Puedes personalizar la conexión a la base de datos en `docker-compose.yml`:

```yaml
environment:
  ROLES_DB_URL: jdbc:postgresql://roles-db:5432/roles
  ROLES_DB_USER: keycloak
  ROLES_DB_PASSWORD: keycloak
  ROLES_DB_POOL_SIZE: 10           # Tamaño máximo del pool de HikariCP
  ROLES_DB_MIN_IDLE: 2             # Conexiones mínimas idle de HikariCP
  ROLES_DB_CONN_TIMEOUT: 30000     # Timeout de conexión (ms)
  ROLES_DB_IDLE_TIMEOUT: 600000    # Timeout de inactividad (ms)
  ROLES_DB_MAX_LIFETIME: 1800000   # Tiempo máximo de vida de conexión (ms)
```

### Logging Personalizado

Habilitar logging de debug para el mapper:

```yaml
environment:
  QUARKUS_LOG_CATEGORY__COM_EXAMPLE_KEYCLOAK__LEVEL: debug
```

Ver logs detallados:
```bash
docker-compose logs -f keycloak | grep "com.example.keycloak"
```

### Datos Persistentes vs Efímeros

**Configuración actual**: Persistente (los datos sobreviven a `docker-compose down`)

**Para hacerlo efímero** (útil para pruebas):
```yaml
volumes:
  roles-db-data:
    # Comentar o eliminar este volumen
```

Luego reiniciar:
```bash
docker-compose down -v  # -v elimina los volúmenes
docker-compose up -d
```

---

## 🎯 Próximos Pasos

### Mejoras Inmediatas (dentro de POC-04-A)

1. **Añadir más usuarios de prueba**:
   - Editar `init-db/01-schema.sql`
   - Añadir sentencias INSERT
   - Reconstruir: `docker-compose down -v && ./build.sh start`

2. **Implementar validación de JWT en Spring Client**:
   - Añadir Spring Security + OAuth2 Resource Server
   - Validar la firma del JWT
   - Extraer y usar `external_roles` para autorización

3. **Añadir endpoint de health check**:
   - Verificar conectividad con la base de datos desde el mapper
   - Exponer vía endpoint REST personalizado en Keycloak

### POC-04-B: User Storage SPI

Evolucionar hacia una implementación completa del User Storage SPI:
- Roles visibles en la Consola de Administración de Keycloak
- Soporte para asignación de roles vía Admin UI
- Integración con el modelo de roles de Keycloak
- Caché y optimización de rendimiento

---

## 📚 Recursos

- [Documentación de Keycloak](https://www.keycloak.org/docs/latest/)
- [Guía de Desarrollo de SPI de Keycloak](https://www.keycloak.org/docs/latest/server_development/)
- [GitHub de HikariCP](https://github.com/brettwooldridge/HikariCP)
- [Debugger de JWT](https://jwt.io/)
