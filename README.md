# Claim Status API

Containerized .NET 8 minimal API providing:
- `GET /claims/{id}` – Returns static claim data from `mocks/claims.json`.
- `POST /claims/{id}/summarize` – Loads claim notes from `mocks/notes.json`, calls Azure OpenAI (Chat Completions REST) to produce: `summary`, `customerSummary`, `adjusterSummary`, `nextStep`.

Fronted by Azure API Management (APIM), deployed to Azure Container Apps (ACA), automated via Azure DevOps pipeline.

---
## Quick Start (Local)
1. Prereqs: .NET 8 SDK, Docker (optional), Azure OpenAI resource (or skip summarization test).
2. Restore & run:
   ```bash
   dotnet build
   dotnet run --project src/ClaimStatusApi
   ```
3. Swagger UI (dev): http://localhost:5000/swagger (actual port from console).
4. Sample calls:
   ```bash
   curl http://localhost:5000/claims/CLM-1001
   curl -X POST http://localhost:5000/claims/CLM-1001/summarize
   ```
5. To enable real summarization set env vars (or use secrets in container):
   - `OpenAI__Endpoint=https://<your-openai>.openai.azure.com`
   - `OpenAI__Deployment=<model-deployment-name>`

If unreachable or unauthorized, API returns fallback text.

---
## Run in Docker
```bash
docker build -t claimstatusapi:dev .
docker run -p 8080:8080 -e OpenAI__Endpoint=... -e OpenAI__Deployment=... claimstatusapi:dev
curl http://localhost:8080/claims/CLM-1002
```

---
## Repository Structure
```
?? src/ClaimStatusApi/           # .NET 8 minimal API source
?  ?? Program.cs                 # Endpoint mappings
?  ?? Services/                  # Repository + Summarization service (REST to Azure OpenAI)
?  ?? Models/                    # DTO / record types
?  ?? appsettings.json           # Default config (placeholder OpenAI values)
?  ?? ClaimStatusApi.csproj
?? mocks/
?  ?? claims.json                # 8 mock claim records
?  ?? notes.json                 # Notes per claim used for summarization
?? apim/
?  ?? api-policy.xml             # Global API-level policies
?  ?? get-claim-operation-policy.xml
?  ?? post-summarize-operation-policy.xml
?  ?? README.md                  # How to apply policies
?? iac/
?  ?? bicep/main.bicep           # Bicep deployment
?  ?? terraform/main.tf          # Terraform alternative
?  ?? README.md
?? pipelines/azure-pipelines.yml # Azure DevOps CI/CD (build, push, vuln gate, deploy)
?? Dockerfile                    # Multi-stage container image
?? README.md                     # This file
```

---
## Azure DevOps Pipeline
File: `pipelines/azure-pipelines.yml`
Stages:
1. Build (.NET build + publish artifact)
2. Container (docker build/push, ACR vulnerability gate using Defender scan results)
3. Deploy (ACA create/update + APIM placeholder)

Required Variables / Pipeline Variables:
```
ACR_NAME, ACR_LOGIN_SERVER, IMAGE_REPO, RESOURCE_GROUP, LOCATION,
ACA_ENV, ACA_NAME, OPENAI_ENDPOINT, OPENAI_DEPLOYMENT, APIM_NAME,
VULN_FAIL_SEVERITY (High|Critical)
```
Service Connection: `AZURE_SUB` (ARM connection).

Gate Logic: Fails if Defender scan reports >= configured severity (High also fails on Critical).

Additions you can extend:
- SBOM: Add `dotnet build /p:GeneratePackageGraph=true` or CycloneDX task.
- SAST/IaC: Integrate Defender for DevOps or CodeQL step.
- Key Vault: Replace inline env with `az containerapp secret set --secrets keyvault-ref=...` (or managed identity + Key Vault references).

---
## Infrastructure as Code
Choose Bicep or Terraform (they provision: Log Analytics, ACA Env, Container App, APIM, optional ACR).

Bicep deploy:
```bash
az deployment group create \
  -g <rg> \
  -f iac/bicep/main.bicep \
  -p containerImage="<acr>.azurecr.io/claimstatusapi:<tag>" \
     openAiEndpoint="https://<openai>.openai.azure.com" \
     openAiDeployment="gpt-4o-mini"
```

