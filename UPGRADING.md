# Agent upgrades (J4 beta)

## Zero-downtime upgrade

1. Note current chart version: `helm list -n owlpane`
2. `helm upgrade owlpane-agent ./deploy/helm/owlpane-agent -n owlpane -f your-values.yaml`
3. DaemonSet rolls node agents one node at a time; cluster collector Deployment rolls with `maxUnavailable: 0` when configured.
4. Confirm new metrics in **Kubernetes** view within 5 minutes.

## Values to keep stable

- `endpoint` (ingest URL)
- `ingestKey` or secret reference
- `cluster.name`

Changing `cluster.name` creates a new cluster identity in the console.

## RBAC

Published scope is enforced in CI via `deploy/helm/test-rbac.sh`. Do not grant `secrets` or `configmaps` read without updating the threat model.
