# Notas de Seguridad: Firmas SAML

Este documento explica las configuraciones de seguridad SAML que se desactivaron en la POC y cómo configurarlas correctamente en producción.

---

## Resumen Ejecutivo

En esta POC desactivamos la verificación de firmas SAML para simplificar la configuración inicial. **En producción, estas firmas son críticas** para prevenir ataques de suplantación de identidad y manipulación de datos.

| Configuración | POC | Producción |
|---------------|-----|------------|
| Client signature required (IdP) | OFF | **ON** |
| Want AuthnRequests signed (SP) | OFF | **ON** |
| Validate Signatures (SP) | OFF | **ON** |

---

## ¿Qué es la firma en SAML?

SAML usa firmas digitales XML (XMLDSig) para garantizar:

1. **Autenticidad**: El mensaje realmente viene de quien dice ser
2. **Integridad**: El mensaje no fue modificado en tránsito
3. **No repudio**: El emisor no puede negar haber enviado el mensaje

```
┌─────────────────────────────────────────────────────────────────┐
│                        Flujo SAML                                │
│                                                                  │
│   Usuario         SP                              IdP            │
│      │            │                                │             │
│      │ ─accede──► │                                │             │
│      │            │                                │             │
│      │            │ ───── AuthnRequest ──────────► │             │
│      │            │      (puede ir firmado)        │             │
│      │            │                                │             │
│      │            │ ◄──── Response + Assertion ─── │             │
│      │            │         (DEBE ir firmado)      │             │
│      │            │                                │             │
│      │ ◄─token──  │                                │             │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Las 3 Configuraciones Explicadas

### 1. Client signature required (en el IdP)

**Ubicación**: IdP → Clients → [cliente SAML] → Keys

**Qué hace**: El IdP exige que el SP firme sus AuthnRequests.

```
SP ────── AuthnRequest ──────► IdP
              │
              └─► ¿Tiene firma válida?
                      │
                  ┌───┴───┐
                  │       │
                 SÍ      NO
                  │       │
                  ▼       ▼
              Procesar  Rechazar
                      "Invalid requester"
```

**¿Por qué es importante?**
- Previene que un atacante envíe AuthnRequests falsos haciéndose pasar por el SP
- Garantiza que solo SPs autorizados pueden iniciar el flujo de autenticación

**¿Por qué lo desactivamos en la POC?**
- El IdP no tenía el certificado público del SP para verificar la firma
- Configurar el intercambio de certificados añade complejidad

---

### 2. Want AuthnRequests signed (en el SP)

**Ubicación**: SP → Identity Providers → [IdP] → Settings

**Qué hace**: El SP firma sus AuthnRequests antes de enviarlos al IdP.

```
┌─────────────────────────────────────────┐
│            AuthnRequest                  │
│                                          │
│  <samlp:AuthnRequest                     │
│      ID="_abc123"                        │
│      IssueInstant="2024-01-01T..."       │
│      Destination="https://idp/sso">      │
│                                          │
│    <ds:Signature>                        │ ◄── Firma XML
│      <ds:SignedInfo>...</ds:SignedInfo>  │
│      <ds:SignatureValue>                 │
│        BASE64_SIGNATURE_HERE             │
│      </ds:SignatureValue>                │
│    </ds:Signature>                       │
│                                          │
│  </samlp:AuthnRequest>                   │
└─────────────────────────────────────────┘
```

**¿Por qué es importante?**
- Demuestra al IdP que la petición viene realmente del SP legítimo
- Previene ataques de replay donde un atacante reenvía peticiones capturadas

**¿Por qué lo desactivamos en la POC?**
- Requiere que el IdP tenga el certificado del SP configurado
- Sin el certificado correcto, el IdP rechaza la petición

---

### 3. Validate Signatures (en el SP)

**Ubicación**: SP → Identity Providers → [IdP] → Settings

**Qué hace**: El SP verifica la firma de las respuestas SAML del IdP.

```
IdP ────── SAML Response ──────► SP
                │
                └─► ¿Firma válida con certificado conocido?
                        │
                    ┌───┴───┐
                    │       │
                   SÍ      NO
                    │       │
                    ▼       ▼
              Crear sesión  Rechazar
              del usuario   "invalid_signature"
```

**¿Por qué es CRÍTICO?**

Esta es la configuración **más importante**. Sin ella, un atacante podría:

```
┌─────────────────────────────────────────────────────────────────┐
│                    ATAQUE: SAML Response Forgery                 │
│                                                                  │
│   Atacante                           SP                          │
│      │                               │                           │
│      │ ─── Fake SAML Response ─────► │                           │
│      │     (sin firma o firma falsa) │                           │
│      │                               │                           │
│      │     Assertion:                │                           │
│      │     "Soy admin@empresa.com"   │                           │
│      │                               │                           │
│      │                               ▼                           │
│      │                     Si no valida firma:                   │
│      │                     ¡Acceso concedido como admin!         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**¿Por qué lo desactivamos en la POC?**
- Al reconstruir el contenedor del IdP, se regeneraron sus claves
- El SP tenía cacheado el certificado antiguo
- Las firmas no coincidían

