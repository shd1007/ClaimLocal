# Variables
$resourceGroupName = "gen-ai-alx"
$location = "eastus2"
# Append a random string to make the ACR name unique
$acrName = "claimlocalacr" + (Get-Random -Maximum 1000)
$imageName = "claimstatusapi"
$tag = "latest"

# Create Resource Group if it doesn't exist
if ((az group exists --name $resourceGroupName) -eq "false") {
    Write-Host "Creating resource group: $resourceGroupName"
    az group create --name $resourceGroupName --location $location
} else {
    Write-Host "Resource group '$resourceGroupName' already exists."
}

# Create ACR if it doesn't exist
if ((az acr show --name $acrName --resource-group $resourceGroupName) -eq $null) {
    Write-Host "Creating ACR: $acrName"
    az acr create --resource-group $resourceGroupName --name $acrName --sku Basic --admin-enabled true
} else {
    Write-Host "ACR '$acrName' already exists."
}

# Get the ACR login server
$acrLoginServer = (az acr show --name $acrName --resource-group $resourceGroupName --query "loginServer" --output tsv)

# Login to ACR
az acr login --name $acrName

# Build the Docker image
docker build -t "${imageName}:${tag}" .

# Tag the image for ACR
docker tag "${imageName}:${tag}" "$acrLoginServer/${imageName}:${tag}"

# Push the image to ACR
docker push "$acrLoginServer/${imageName}:${tag}"

Write-Host "Image pushed to $acrLoginServer/${imageName}:${tag}"