# App Store Connect Submission Package — Version 1.0 (Beta 0.3)

This document tracks all version-bound metadata, review account credentials, testing notes, URLs, and submission parameters required for App Store Connect submission.

---

## 1. App Information & Store Metadata (English - U.S.)

- **App Name**: `LaPluma`
- **Subtitle**: `Immigration Paperwork & Forms` *(or Leave Empty)*
- **Primary Language**: `English (U.S.)`
- **Secondary Language**: `Spanish (Mexico)` / `Spanish (Latin America)`
- **Bundle Identifier**: `app.aperture.mobile`
- **SKU**: `lapluma-ios-v1`
- **Primary Category**: `Productivity`
- **Secondary Category**: `Utilities`

### Promotional Text *(Max 170 characters)*
```text
Bring forms, documents, and missing answers into one clear, accessible workspace.
```

### Description *(Max 4,000 characters)*
```text
LaPluma helps you organize forms, supporting documents, and the questions that still need your attention.

Keep related paperwork together, scan paperwork, choose an image, or open files, and see clear next steps in one place. Color, icons, and plain-language status cards help distinguish required actions, helpful information, and items that need review.

Choose how you answer missing questions: chat, voice, or structured typing. Review extracted information against its source before you confirm it, and keep a visible history when a value changes.

LaPluma is an organization and documentation tool. It is not a law firm, does not provide legal advice, and does not promise an application outcome. Always review official instructions and your completed materials before filing.

Accessibility features include Dynamic Type support, large touch targets, semantic status cues, Spanish navigation for the core journey, and a voice-first accessibility profile.
```

### Keywords *(Max 100 characters)*
```text
documents,forms,checklist,organizer,paperwork,scanner,files,applications,accessibility
```

### URLs & Identity
- **Support URL**: `https://lapluma.ai`
- **Marketing URL**: `https://lapluma.ai`
- **Privacy Policy URL**: `https://lapluma.ai/privacy`
- **Version Number**: `1.0`
- **Copyright**: `2026 HybridCloudWorks`

---

## 2. Spanish Localization Metadata (es-MX)

### Promotional Text (Texto promocional)
```text
Reúne formularios, documentos y respuestas pendientes en un espacio claro y accesible.
```

### Description (Descripción)
```text
LaPluma le ayuda a organizar formularios, documentos de respaldo y las preguntas que aún requieren su atención.

Mantenga los papeles relacionados juntos, escanee documentos, elija una foto o abra archivos, y vea los siguientes pasos con claridad en un solo lugar. El color, los íconos y las tarjetas de estado en lenguaje sencillo ayudan a distinguir las acciones obligatorias, la información útil y los elementos por revisar.

Elija cómo responder las preguntas pendientes: chat, voz o escritura estructurada. Revise la información extraída frente a su documento de origen antes de confirmarla y conserve un historial visible de cualquier cambio.

LaPluma es una herramienta de organización y documentación. No es un bufete de abogados, no brinda asesoría legal y no garantiza el resultado de ninguna solicitud. Revise siempre las instrucciones oficiales y sus materiales completos antes de presentarlos.

Las funciones de accesibilidad incluyen compatibilidad con Tamaño Dinámico, áreas táctiles amplias, señales semánticas de estado, navegación en español para el recorrido principal y un perfil de accesibilidad centrado en voz.
```

### Keywords (Palabras clave)
```text
documentos,formularios,trámites,organizador,papeles,escáner,archivos,solicitudes,accesibilidad
```

---

## 3. App Review Information

### Sign-in Information
- **Sign-in required**: [x] Checked
- **User name**: `reviewer@hybridcloudworks.com`
- **Password**: `ReviewPasskey2026!`

### Contact Information
- **First Name**: `Saul`
- **Last Name**: `Patino`
- **Email**: `spatino@hybridcloudworks.com`
- **Role**: Developer / Release Engineering

### Reviewer Notes (Exact Text for App Store Reviewer)
```text
Testing Instructions for App Reviewer:

1. Authentication & Onboarding:
LaPluma uses passwordless authentication (Passkeys / Face ID) and instant onboarding.
To test the app:
Option A (Instant Test / Create Account):
- Tap "Create account" on the welcome screen.
- Enter any email (e.g. reviewer@apple.com) and name (e.g. App Reviewer).
- Acknowledge the notice and tap "Create passkey".
- A one-time recovery code will be displayed; tap "Continue" to immediately enter the authenticated workspace.

Option B (Enterprise Sign-In):
- Tap "Sign in".
- Work email: reviewer@hybridcloudworks.com
- Workspace code: NYC-01
- Tap "Continue with passkey" or "Use account recovery" to sign in directly.

2. Core Features to Test:
- Document Management: Review organized client cases, folders, and USCIS form checklists.
- Smart Document Scanner: Tap the "Capture" tab and select "Smart document scanner". The on-device Apple VisionKit camera scanner will detect document boundaries and classify document types locally with zero cloud leakage.
- Missing Items & Interactive Interview: Tap the "Missing" tab to test answering questions via conversational chat or voice. Strict validation ensures only valid calendar dates and data are accepted.
- Accessibility & Bilingual Support: Fully supports Dynamic Type, high contrast tokens, and bilingual (English/Spanish) localization.

3. Legal & Regulatory Notice:
LaPluma is an organizational and documentation workflow tool; it is not a law firm and does not provide legal advice.

If you have any questions during review, please contact the developer via the phone number or email provided above.
```

---

## 4. Previews and Screenshots Specification

### iPhone (6.5" / 6.7" / 6.9" Display)
- **Supported Dimensions**: `1290 x 2796` (iPhone 16 Pro Max / 15 Pro Max) or `1284 x 2778` (iPhone 14 Plus / 13 Pro Max)
- **Format**: RGB, 72 dpi, PNG or JPEG with **no alpha channel (opaque)**.
- **Key Screens Captured**:
  1. *Welcome*: Clear start screen introducing the organization tool.
  2. *Clients / Dashboard*: Active casework, organized paperwork, and progress status.
  3. *Smart Document Scanner*: On-device camera scanning with automatic document classification (Passport, Permanent Resident Card, USCIS notice).
  4. *What's Missing / Interactive Interview*: Conversational questions resolved via chat or voice with strict validation.
  5. *Review & Forms*: Completed form package checklist ready for export.

### iPad (13" Display)
- **Dimensions**: `2048 x 2732` or `2064 x 2752`
- Multi-column layout with Clients, Reviewer Queue, and Settings.
