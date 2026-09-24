# owlpane-demo-workloads

**Cluster-side only.** Sample Deployments, Services, Ingress, Secrets (app placeholders), NetworkPolicies, CronJob, and optional cert-manager `Certificate`. The Owlpane **SaaS does not reference this chart** — the agent discovers whatever you install using `cluster.name` from [owlpane-agent](../owlpane-agent).

## What you get

| Object | Purpose in console |
|--------|-------------------|
| `demo-storefront`, `demo-api`, `demo-worker` | Workloads, Pods, Map/Network paths |
| `demo-flow-forwarder` | Synthetic `owlpane.flow.*` OTLP logs (Flows tab, Map **Network flows**) |
| `demo-ingress` | Ingress metrics + object snapshots (host/path → services) |
| `demo-app-credentials` Secret | Realistic pod env (agent never reads Secret data) |
| NetworkPolicies | Security + Network policy hints |
| CronJob `demo-nightly-sync` | Workloads tab variety |
| Helm annotations | Platform → Helm releases |

## Prerequisites

- [owlpane-agent](../owlpane-agent) installed with `clusterCollector.objectSnapshots=true` and `watchSecurityPosture=true` (see [values-demo-workloads.yaml](../owlpane-agent/values-demo-workloads.yaml)).
- An **Ingress controller** if `ingress.enabled=true` (e.g. ingress-nginx on kind).
- **cert-manager** only if `certManager.enabled=true` (and `watchCertManager=true` on the agent).

## Quick install

```bash
./scripts/install-demo-workloads.sh
```

Or manually:

```bash
helm upgrade --install owlpane-demo ./deploy/helm/owlpane-demo-workloads \
  -n owlpane-demo --create-namespace \
  --set namespace=owlpane-demo \
  --set ingress.host=demo.local \
  --set createNamespace=false
```

Use the **same `cluster.name`** you set on the owlpane-agent Helm chart in the console Kubernetes cluster picker.

## kind + ingress-nginx

```bash
INSTALL_INGRESS=true ./scripts/install-demo-workloads.sh
# Add to /etc/hosts: 127.0.0.1 demo.local
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80
curl -H 'Host: demo.local' http://127.0.0.1:8080/
```

## Demo databases (Infrastructure onboarding)

Enable in-cluster Postgres, MySQL, and MongoDB (dev credentials in chart values — **not** for production):

```bash
OWLPANE_DEMO_DATABASES=true ./scripts/install-demo-workloads.sh
```

Services are labeled `owlpane.io/demo-database` for discovery. Wire the agent without hardcoding endpoints in Owlpane SaaS:

```bash
OWLPANE_DEMO_NS=owlpane-demo OWLPANE_AGENT_NS=owlpane ./scripts/enable-demo-database-integrations.sh
```

Or one shot:

```bash
OWLPANE_DEMO_DATABASES=true OWLPANE_ENABLE_DB_INTEGRATIONS=true ./scripts/install-demo-workloads.sh
```

Then open **Infrastructure → Databases** in the console (same `cluster.name` as the agent).

## Optional values

| Value | Effect |
|-------|--------|
| `databases.postgres.enabled` / `mysql` / `mongodb` | Demo database Deployments + Services |
| `certManager.enabled=true` | Certificate CR (needs issuer) |
| `publicService.enabled=true` | LoadBalancer Service (exposure findings) |
| `chaos.unhealthyWorker=true` | CrashLoop worker for Events/alerts |
| `ingress.tls.enabled=true` | TLS stanza on Ingress (plain cert or cert-manager) |
| `flowForwarder.enabled=true` | OTLP log forwarder for Network → Flows (needs `otlpEndpoint`, `clusterName`, `owlpane-ingest` Secret) |

`./scripts/install-demo-workloads.sh` enables the flow forwarder when `OWLPANE_INGEST_KEY` is set and copies the ingest key into the demo namespace.

## Uninstall

```bash
helm uninstall owlpane-demo -n owlpane-demo
kubectl delete namespace owlpane-demo --ignore-not-found
```