---

## Cómo Configurar Firmas Correctamente en Producción

### Opción A: Intercambio Manual de Certificados

#### Paso 1: Exportar certificado del IdP

```bash
# Acceder al IdP Admin Console
# Realm Settings → Keys → RS256 → Certificate
# Copiar el contenido del certificado
```

#### Paso 2: Importar en el SP

```bash
# SP → Identity Providers → [IdP] → Settings
# Pegar el certificado en "Validating X509 Certificates"
# Activar "Validate Signatures: ON"
```

#### Paso 3: Exportar certificado del SP

```bash
# SP → Realm Settings → Keys → RS256 → Certificate
# Copiar el contenido
```

#### Paso 4: Importar en el IdP

```bash
# IdP → Clients → [cliente SAML] → Keys
# Importar el certificado del SP
# Activar "Client signature required: ON"
```

### Opción B: Usar Metadata con Certificados

Los endpoints de metadata SAML incluyen los certificados:

```
# Metadata del IdP (incluye su certificado)
http://localhost:8180/realms/idp-realm/protocol/saml/descriptor

# Metadata del SP (incluye su certificado)
http://localhost:8080/realms/sp-realm/protocol/saml/descriptor
```

**Flujo recomendado**:

1. **IdP** importa metadata del SP → obtiene certificado del SP automáticamente
2. **SP** importa metadata del IdP → obtiene certificado del IdP automáticamente
3. Activar todas las validaciones de firma

### Opción C: Certificados Externos (Producción Real)

En producción real, usa certificados de una CA (Certificate Authority):

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                  │
│   ┌─────────────┐                                               │
│   │     CA      │  (DigiCert, Let's Encrypt, CA interna)        │
│   └──────┬──────┘                                               │
│          │                                                       │
│    ┌─────┴─────┐                                                │
│    ▼           ▼                                                │
│  ┌───┐       ┌───┐                                              │
│  │IdP│       │SP │                                              │
│  └───┘       └───┘                                              │
│                                                                  │
│  Ambos confían en la CA                                         │
│  → Pueden verificar certificados sin intercambio manual         │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Ataques que Previenen las Firmas

### 1. SAML Response Injection

**Sin firma**: Atacante crea una respuesta SAML falsa.

```xml
<saml:Assertion>
  <saml:Subject>
    <saml:NameID>admin@victima.com</saml:NameID>
  </saml:Subject>
</saml:Assertion>
```

**Con firma**: El SP rechaza porque la firma no es válida.

### 2. Assertion Replay

**Sin firma**: Atacante captura y reenvía una assertion válida.

**Con firma + timestamps**: La assertion expira y no puede reutilizarse.

### 3. Man-in-the-Middle

**Sin firma**: Atacante modifica la assertion en tránsito.

```
IdP ──► [Atacante modifica assertion] ──► SP
```

**Con firma**: Cualquier modificación invalida la firma.

### 4. SP Impersonation

**Sin firma en AuthnRequest**: Atacante se hace pasar por un SP legítimo.

**Con firma**: El IdP verifica que el AuthnRequest viene del SP real.

---

## Checklist de Seguridad para Producción

### Obligatorio

- [ ] **Validate Signatures: ON** en todos los SPs
- [ ] Certificados del IdP importados en todos los SPs
- [ ] HTTPS en todos los endpoints SAML
- [ ] Assertions firmadas (configuración por defecto en Keycloak)

### Recomendado

- [ ] **Client signature required: ON** en el IdP
- [ ] **Want AuthnRequests signed: ON** en el SP
- [ ] Certificados con fecha de expiración monitoreada
- [ ] Rotación de certificados planificada

### Adicional

- [ ] Assertions encriptadas (no solo firmadas)
- [ ] Validación de audiencia (Audience Restriction)
- [ ] Tiempo de vida corto para assertions (NotOnOrAfter)
- [ ] Single Logout configurado y firmado

---

## Configuración Recomendada por Entorno

| Setting | Desarrollo | Staging | Producción |
|---------|------------|---------|------------|
| Validate Signatures | OFF/ON | **ON** | **ON** |
| Client signature required | OFF | ON | **ON** |
| Want AuthnRequests signed | OFF | ON | **ON** |
| HTTPS | Opcional | **Sí** | **Sí** |
| Encrypt Assertions | No | Opcional | **Sí** |

---

## Referencias

- [OWASP SAML Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/SAML_Security_Cheat_Sheet.html)
- [Keycloak SAML Documentation](https://www.keycloak.org/docs/latest/server_admin/#saml-clients)
- [XML Signature (XMLDSig)](https://www.w3.org/TR/xmldsig-core1/)
- [SAML 2.0 Security Considerations](https://docs.oasis-open.org/security/saml/v2.0/saml-sec-consider-2.0-os.pdf)
