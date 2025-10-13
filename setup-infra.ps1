# PowerShell script to create Azure resources, Azure DevOps pipeline, and push the initial Docker image.

# --- Git Repository Initialization ---
if (-not (Test-Path .\.git)) {
    Write-Host "--- Initializing Git repository ---"
    git init
    git add .
    git commit -m "Initial commit"
    Write-Host "Git repository initialized and initial commit created."
} else {
    Write-Host "--- Git repository already exists. Skipping initialization. ---"
}

# --- Azure Resource Variables ---
$randomIdentifier = (Get-Random -Maximum 1000)
$resourceGroupName = "gen-ai-alx" + $randomIdentifier
$location = "eastus2"
$acrName = "claimlocalacr" + $randomIdentifier
$acaEnvName = "claimlocal-env"
$acaName = "claimlocal-app"
$apimName = "claimlocal-apim" + $randomIdentifier
$logAnalyticsWorkspaceName = "claimlocal-logs"

# --- Azure DevOps Variables ---
$devopsOrganizationUrl = "https://dev.azure.com/C0417467083442160311" # <-- UPDATE THIS
$devopsProjectName = "ClaimsGenAI" # <-- UPDATE THIS
$pipelineName = "ClaimLocal-CI-CD"
$variableGroupName = "ClaimLocal-Pipeline-Vars"
$serviceConnectionName = "AZURE_SUB"
$servicePrincipalName = "ClaimLocal-SP"
$repositoryName = "ClaimLocal" # Assumes your repo has the same name as the project
$repositoryType = "tfsgit" # Or 'github'
$branch = "main"
$yamlFilePath = "/pipelines/azure-pipelines.yml"

# --- Docker Image Variables ---
$imageName = "claimstatusapi"
$tag = "initial" # Using 'initial' for the first push

# --- Script ---

# Login to Azure (uncomment if you are not already logged in)
# az login

# Set the subscription (uncomment and set if you have multiple subscriptions)
# az account set --subscription "Your-Subscription-Id"

# --- 1. Create Azure Resources ---
Write-Host "--- Creating Azure Resources ---"

# Create Resource Group
Write-Host "Creating resource group: $resourceGroupName"
az group create --name $resourceGroupName --location $location

# Create Azure Container Registry (ACR)
Write-Host "Creating ACR: $acrName"
az acr create --resource-group $resourceGroupName --name $acrName --sku Basic --admin-enabled true
$acrLoginServer = (az acr show --name $acrName --resource-group $resourceGroupName --query "loginServer" --output tsv)

# Create Log Analytics Workspace
Write-Host "Creating Log Analytics Workspace: $logAnalyticsWorkspaceName"
az monitor log-analytics workspace create --resource-group $resourceGroupName --workspace-name $logAnalyticsWorkspaceName

# Get Log Analytics Workspace Client ID and Secret
$logAnalyticsWorkspaceClientId = (az monitor log-analytics workspace show --resource-group $resourceGroupName --workspace-name $logAnalyticsWorkspaceName --query "customerId" --output tsv)
$logAnalyticsWorkspaceClientSecret = (az monitor log-analytics workspace get-shared-keys --resource-group $resourceGroupName --workspace-name $logAnalyticsWorkspaceName --query "primarySharedKey" --output tsv)

# Create Azure Container Apps Environment
Write-Host "Creating ACA Environment: $acaEnvName"
az containerapp env create --name $acaEnvName --resource-group $resourceGroupName --location $location --logs-workspace-id $logAnalyticsWorkspaceClientId --logs-workspace-key $logAnalyticsWorkspaceClientSecret

# Create API Management (APIM) instance
Write-Host "Creating APIM instance: $apimName"
az apim create --name $apimName --resource-group $resourceGroupName --location $location --publisher-email "contact@example.com" --publisher-name "ClaimLocal" --sku-name Consumption

Write-Host "Azure resources created successfully."
Write-Host "ACR Name: $acrName"

# --- 2. Create Azure DevOps Pipeline ---
Write-Host "`n--- Creating Azure DevOps Pipeline ---"

# Install Azure DevOps extension
Write-Host "Installing Azure DevOps extension..."
az extension add --name azure-devops

# Login to Azure DevOps (requires a PAT or interactive login)
Write-Host "Please ensure you are logged into Azure DevOps."
Write-Host "You can login using 'az devops login' or by setting the AZURE_DEVOPS_EXT_PAT environment variable."
az devops configure --defaults organization=$devopsOrganizationUrl project=$devopsProjectName

