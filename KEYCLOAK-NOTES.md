# Notas de Keycloak: Flujos y Configuraciones

Este documento explica conceptos clave de Keycloak que encontramos durante la implementación de esta POC.

---

## 1. First Broker Login (Primer Login Federado)

### ¿Qué es?

Cuando un usuario se autentica via un Identity Provider externo (SAML, OIDC, etc.) por primera vez, Keycloak necesita crear una cuenta local vinculada. El flujo "First Broker Login" controla qué pasa en ese momento.

### Comportamiento por defecto

```
┌─────────────────────────────────────────────────────────────────┐
│                    Primera vez que entra                         │
│                                                                  │
│   Usuario ──► IdP ──► Login ──► SP recibe assertion             │
│                                       │                          │
│                                       ▼                          │
│                          ┌─────────────────────┐                │
│                          │ Update Account Info │                │
│                          │                     │                │
│                          │ Email: [________]   │                │
│                          │ First: [________]   │                │
│                          │ Last:  [________]   │                │
│                          │                     │                │
│                          │     [Submit]        │                │
│                          └─────────────────────┘                │
│                                       │                          │
│                                       ▼                          │
│                          Usuario creado en SP                    │
│                          (vinculado al IdP)                      │
└─────────────────────────────────────────────────────────────────┘
```

### ¿Es obligatorio este formulario?

No. Es configurable según tus necesidades:

| Escenario | Recomendación |
|-----------|---------------|
| IdP confiable con datos completos | Desactivar formulario |
| Necesitas datos adicionales | Mantener formulario |
| Usuarios internos (empleados) | Desactivar |
| Usuarios externos (clientes) | Evaluar caso a caso |

### Cómo desactivar el formulario

**Opción A: Deshabilitar "Review Profile"**

1. SP → **Authentication** → **First broker login**
2. En la fila **"Review Profile"** → menú (⋮) → **Disable**
3. El usuario se crea automáticamente sin pedir datos

**Opción B: Cambiar el flujo completo**

1. SP → **Identity Providers** → **[tu IdP]**
2. **First login flow**: cambiar a otro flujo (ej: `Automatically set existing user`)

### Flujos disponibles

| Flujo | Comportamiento |
|-------|----------------|
| `first broker login` | Revisa perfil + crea usuario (default) |
| `Automatically set existing user` | Vincula a usuario existente si el email coincide |
| Custom | Puedes crear tu propio flujo |

### Segunda vez que entra

El formulario solo aparece la **primera vez**. En logins posteriores:

```
Usuario ──► IdP ──► Login ──► SP ──► Token directo (sin formulario)
```

---

## 2. URL de Autorización OAuth2/OIDC

### Anatomía de la URL

```
http://localhost:8080/realms/sp-realm/protocol/openid-connect/auth?client_id=spring-client&response_type=code&redirect_uri=http://localhost:8080/&scope=openid
```

Desglosada:

```
http://localhost:8080
└─────────┬─────────┘
          │
    Keycloak SP (servidor de autorización)


/realms/sp-realm
└───────┬───────┘
        │
    Realm donde está configurado el client


/protocol/openid-connect/auth
└────────────┬────────────────┘
             │
    Endpoint de autorización OAuth2/OIDC
    (donde comienza el flujo de login)
```

### Parámetros de la URL

| Parámetro | Valor | Descripción |
|-----------|-------|-------------|
| `client_id` | `spring-client` | Identificador de la aplicación que solicita autenticación |
| `response_type` | `code` | Tipo de respuesta esperada (authorization code) |
| `redirect_uri` | `http://localhost:8080/` | URL donde Keycloak redirige después del login |
| `scope` | `openid` | Permisos solicitados (openid = quiero ID token) |

### Response Types

| Valor | Flujo OAuth2 | Uso |
|-------|--------------|-----|
| `code` | Authorization Code | Apps server-side (más seguro) |
| `token` | Implicit | Apps client-side (deprecated) |
| `code token` | Hybrid | Casos especiales |

### Scopes comunes

| Scope | Qué incluye en el token |
|-------|-------------------------|
| `openid` | Subject (sub), obligatorio para OIDC |
| `profile` | name, family_name, given_name, etc. |
| `email` | email, email_verified |
| `roles` | Roles del usuario |

### Ejemplo completo con más parámetros

```
http://localhost:8080/realms/sp-realm/protocol/openid-connect/auth
  ?client_id=spring-client
  &response_type=code
  &redirect_uri=http://localhost:8080/callback
  &scope=openid profile email
  &state=abc123              ← Previene CSRF
  &nonce=xyz789              ← Previene replay attacks
  &prompt=login              ← Fuerza re-autenticación
```

---

## 3. Página de Login del SP

### ¿Por qué muestra múltiples opciones?

Cuando accedes al endpoint de autorización, Keycloak muestra **todas las formas de autenticarse** configuradas en ese realm:

```
┌─────────────────────────────────────────┐
│             SP-REALM                    │
│                                         │
│   ┌─────────────────────────────────┐   │
│   │      Sign in to your account    │   │
│   │                                 │   │
│   │   Username: [________________]  │ ◄─┼── Para usuarios LOCALES
│   │   Password: [________________]  │   │   (creados en sp-realm)
│   │                                 │   │
│   │          [Sign In]              │   │
│   │                                 │   │
│   │   ─────── Or sign in with ───── │   │
│   │                                 │   │
│   │   [Login con FortiAuth]         │ ◄─┼── Identity Provider SAML
│   │                                 │   │   (redirige al IdP externo)
│   └─────────────────────────────────┘   │
│                                         │
└─────────────────────────────────────────┘
```

### Tipos de autenticación

