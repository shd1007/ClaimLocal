APIM Policy Files
=================

Files:
- api-policy.xml: Global API-level policies (rate limiting + backend + error handling)
- get-claim-operation-policy.xml: Operation-specific policy for GET /claims/{id:int} (includes caching & throttle)
- post-summarize-operation-policy.xml: Operation-specific policy for POST /claims/{id:int}/summarize (stricter throttle, request size validation)

Suggested APIM Configuration Steps (CLI snippet):
------------------------------------------------
Assumes existing APIM instance, product requiring subscription key, and a backend named `claims-backend` pointing to the Container App FQDN.

1. Create backend (once):
   az apim backend create \
     --resource-group <rg> --service-name <apimName> \
     --url https://<container-app-fqdn> \
     --protocol http --name claims-backend

2. Import API (from OpenAPI once the app is reachable):
   az apim api import \
     --resource-group <rg> --service-name <apimName> \
     --path claims --api-id claims-api \
     --specification-url https://<container-app-fqdn>/swagger/v1/swagger.json

3. Apply global API policy:
   az apim api policy apply --resource-group <rg> --service-name <apimName> \
     --api-id claims-api --format rawxml --policy-file apim/api-policy.xml

4. Apply operation policies (operationIds must match imported OpenAPI):
   # Get claim (operationId: GetClaimById)
   az apim api operation policy apply --resource-group <rg> --service-name <apimName> \
     --api-id claims-api --operation-id GetClaimById --format rawxml --policy-file apim/get-claim-operation-policy.xml

   # Summarize claim (operationId: SummarizeClaim)
   az apim api operation policy apply --resource-group <rg> --service-name <apimName> \
     --api-id claims-api --operation-id SummarizeClaim --format rawxml --policy-file apim/post-summarize-operation-policy.xml

Notes:
- The route parameter is now constrained to an integer (`/claims/{id:int}`); make sure any API consumers and policies referencing path templates reflect this.
- Adjust rate limits for production scale.
- Consider per-subscription vs per-IP keys; here it falls back to IP if no subscription.
- Add additional policies (e.g., `set-header`, `cors`, `validate-jwt`) as needed.
