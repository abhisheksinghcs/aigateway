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

## Guarded node auto-recovery

The infrastructure includes a disabled-by-default Logic App named
`litellm-aks-node-auto-recovery`. Enable it only after setting
`nodeVmssName` to the exact AKS node VMSS name and reviewing the support
evidence for the current incident.

When enabled:

1. Only the stateful `litellm-aks-node-not-ready` alert invokes the dedicated
   `litellm-aks-auto-recovery` action group. Compute-lifecycle and Resource
   Health alerts do not invoke recovery, which prevents the Logic App's own
   start operation from creating a trigger loop.
2. The workflow waits five minutes, then uses its system-assigned managed
   identity to query the configured VMSS.
3. It starts only instances that still report `PowerState/deallocated`.
4. It waits three minutes and verifies that the targeted instances left the
   deallocated state.
5. It makes exactly one start attempt. A failed verification marks the Logic
   App run failed; it does not retry indefinitely.

The managed identity receives a custom role scoped to the single VMSS. The role
allows only VMSS reads, VM-instance reads, and the VMSS start action. The
existing lifecycle alert records and emails the resulting start operation.

This is a POC availability safeguard, not a root-cause fix. It can mask or
interfere with intentional maintenance if enabled without operational review.
It was enabled with explicit approval after evidence preservation ended on
2026-10-13.

Activation requires both parameters:

```bicep
param enableNodeAutoRecovery = true
param nodeVmssName = '<exact AKS node VMSS name>'
```

Run subscription validation and what-if before activation. Do not apply the
full subscription template without reviewing unrelated existing-resource drift;
use the recovery-only `infra/node-auto-recovery.bicep` entry point when only
this workflow and its alert wiring should change.

The first approved run completed successfully:

- Trigger accepted: `2026-10-13T19:33:38Z`
- VMSS start action began after the safety delay: `19:38:39Z`
- Post-start verification completed: `19:42:53Z`
- Result: both VMSS instances Running, both Kubernetes nodes Ready, and no
  instance remained deallocated

LiteLLM required a Deployment rollout restart after infrastructure recovery
because its ReplicaSet remained in the earlier Workload Identity webhook
`FailedCreate` backoff. The workflow intentionally recovers compute only; it
does not mutate Kubernetes workloads.

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
| where Message has_any ("shutdown", "deallocat", "reimage", "repair", "upgrade", "NodeNotReady")
| project TimeGenerated, Category, Message
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

## Incident record: 2026-10-13

Both worker VMs deallocated again after the node-image upgrade and observability
deployment. This recurrence changes the root-cause assessment:

- VM 0: final heartbeat `17:07:21Z`; Resource Health reported
  `Stopping and deallocating` at `17:08:25Z`; Kubernetes marked it NotReady at
  `17:09:20Z`; the cloud controller observed `powerStatus="deallocating"` at
  `17:09:21Z`.
- VM 1: final heartbeat `17:08:43Z`; Resource Health reported the same event at
  `17:12:15Z`; Kubernetes marked it NotReady at `17:13:22Z`.
- Both Resource Health events use cause `UserInitiated` and state that an
  authorized user or process requested the deallocation.
- No VMSS `deallocate/action`, `powerOff/action`, or other initiating compute
  operation appears in the subscription Activity Log before the stops.
- AKS-managed manual-upgrade and instance-write operations began after both
  stops. Treat them as repair/reconciliation evidence, not the initiating
  action.
- The previous stale NodeImage hypothesis is no longer the leading explanation:
  both nodes were already on the current image when this incident occurred.

Use these correlation IDs in an Azure support case:

- VM 0: `846cacb9-9ced-4fb1-ad45-864c331f65bd`
- VM 1: `e8c66761-570b-47f9-903b-a8bc25ff5184`
- VMSS: `2fc2db1c-6c0b-4ed8-8207-088ce8b02531`

Ask Microsoft to identify the authenticated actor or internal Azure service
behind the `UserInitiated` events and explain why no initiating management
operation appears in the Activity Log.

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
