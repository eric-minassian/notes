---
title: "Frontend + Router Integration Architecture Options"
description: "Compares AWS-native frontend, BFF, and router integration patterns for protected SPA and partner API access."
date: 2026-05-16
tags: ["aws", "architecture", "frontend", "api-gateway", "bff"]
---

## Context

We need an AWS-native architecture that:

- serves a protected React SPA
- prevents unauthenticated access to frontend assets
- supports Cognito today but can evolve to Okta/other IdPs
- provides a single API front door/router for many backend services
- supports partner SDKs and machine-to-machine auth
- provides a path to API Gateway features like mTLS
- works in GovCloud / FedRAMP High constraints
- keeps frontend-specific integration/config/telemetry concerns out of the public SDK

The key design question is how `domain.com`, `domain.com/api/*`, and `api.domain.com` should interact across frontend-owned and router-owned infrastructure.

---

## Option 1 — Shared frontend-owned router Lambda behind both ALB and API Gateway

In this option, frontend owns the Lambda, consolidates authorizer/router behavior into it, and both frontend ALB and router API Gateway invoke it.

```mermaid
sequenceDiagram
    participant Browser
    participant ALB as Frontend ALB domain.com
    participant Lambda as Frontend-Owned Router Lambda
    participant APIGW as Router API Gateway api.domain.com
    participant Service as Backend Service

    Browser->>ALB: GET /api/orders with ALB session
    ALB->>ALB: OIDC auth, inject x-amzn-oidc-* headers
    ALB->>Lambda: Invoke Lambda target
    Lambda->>Service: Route request
    Service-->>Lambda: Response
    Lambda-->>Browser: API response

    Note over APIGW,Lambda: Partner / SDK path
    APIGW->>Lambda: Cross-account Lambda invoke
    Lambda->>Service: Route request
```

### Good

- Avoids an extra BFF hop for frontend API requests.
- Frontend Lambda can directly access ALB OIDC headers such as `x-amzn-oidc-accesstoken`.
- API Gateway can cross-account invoke the same Lambda.
- Router team can still own `api.domain.com`, throttling, WAF, mTLS, custom domains, etc.

### Bad

- Ownership gets blurry: frontend now owns the real routing/auth behavior.
- API Gateway becomes mostly a shell in front of frontend-owned logic.
- ALB auth context and API Gateway auth context are different; Lambda must support both event/auth models.
- API Gateway mTLS only protects `api.domain.com`, not `domain.com/api/*`.
- Partner-facing SDK behavior depends on frontend-owned Lambda deployments.
- Harder to reason about public API lifecycle if router team does not own the core router implementation.

### Fit

Technically valid, but organizationally risky unless frontend is intended to own the router long-term.

---

## Option 2 — Frontend BFF forwards to router-owned API Gateway

Frontend owns the SPA, ALB, and a small BFF. Router team continues to own API Gateway and routing.

```mermaid
sequenceDiagram
    participant Browser
    participant ALB as Frontend ALB domain.com
    participant BFF as Frontend BFF
    participant APIGW as Router API Gateway api.domain.com
    participant Router as Router Service/Lambda
    participant Service as Backend Service

    Browser->>ALB: GET /app
    ALB->>ALB: Redirect to IdP if unauthenticated
    ALB-->>Browser: React SPA assets

    Browser->>ALB: GET /api/orders
    ALB->>ALB: OIDC auth, inject x-amzn-oidc-* headers
    ALB->>BFF: Forward /api/orders
    BFF->>BFF: Normalize frontend identity/session
    BFF->>APIGW: Forward to api.domain.com/orders
    APIGW->>Router: Invoke router
    Router->>Service: Route to backend
    Service-->>Router: Response
    Router-->>APIGW: Response
    APIGW-->>BFF: Response
    BFF-->>Browser: Response
```

### Good

- Clear ownership boundary:
  - frontend owns frontend experience and frontend-only services
  - router owns public API front door, routing policy, SDK contract, mTLS path
- Keeps partner API and frontend API aligned through one router.
- Frontend can keep same-origin browser calls to `domain.com/api/*`.
- Avoids exposing partner-oriented auth details directly in browser code.
- Frontend-only endpoints can stay out of partner SDKs.
- Router team can evolve mTLS, throttling, WAF, API Gateway policies without frontend needing to own them.
- BFF can translate ALB/OIDC session context into router-compatible auth context.
- Supports future IdP swap by localizing frontend session handling.

### Bad

- Adds one network hop.
- BFF must be operated, monitored, scaled, and secured.
- Need clear contract between BFF and router.
- If implemented as Lambda, cold starts could add latency.
- If BFF performs token introspection or IdP calls per request, latency can grow.

### Latency note

