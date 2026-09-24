# owlpane-agent

Sends Kubernetes node, pod, container and cluster telemetry to your Owlpane ingest gateway using
OpenTelemetry. Status: **alpha**. Tested on a real (kind) cluster: pods run, kubelet and cluster-state
metrics arrive with `k8s.cluster.name` and your project key.

## Install

```bash
kubectl create namespace owlpane
kubectl -n owlpane create secret generic owlpane-ingest --from-literal=key=owl_ing_YOUR_KEY
helm install owlpane-agent ./deploy/helm/owlpane-agent -n owlpane \
  --set endpoint=https://ingest.example.com --set cluster.name=production-eu
```

## What it runs

| Piece | Kind | Does |
|---|---|---|
| cluster collector | Deployment (1) | workload state, HorizontalPodAutoscaler gauges (`k8s.hpa.current_replicas`, `desired_replicas`, `min_replicas`, `max_replicas`), PersistentVolumeClaim capacity and phase, restarts, node conditions, Kubernetes events, and optional Service/Ingress object snapshots for routing in the console |
| node agent | DaemonSet | node, pod, container, and volume metrics from the kubelet (`k8s.volume.capacity`, `k8s.node.filesystem.usage`); an OTLP receiver applications can send to; optional container logs |

## What it is allowed to do

Read-only access to nodes, namespaces, pods, services, endpoints, ingresses, PVCs, workloads, jobs, autoscalers, events, cert-manager Certificates, and Gateway API Gateways/HTTPRoutes (when enabled in values).
**No access to Secrets or ConfigMaps, no exec, no log API, no write verbs.** `./test-rbac.sh` fails
the build if that ever changes. Containers run non-root (except when log collection is enabled, which
must read the node's log directory), with a read-only filesystem and all capabilities dropped.

## Privacy defaults

Pod labels and annotations are **not** attached unless you list them, and container logs are **off**
until you enable them (`logs.enabled=true`), because both often contain personal data. The ingest key
lives in a Secret, never in the chart.

Console: **Infrastructure → Databases** (inventory + onboarding wizard) and **Settings → Integrations** (Helm generator). See [database onboarding](../../../docs/ops/database-onboarding.md).

## Database integrations (Postgres, Redis)

Off by default. Enable a small extra collector that reads database health with a read-only account and sends it as
metrics under the service name you choose:

```yaml
integrations:
  enabled: true
  postgres:
    - name: orders-db
      endpoint: orders-db.default.svc:5432
      secret: { name: orders-db-monitor, userKey: username, passwordKey: password }
  redis:
    - name: session-cache
      endpoint: session-cache.default.svc:6379
      secret: { name: session-cache-monitor, passwordKey: password }
```

Create the Secrets yourself (`kubectl create secret generic ...`); the chart never holds a credential. For Postgres run
`GRANT pg_monitor TO owlpane;`; for Redis an ACL user limited to `+info +ping` is enough. The pod has no Kubernetes API
access, a read-only root filesystem and no extra capabilities. `test-rbac.sh` renders this configuration and has the real
collector validate it. Verified against throwaway Postgres 16 and Redis 7 containers: 12 Postgres and 26 Redis metrics arrived under the configured service names. Not yet verified: a Postgres over TLS, or Redis with ACL credentials.

## Network collector

Off by default. When `networkCollector.enabled=true` the chart runs a DaemonSet that reads the node's `/proc/net/tcp` and posts `owlpane.flow.*` logs (`source=conntrack`). It records endpoints and a byte placeholder, not packet payloads. Optional `networkCollector.beyla.enabled=true` adds Grafana Beyla for eBPF network **metrics** (privileged). That container does not decrypt TLS.

Namespace capture filters are not applied by the conntrack loop (it is node-scoped). Port filters are `networkCollector.captureFilters.ports`.

## Uninstall

`helm uninstall owlpane-agent -n owlpane` removes everything the chart created.
