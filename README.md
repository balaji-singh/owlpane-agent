# Owlpane Kubernetes agent

Helm chart for customer clusters (OpenTelemetry collectors → your Owlpane ingest).

```bash
helm upgrade --install owlpane . -n owlpane --create-namespace \
  --set endpoint=https://ingest.example.com --set cluster.name=my-cluster
```

Optional demo workloads: `demo-workloads/`.

Split from the [Owlpane monorepo](https://github.com/balaji-singh/owlpane).