# Create the Azure DevOps repository if it does not exist
$repo = az repos list --query "[?name=='$repositoryName']" | ConvertFrom-Json
if ($repo.Count -eq 0) {
    Write-Host "Creating Azure DevOps repository '$repositoryName'..."
    az repos create --name $repositoryName
}

# Get the remote URL
$remoteUrl = (az repos show --repository $repositoryName --query "remoteUrl" --output tsv)

# Add or update the remote for the local git repository
if (-not (git remote | findstr "origin")) {
    Write-Host "Adding remote 'origin'..."
    git remote add origin $remoteUrl
} else {
    Write-Host "Remote 'origin' already exists. Setting URL..."
    git remote set-url origin $remoteUrl
}

# Push the code to the new repository
Write-Host "Pushing code to Azure DevOps..."
git push -u origin --all

# Create the pipeline
Write-Host "Creating pipeline '$pipelineName'..."
az pipelines create `
  --name $pipelineName `
  --repository $repositoryName `
  --repository-type $repositoryType `
  --branch $branch `
  --yml-path $yamlFilePath `
  --skip-first-run true

# --- 3. Build and Push Docker Image ---
Write-Host "`n--- Building and Pushing Docker Image ---"

# Login to ACR
Write-Host "Logging in to ACR: $acrName"
az acr login --name $acrName

# Build the Docker image
Write-Host "Building Docker image: ${imageName}:${tag}"
docker build -t "${imageName}:${tag}" .

# Tag the image for ACR
$acrImageFullName = "$acrLoginServer/${imageName}:${tag}"
Write-Host "Tagging image as: $acrImageFullName"
docker tag "${imageName}:${tag}" $acrImageFullName

# Push the image to ACR
Write-Host "Pushing image to ACR..."
docker push $acrImageFullName

# --- 4. Create Azure DevOps Variable Group ---
Write-Host "`n--- Creating Azure DevOps Variable Group ---"
$vg = az pipelines variable-group list --query "[?name=='$variableGroupName']" | ConvertFrom-Json
if ($vg.Count -eq 0) {
    Write-Host "Creating variable group '$variableGroupName'..."
    az pipelines variable-group create --name $variableGroupName --authorize true --variables `
      ACR_NAME=$acrName `
      ACR_LOGIN_SERVER=$acrLoginServer `
      ACA_ENV=$acaEnvName `
      ACA_NAME=$acaName `
      RESOURCE_GROUP=$resourceGroupName `
      APIM_NAME=$apimName `
      LOCATION=$location `
      IMAGE_REPO=$imageName `
      OPENAI_ENDPOINT="YOUR_OPENAI_ENDPOINT" `
      OPENAI_DEPLOYMENT="YOUR_OPENAI_DEPLOYMENT"
} else {
    Write-Host "Variable group '$variableGroupName' already exists. Skipping creation."
}

Write-Host "Variable group created. IMPORTANT: Go to the Azure DevOps UI, open the '$variableGroupName' group, and mark 'OPENAI_ENDPOINT' and 'OPENAI_DEPLOYMENT' as secrets."

# --- 5. Create Azure DevOps Service Connection ---
Write-Host "`n--- Creating Azure DevOps Service Connection ---"

# Get current subscription details
$subscriptionId = (az account show --query "id" --output tsv)
$subscriptionName = (az account show --query "name" --output tsv)
$tenantId = (az account show --query "tenantId" --output tsv)

# Create Service Principal
Write-Host "Creating Service Principal '$servicePrincipalName' with 'Contributor' role on the current subscription..."
$spOutput = (az ad sp create-for-rbac --name $servicePrincipalName --role "Contributor" --scopes "/subscriptions/$subscriptionId" | ConvertFrom-Json)
$servicePrincipalId = $spOutput.appId
$servicePrincipalPassword = $spOutput.password

# Create the Azure DevOps service connection
Write-Host "Creating service connection '$serviceConnectionName' in Azure DevOps..."
$env:AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY = $servicePrincipalPassword
az devops service-endpoint azurerm create --azure-rm-service-principal-id $servicePrincipalId `
  --azure-rm-subscription-id $subscriptionId `
  --azure-rm-subscription-name "$subscriptionName" `
  --azure-rm-tenant-id $tenantId `
  --name $serviceConnectionName



Write-Host "`n--- ALL SETUP COMPLETE ---"
Write-Host "The entire environment and pipeline have been configured."
Write-Host "You can now go to Azure DevOps and run the '$pipelineName' pipeline."