Terraform deploy:
```bash
cd iac/terraform
terraform init
terraform apply -var resource_group_name=<rg> \
  -var container_image=<acr>.azurecr.io/claimstatusapi:<tag> \
  -var openai_endpoint=https://<openai>.openai.azure.com \
  -var openai_deployment=gpt-4o-mini
```

Post-deploy:
1. Import OpenAPI into APIM from running Container App Swagger.
2. Apply policies in `apim/` (see apim/README.md commands).
3. Grant Container App system-assigned managed identity role `Cognitive Services User` on the Azure OpenAI resource (if using AAD auth flow; current implementation uses managed identity to fetch token).

---
## APIM Policies Overview
- Global `api-policy.xml`: rate limit (100 calls/min), backend routing, unified error body.
- GET policy: additional rate limit (30/min) + 30s cache.
- POST summarize policy: tighter rate limit (10/min) + payload size validation.
Adjust counters or add JWT validation (`validate-jwt`) for production.

---
## Summarization Flow
1. Repository loads `claims.json` / `notes.json` (cached in memory).
2. Summarization service builds structured system & user prompts.
3. Calls Azure OpenAI Chat Completions REST endpoint with bearer token obtained via `DefaultAzureCredential` (Managed Identity when deployed).
4. Attempts to parse JSON from model output. On failure returns raw content in all fields.
5. Fallback: On error returns static "Summarization unavailable" response.

System Prompt Used:
```
You are an insurance claims assistant. Create: (1) a concise general summary (2) a simple customer-facing summary (3) a more detailed adjuster summary with any missing info callouts (4) a single recommended next step phrase. Return JSON with keys summary, customerSummary, adjusterSummary, nextStep.
```
User Prompt Template:
```
Claim: {Id} Type: {Type} Status: {Status} LossDate: {LossDate} Notes:\n- author: text ...
```
Modify prompts by updating `OpenAiSummarizationService`.

---
## Observability
Log Analytics collects console logs. Sample KQL (create an `observability/` folder if needed):
```
// High latency ( > 1000 ms ) requests (if custom metrics added later)
AppTraces | where Message contains "Request completed" and toint(Extract("duration=(\\d+)", 1, Message)) > 1000

// Error logs
AppTraces | where SeverityLevel >= 3
```
APIM Analytics: use Azure Portal (Latency, Failure %, Usage). Export or pin dashboards; apply rate-limits to protect OpenAI cost.

Add structured logging: extend Serilog sinks (eg. Seq, Application Insights) if required.

---
## Security Notes
- Defender for Cloud auto image scan after push to ACR triggers vulnerability gate.
- Rate limiting + subscription key in APIM to protect backend & cost.
- Use Managed Identity for Azure OpenAI (avoid API keys).
- Optionally add WAF / Private endpoints + Key Vault for secrets.

---
## Testing
Currently no unit tests. Suggested quick additions:
- Repository tests loading JSON.
- Summarization service test with mocked HTTP handler (returning fixed JSON).
- Contract tests for endpoints using `WebApplicationFactory`.

Example `dotnet new xunit -o tests` then reference project & add to solution.

---
## Common Issues
| Problem | Cause | Fix |
|---------|-------|-----|
| 500 on summarize | OpenAI auth/endpoint misconfigured | Verify env vars & managed identity role |
| Empty summaries | Model returned non-JSON content | Adjust prompt or add output parser | 
| Vulnerability gate fails | High/Critical findings | Patch / rebuild, raise threshold only as last resort |

---
## Extensibility Ideas
- Add pagination & list endpoint (`GET /claims`).
- Add authentication (JWT + `validate-jwt` APIM policy).
- Add caching layer (Redis) or ETag for claim retrieval.
- Add cost logging per summarization request.
- Introduce background enrichment worker.

---
## License
(Add appropriate license file if distributing.)

---
## Generated With GenAI Assistance
Prompts leveraged to create: API endpoints, OpenAI prompt text, pipeline YAML, APIM policies, IaC templates, README skeleton, mock data expansions.

