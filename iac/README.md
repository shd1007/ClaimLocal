Infrastructure as Code
======================

Contents:
- bicep/main.bicep : Single file deployment for Container App + APIM + Logging (optional ACR)
- terraform/main.tf : Terraform variant using azurerm + azapi providers

Bicep Deployment Example:
-------------------------
az deployment group create \
  --resource-group <rg> \
  --template-file iac/bicep/main.bicep \
  --parameters containerImage="myregistry.azurecr.io/claimstatusapi:1" openAiEndpoint="https://<openai>.openai.azure.com" openAiDeployment="gpt-4o-mini"

Terraform Deployment Example:
-----------------------------
terraform init iac/terraform
terraform apply -var "resource_group_name=<rg>" \
  -var "container_image=myregistry.azurecr.io/claimstatusapi:1" \
  -var "openai_endpoint=https://<openai>.openai.azure.com" \
  -var "openai_deployment=gpt-4o-mini"

Post-Deploy Steps:
------------------
1. Import OpenAPI spec into APIM (pipeline or CLI) and attach policies from apim/ directory.
2. Assign necessary RBAC if Container App managed identity needs Azure OpenAI access (Cognitive Services User role at resource scope).
3. Configure custom domains / TLS for APIM if needed.
4. Validate logging in Log Analytics: query ContainerAppConsoleLogs.