A lightweight warm BFF usually adds approximately **single-digit to low double-digit milliseconds** inside the same AWS region. The bigger latency risks are cold starts, per-request token introspection, NAT/VPC egress, and non-pooled HTTP clients.

### Fit

Best balance of ownership, extensibility, and security.

---

## Option 3 — Token-mediating backend pattern

In this model, frontend BFF does more than proxy. It actively mediates tokens: it receives ALB/OIDC session context, exchanges or mints a downstream token, then calls the router.

```mermaid
sequenceDiagram
    participant Browser
    participant ALB as Frontend ALB
    participant BFF as Token-Mediating BFF
    participant IdP as Cognito/Okta/Auth Service
    participant APIGW as Router API Gateway
    participant Router
    participant Service

    Browser->>ALB: GET /api/orders
    ALB->>BFF: Request with authenticated OIDC headers
    BFF->>IdP: Exchange/introspect/refresh token
    IdP-->>BFF: Router-facing token or claims
    BFF->>APIGW: Request with normalized token
    APIGW->>Router: Invoke router
    Router->>Service: Route request
    Service-->>Router: Response
    Router-->>BFF: Response
    BFF-->>Browser: Response
```

### Good

- Strongest abstraction between browser auth and backend auth.
- Router sees a clean, stable token/claims model.
- Easier to swap Cognito for Okta later if BFF owns token mediation.
- Can support fine-grained frontend session rules, token refresh, and claims normalization.
- Browser does not need direct access to backend-oriented credentials.

### Bad

- More complex than a simple proxy BFF.
- Can add significant latency if token exchange/introspection happens per request.
- Requires careful caching and token lifecycle management.
- BFF becomes security-critical.
- More implementation burden and more audit surface.

### Fit

Good if the organization needs strong IdP abstraction or does not want browser-held access tokens to be passed to the router. Potentially overkill for the first iteration.

---

## Option 4 — Browser calls `api.domain.com` directly

Frontend serves the SPA behind ALB auth, but the React app calls the router API directly with bearer tokens.

```mermaid
sequenceDiagram
    participant Browser
    participant ALB as Frontend ALB domain.com
    participant IdP as Cognito/Okta
    participant APIGW as API Gateway api.domain.com
    participant Router
    participant Service

    Browser->>ALB: GET /app
    ALB->>IdP: Redirect/login if needed
    ALB-->>Browser: React SPA

    Browser->>IdP: Obtain access token
    Browser->>APIGW: GET /orders Authorization: Bearer token
    APIGW->>Router: Invoke router
    Router->>Service: Route request
```

### Good

- Simple infrastructure path.
- No BFF hop.
- Router remains the single API front door.
- Good alignment with partner SDK model.

### Bad

- Browser must manage API tokens directly.
- CORS is required.
- Frontend asset auth and API auth become separate flows.
- Harder to hide frontend-only integration/config endpoints.
- Less control over session-to-token mediation.
- More coupling between SPA and IdP/token details.

### Fit

Reasonable for a pure SPA model, but less attractive when frontend already needs a backend service and wants frontend-only integration/config behavior.

---

## Recommendation

Recommend **Option 2: Frontend BFF forwards to router-owned API Gateway**, with a path to Option 3 if stronger token mediation becomes necessary.

```mermaid
flowchart LR
    Browser --> ALB[Frontend ALB<br/>domain.com]
    ALB --> SPA[Protected React SPA assets]
    ALB --> BFF[Frontend BFF<br/>/api/*]
    BFF --> APIGW[Router API Gateway<br/>api.domain.com]
    APIGW --> Router[Router Lambda/Service]
    Router --> Services[Backend Services]

    Partner[Partner / SDK / M2M] --> APIGW
```

### Recommended ownership

#### Frontend team owns

- `domain.com`
- ALB authentication for protected frontend access
- React SPA delivery
- frontend BFF
- frontend-only integration/config/telemetry endpoints
- translation of ALB session/OIDC context into router-compatible requests

#### Router team owns

- `api.domain.com`
- API Gateway
- mTLS configuration
- WAF/throttling/usage plans as needed
- router Lambda/service
- route-based access control
- OpenAPI contract
- generated partner SDKs

#### Backend service teams own

- service implementation
- tag/resource/business authorization
- service-local policies

### Why this recommendation

This keeps the router as the authoritative public API boundary while letting frontend own the user-facing application boundary. It supports authenticated frontend assets, same-origin frontend API calls, partner SDKs, machine-to-machine auth, and future API Gateway mTLS without making frontend own the entire public API routing surface.

The extra BFF hop is usually acceptable if the BFF is lightweight, warm, uses connection pooling, caches IdP metadata/JWKS, and avoids per-request token introspection.
