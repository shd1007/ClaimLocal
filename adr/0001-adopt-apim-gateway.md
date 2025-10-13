# ADR 0001: Adopt Azure API Management (APIM) as Gateway for Claims Summarization API

Date: 2025-10-13
Status: Accepted

## Context
The Claim Status / Summarization API exposes minimal endpoints (`GET /claims/{id}` and `POST /claims/{id}/summarize`) that will be consumed by multiple internal and potentially external clients. We need:
- Centralized rate limiting to protect Azure OpenAI usage costs
- Consistent authentication / future JWT validation and key management
- Policy-based transformations (e.g., response shaping, header injection)
- Observability (per-operation metrics, latency, failure %)
- A place to apply custom security (IP filtering, content validation) without modifying application code

Alternatives considered:
1. Direct ingress (public ACA + custom reverse proxy) – increases custom maintenance, limited policy surface.
2. Azure Front Door + custom functions – good for global routing, but lacks rich API-specific policy model out-of-box.
3. Application Gateway with WAF – strong L7 protection, but not as granular for per-operation policies/lifecycle.
4. APIM (chosen) – mature policy engine, developer portal (optional), built-in analytics, straightforward key/subscription model, easy future JWT + caching policies.

## Decision
Adopt Azure API Management as the API gateway in front of the Container App hosting the summarization API. All client traffic flows: Client → APIM → ACA → Azure OpenAI (indirectly). APIM policies will enforce rate limits, request/response shaping, and set the stage for future authentication.

## Consequences
Positive:
- Rapid enforcement of rate limits to prevent runaway OpenAI cost.
- Central point for future auth (JWT validate-jwt policy) and caching.
- Simplifies A/B versioning of future endpoints (versioned APIs or revisions).
- Observability via APIM analytics consolidated with Container logs.

Negative / Trade-offs:
- Additional cost for APIM instance (depending on tier).
- Slight added latency (typically low ms overhead) per request.
- Need to manage policy deployment (handled via pipeline script or IaC export/import later).

## Implementation Notes
- Policies stored under `apim/` folder; pipeline (future enhancement) will import OpenAPI and upsert policies.
- Consider switching placeholder CLI calls to ARM/Bicep or `az apim api import` with revision support for evolutions.
- Evaluate APIM tier (Consumption vs Basic) based on projected RPS and SLA needs.

## Future Considerations
- Introduce JWT validation policy with Azure AD issuer.
- Add caching policy on GET endpoint if claim data becomes remote/expensive.
- Add custom headers for correlation IDs and propagate to ACA logs.
- Consider Developer Portal onboarding if external partners need documentation.
