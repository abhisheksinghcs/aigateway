# AKS deallocation observability

This deployment captures the Azure and Kubernetes evidence needed to investigate
unexpected AKS node deallocation.

## Data collection

The existing Log Analytics workspace receives:

- Container Insights node, pod, event, inventory, and container logs through the
  `MSCI-<region>-<cluster>` data collection rule.
- AKS control-plane logs through the `aks-control-plane` diagnostic setting:
  - `kube-apiserver`
  - `kube-audit-admin`
  - `kube-controller-manager`
  - `kube-scheduler`
  - `cluster-autoscaler`
  - `cloud-controller-manager`
  - `guard`
  - `AllMetrics`
- Subscription Activity Log categories through
  `litellm-subscription-activity`:
  - Administrative
  - Security
  - ServiceHealth
  - Alert
  - Recommendation
  - Policy
  - Autoscale
  - ResourceHealth

Full `kube-audit` logging is intentionally excluded because its volume and cost
are substantially higher. `kube-audit-admin` records control-plane write
operations needed for this investigation.

## Alerts

The `litellm-aks-operations` action group sends common-schema email alerts to
the deployment owner.

| Alert | Trigger |
|---|---|
| `litellm-aks-node-not-ready` | Fewer than two nodes report through Container Insights within ten minutes, or a reporting node is not `Ready` |
| `litellm-aks-node-compute-lifecycle` | VMSS or VM instance write, deallocate, power-off, redeploy, reimage, restart, or delete operation in the AKS managed resource group |
| `litellm-aks-node-resource-health` | AKS-managed compute changes to `Degraded`, `Unavailable`, or `Unknown` resource health |

The missing-telemetry condition is important: a deallocated node cannot report
its own `NotReady` state.

## Investigation queries

Run these in the Log Analytics workspace after an alert.

### Node heartbeat timeline

```kusto
KubeNodeInventory
| where TimeGenerated > ago(24h)
| summarize LastSeen=max(TimeGenerated), Status=any(Status) by Computer
| order by LastSeen asc
```

### Kubernetes node events

```kusto
KubeEvents
| where TimeGenerated > ago(24h)
| where Name startswith "aks-system-"
| project TimeGenerated, Name, Reason, Message, SourceComponent
| order by TimeGenerated asc
```

### AKS control-plane evidence

```kusto
AKSControlPlane
| where TimeGenerated > ago(24h)
| where log_s has_any ("shutdown", "deallocat", "reimage", "repair", "upgrade", "NodeNotReady")
| project TimeGenerated, Category, log_s
| order by TimeGenerated asc
```

### Administrative writes around the outage

```kusto
AzureActivity
| where TimeGenerated > ago(24h)
| where ResourceGroup startswith "MC_rg-litellm-gateway-demo"
| where OperationNameValue has_any ("virtualMachineScaleSets", "managedClusters")
| project TimeGenerated, OperationNameValue, ActivityStatusValue, Caller, CorrelationId, ResourceId
| order by TimeGenerated asc
```

### Resource Health transitions

```kusto
AzureActivity
| where TimeGenerated > ago(24h)
| where CategoryValue == "ResourceHealth"
| project TimeGenerated, ResourceId, Properties
| order by TimeGenerated asc
```

Use the `CorrelationId` from Activity Log records to group AKS repair, upgrade,
VMSS write, reimage, and delete operations into one control-plane workflow.

## Validation

After deployment, confirm:

1. Both nodes have recent `Ready` records in `KubeNodeInventory`.
2. `AKSControlPlane` and `AKSAuditAdmin` contain current records.
3. All three alert rules are enabled and reference
   `litellm-aks-operations`.
4. The action-group email receiver reports `Enabled`.

The Azure CLI synthetic notification command can reject email test payloads
with `There are no valid receivers in the request` even when the stored action
group receiver is enabled. Treat an accepted synthetic notification or the
first real alert email as delivery proof; do not infer delivery from resource
provisioning alone.
