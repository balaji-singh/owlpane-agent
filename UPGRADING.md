# Agent upgrades (J4 beta)

## Zero-downtime upgrade

1. Note current chart version: `helm list -n owlpane`
2. `helm upgrade owlpane oci://ghcr.io/balaji-singh/owlpane-agent --version <chart-version> -n owlpane -f your-values.yaml --reset-values`

### 0.1.3

- Pod labels use `app.kubernetes.io/name: owlpane` and `app.kubernetes.io/part-of: owlpane` (Owlpane SaaS brand). RBAC object names stay `owlpane-agent-<namespace>` so upgrades do not duplicate ClusterRoles.
- Recommended Helm **release name** is `owlpane` (chart package name remains `owlpane-agent` on OCI).
   (Pin the same `--version` you used at install; see `helm list -n owlpane`.)
3. DaemonSet rolls node agents one node at a time; cluster collector Deployment rolls with `maxUnavailable: 0` when configured.
4. Confirm new metrics in **Kubernetes** view within 5 minutes.

## Values to keep stable

- `endpoint` (ingest URL)
- `ingestKey` or secret reference
- `cluster.name`

Changing `cluster.name` creates a new cluster identity in the console.

## RBAC

Published scope is enforced in CI via `deploy/helm/test-rbac.sh`. Do not grant `secrets` or `configmaps` read without updating the threat model.
