# Observability

This folder provides quick-start guidance to enable and query observability for the Claim Status API stack.

## Components
- **API Management (APIM) Analytics**: Native metrics (calls, latency, failures) and custom logs exportable to Log Analytics.
- **Azure Container Apps (ACA) / Container Insights**: Container stdout/stderr, system logs, revision metrics.
- **Log Analytics Workspace (LAW)**: Central query surface for KQL.
- **(Optional) Application Insights**: Can be added for distributed tracing if deeper telemetry is needed.

## Enable Diagnostics & Logging

### 1. APIM → Log Analytics
Use Azure Portal or CLI to send gateway logs & metrics to an existing Log Analytics workspace.

```bash
APIM_NAME=<apim>
RG=<resource-group>
WORKSPACE_ID=$(az monitor log-analytics workspace show -g $RG -n <workspace> --query customerId -o tsv)
WORKSPACE_RG=$RG
WORKSPACE_NAME=<workspace>

# Get workspace resource ID
WORKSPACE_RES_ID=$(az monitor log-analytics workspace show -g $WORKSPACE_RG -n $WORKSPACE_NAME --query id -o tsv)

# Enable diagnostic settings for APIM (gateway logs & metrics)
az monitor diagnostic-settings create \
  --name apim-to-law \
  --resource $(az apim show -g $RG -n $APIM_NAME --query id -o tsv) \
  --workspace $WORKSPACE_RES_ID \
  --logs '[{"category":"GatewayLogs","enabled":true},{"category":"WebSocketConnectionLogs","enabled":false}]' \
  --metrics '[{"category":"AllMetrics","enabled":true}]'
```

### 2. Container Apps → Log Analytics
If the Container Apps environment was created with a Log Analytics workspace, logs already flow. To confirm:
```bash
az containerapp env show -g $RG -n <aca-env> --query "properties.appLogsConfiguration.logAnalyticsConfiguration.customerId"
```
If you need to connect it post-creation (Bicep example uses parameter):

```bicep
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: logAnalyticsName
  resourceGroup: rgName
}

resource acaEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: acaEnvName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: listKeys(logAnalytics.id, '2020-08-01').primarySharedKey
      }
    }
  }
}
```
> NOTE: For existing env you can't update sharedKey inline; recreate or use CLI `az containerapp env update`.

### 3. Optional: Application Insights
```bash
az monitor app-insights component create \
  -g $RG -a <appinsights-name> -l <region>
```
Then set connection string as a secret/env var in ACA.

---
## Sample KQL Queries
See `kql/queries.kql` for a consolidated list. Highlights below.

### High Latency (APIM Gateway)
```kql
AzureDiagnostics
| where Category == "GatewayLogs"
| extend latencyMs = toint(properties.response_processing_time) + toint(properties.backend_time) + toint(properties.client_time)
| where latencyMs > 1000
| project TimeGenerated, operationName, latencyMs, properties.backend_time, properties.client_time, backendStatusCode=properties.backend_status_code
| order by latencyMs desc
```

### Top Failing Operations (APIM)
```kql
AzureDiagnostics
| where Category == "GatewayLogs"
| summarize failures = countif(toint(properties.backend_status_code) >= 500), total = count() by operationName
| extend failureRate = failures * 100.0 / total
| where total > 20 and failureRate > 5
| order by failureRate desc
```

### Container App Recent Errors
```kql
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(1h)
| where Log_s contains "fail" or Log_s contains "error"
| project TimeGenerated, RevisionName_s, ContainerName_s, Log_s
| order by TimeGenerated desc
```

### Summarization Endpoint Latency (App Logs)
If logs include structured timing (add logging if not yet):
```kql
ContainerAppConsoleLogs_CL
| where Log_s contains "Request completed" and Log_s contains "/claims/" 
| extend durationMs = toint(extract("duration=(\\d+)", 1, Log_s))
| summarize p95=percentile(durationMs,95), p99=percentile(durationMs,99), avg=avg(durationMs) by bin(TimeGenerated, 15m)
| order by TimeGenerated desc
```

### Vulnerability Gate History (Artifact JSON Ingestion)
If you choose to ingest `vulns.json` into a custom table later:
```kql
VulnGate_CL
| summarize any(High_d), any(Critical_d) by ImageTag_s, TimeGenerated
| order by TimeGenerated desc
```

---
## Alerting Examples

### Alert: High APIM Failure Rate
Metric-based or Log Alert: failureRate > 5% over 5m for an operation.

### Alert: Container App Error Spike
Log Alert on query:
```kql
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(5m)
| where Log_s contains "error"
| summarize count() > 50
```

### Alert: P95 Latency Above 2s
```kql
ContainerAppConsoleLogs_CL
| where Log_s contains "Request completed"
| extend durationMs = toint(extract("duration=(\\d+)", 1, Log_s))
| summarize p95=percentile(durationMs,95) by bin(TimeGenerated, 5m)
| where p95 > 2000
```

---
## Next Steps
- Add structured logging (JSON) for easier parsing.
- Export APIM logs to storage for long-term retention (diagnostic settings multi-sink).
- Add a dashboard (Workbook) combining latency, errors, request volume, vulnerability counts.
- Add distributed tracing (App Insights) if you introduce additional microservices.

---
## References
- APIM Diagnostics Categories: https://learn.microsoft.com/azure/api-management/api-management-howto-use-azure-monitor
- Container Apps Logging: https://learn.microsoft.com/azure/container-apps/monitor
- KQL Basics: https://learn.microsoft.com/azure/data-explorer/kusto/query