| Tipo | Origen | Ejemplo |
|------|--------|---------|
| **Local** | Usuarios creados en el realm del SP | Formulario username/password |
| **Federado** | Identity Providers configurados | Botón SAML, Google, GitHub, etc. |

### En esta POC

- **No hay usuarios locales** en sp-realm
- El formulario username/password no funcionará (no hay usuarios)
- Solo funciona el botón "Login con FortiAuth (Simulado)" → redirige al IdP

### Personalización de la página de login

| Configuración | Ubicación | Efecto |
|---------------|-----------|--------|
| **Default** | Identity Providers → [IdP] | ON = Redirige automáticamente al IdP |
| **Hide on login page** | Identity Providers → [IdP] | ON = Oculta el botón del IdP |
| **Login Theme** | Realm Settings → Themes | Personaliza el aspecto visual |

---

## 4. Redirect Automático al IdP

### ¿Cuándo usarlo?

Cuando tienes **un solo método de login** (solo SAML, solo Google, etc.), puedes saltar la página de login del SP y redirigir directamente al IdP.

### Cómo configurarlo

1. SP → **Identity Providers** → **[tu IdP]**
2. Activar **"Default"**: **ON**
3. Guardar

### Comportamiento resultante

**Antes (Default: OFF)**:
```
Usuario ──► SP login page ──► Click en IdP ──► IdP login ──► Token
```

**Después (Default: ON)**:
```
Usuario ──► SP ──► Redirect automático ──► IdP login ──► Token
```

### Forzar un IdP específico via URL

También puedes forzar el IdP añadiendo un parámetro a la URL:

```
http://localhost:8080/realms/sp-realm/protocol/openid-connect/auth
  ?client_id=spring-client
  &response_type=code
  &redirect_uri=http://localhost:8080/
  &scope=openid
  &kc_idp_hint=forti-simulator    ← Fuerza este IdP
```

El parámetro `kc_idp_hint` indica a Keycloak qué Identity Provider usar, saltando la página de selección.

---

## 5. Flujo Completo: Del Click al Token

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         FLUJO AUTHORIZATION CODE                         │
│                                                                          │
│  1. App construye URL de autorización                                   │
│     ──────────────────────────────────────────────────────────────      │
│     http://localhost:8080/realms/sp-realm/protocol/openid-connect/auth  │
│       ?client_id=spring-client                                          │
│       &response_type=code                                               │
│       &redirect_uri=http://localhost:8080/                              │
│       &scope=openid                                                     │
│                                                                          │
│  2. Usuario abre URL → Keycloak SP                                      │
│     ──────────────────────────────────────────────────────────────      │
│     SP muestra página de login (o redirige a IdP si Default=ON)         │
│                                                                          │
│  3. Usuario elige IdP → Redirect a IdP                                  │
│     ──────────────────────────────────────────────────────────────      │
│     SP genera SAML AuthnRequest → Redirige al IdP                       │
│                                                                          │
│  4. Usuario se autentica en IdP                                         │
│     ──────────────────────────────────────────────────────────────      │
│     IdP valida credenciales → Genera SAML Response                      │
│                                                                          │
│  5. IdP redirige de vuelta al SP                                        │
│     ──────────────────────────────────────────────────────────────      │
│     SAML Response con Assertion (username, email, etc.)                 │
│                                                                          │
│  6. SP procesa SAML Response                                            │
│     ──────────────────────────────────────────────────────────────      │
│     - Valida assertion                                                  │
│     - Crea/actualiza usuario local                                      │
│     - Ejecuta Protocol Mappers (← aquí se añade external_roles)         │
│                                                                          │
│  7. SP redirige a redirect_uri con code                                 │
│     ──────────────────────────────────────────────────────────────      │
│     http://localhost:8080/?code=abc123&session_state=xyz789             │
│                                                                          │
│  8. App intercambia code por tokens                                     │
│     ──────────────────────────────────────────────────────────────      │
│     POST /token                                                         │
│       client_id, client_secret, code, redirect_uri                      │
│                                                                          │
│  9. SP devuelve tokens                                                  │
│     ──────────────────────────────────────────────────────────────      │
│     {                                                                   │
│       "access_token": "eyJ...",   ← Contiene external_roles             │
│       "id_token": "eyJ...",                                             │
│       "refresh_token": "eyJ..."                                         │
│     }                                                                   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 6. Resumen de Endpoints

| Endpoint | Propósito |
|----------|-----------|
| `/auth` | Iniciar flujo de autorización (login) |
| `/token` | Intercambiar code por tokens |
| `/userinfo` | Obtener info del usuario con access_token |
| `/logout` | Cerrar sesión |
| `/certs` | Obtener claves públicas para validar tokens |

### URLs completas para sp-realm

```bash
# Autorización (iniciar login)
http://localhost:8080/realms/sp-realm/protocol/openid-connect/auth

# Token (intercambiar code)
http://localhost:8080/realms/sp-realm/protocol/openid-connect/token

# UserInfo (datos del usuario)
http://localhost:8080/realms/sp-realm/protocol/openid-connect/userinfo

# Logout
http://localhost:8080/realms/sp-realm/protocol/openid-connect/logout

# JWKS (claves públicas)
http://localhost:8080/realms/sp-realm/protocol/openid-connect/certs

# Well-known (descubrimiento)
http://localhost:8080/realms/sp-realm/.well-known/openid-configuration
```

---

## Referencias

- [OAuth 2.0 RFC 6749](https://tools.ietf.org/html/rfc6749)
- [OpenID Connect Core 1.0](https://openid.net/specs/openid-connect-core-1_0.html)
- [Keycloak Identity Brokering](https://www.keycloak.org/docs/latest/server_admin/#_identity_broker)
- [Keycloak First Login Flow](https://www.keycloak.org/docs/latest/server_admin/#_identity_broker_first_login)
