#!/usr/bin/env bash
# Fails if the agent's ClusterRole ever gains a write verb or access to secrets/configmaps/exec/logs.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd ../.. && pwd)"
PYTHON=python3
if ! python3 -c "import yaml" 2>/dev/null; then
  VENV="$ROOT/scripts/.helm-test-venv"
  if [[ ! -x "$VENV/bin/python3" ]]; then
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q pyyaml
  fi
  PYTHON="$VENV/bin/python3"
fi
helm lint owlpane-agent --set endpoint=https://ingest.example.com --set cluster.name=t >/dev/null
helm lint owlpane-api --set existingSecret=owlpane-api-env --set image.tag=ci >/dev/null
helm lint owlpane-ingest --set existingSecret=owlpane-ingest-env --set image.tag=ci >/dev/null
OUT="$(mktemp)"; trap 'rm -f "$OUT"' EXIT
helm template t owlpane-agent -n owlpane --set endpoint=https://ingest.example.com --set cluster.name=t --set logs.enabled=true --set networkPolicy.enabled=true --set integrations.enabled=true --set 'integrations.redis[0].name=c' --set 'integrations.redis[0].endpoint=c:6379' > "$OUT"
"$PYTHON" - "$OUT" <<'PY'
import sys, yaml
docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
roles = [d for d in docs if d["kind"] in ("ClusterRole", "Role")]
assert roles, "no role rendered"
bad = {"secrets", "configmaps", "pods/exec", "pods/log", "pods/attach", "serviceaccounts", "*"}
for r in roles:
    for rule in r["rules"]:
        assert set(rule["verbs"]) <= {"get", "list", "watch"}, f"write verb in {rule}"
        assert not (set(rule["resources"]) & bad), f"forbidden resource in {rule}"
        assert "*" not in rule["apiGroups"], "wildcard api group"
for d in docs:
    if d["kind"] in ("DaemonSet", "Deployment"):
        name = d["metadata"]["name"]
        for c in d["spec"]["template"]["spec"]["containers"]:
            sc = c["securityContext"]
            assert sc["allowPrivilegeEscalation"] is False and sc["readOnlyRootFilesystem"] is True and sc["capabilities"]["drop"] == ["ALL"], f"weak container security in {name}"
        assert "hostNetwork" not in d["spec"]["template"]["spec"], "hostNetwork requested"
print("PASS: read-only RBAC, no secrets access, hardened containers")
PY

# Edge redaction (transform/redact, the count connector that proves it ran) is on by default; a
# regression here would mean personal data and secrets leave the customer's network unredacted.
"$PYTHON" - "$OUT" <<'PY'
import sys, yaml
docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
cm = next(d for d in docs if d["kind"] == "ConfigMap" and d["metadata"]["name"] == "owlpane-node-agent")
cfg = yaml.safe_load(cm["data"]["config.yaml"])
assert "transform/redact" in cfg["processors"], "redaction is on by default but transform/redact is missing"
assert "transform/scrub_urls" in cfg["processors"], "redaction is on by default but transform/scrub_urls is missing"
assert "count" in cfg.get("connectors", {}), "the redaction-counter connector is missing"
for name in ("traces", "logs"):
    pl = cfg["service"]["pipelines"][name]
    assert "transform/redact" in pl["processors"], f"{name} pipeline does not run transform/redact"
    assert "count" in pl["exporters"], f"{name} pipeline does not feed the redaction counter"
assert cfg["service"]["pipelines"]["metrics/redaction"]["receivers"] == ["count"], "no metrics/redaction pipeline reading the counter"
print("PASS: edge redaction (transform/redact + the redaction-counter metric) is on by default")
PY

# The collector itself must accept the rendered configuration, so a setting the pinned version does
# not know is caught here and not by a crash-looping pod. Needs docker (skipped when it is absent).
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP" "$OUT"' EXIT
  IMG="otel/opentelemetry-collector-contrib:$(grep -E '^appVersion' owlpane-agent/Chart.yaml | tr -d '" ' | cut -d: -f2)"
  cat > "$TMP/integrations.yaml" <<'YAML'
integrations:
  enabled: true
  postgres:
    - { name: orders-db, endpoint: "orders-db.default.svc:5432", databases: [orders], tls: { insecure: true }, secret: { name: orders-db-monitor } }
  redis:
    - { name: session-cache, endpoint: "session-cache.default.svc:6379", secret: { name: session-cache-monitor } }
    - { name: open-cache, endpoint: "open-cache.default.svc:6379" }
  mysql:
    - { name: billing-db, endpoint: "mysql.default.svc:3306", secret: { name: mysql-monitor } }
  mongodb:
    - { name: events-db, endpoint: "mongo.default.svc:27017", secret: { name: mongo-monitor } }
  kafka:
    - { name: events-bus, brokers: ["kafka.default.svc:9092"] }
  rabbitmq:
    - { name: jobs-queue, endpoint: "http://rabbitmq.default.svc:15672", secret: { name: rabbit-monitor } }
  nginx:
    - { name: edge-proxy, endpoint: "http://nginx.default.svc/status" }
  cloudScrapes:
    - { name: aws-metrics, provider: aws, targets: ["yace.default.svc:5000"] }
YAML
  helm template t owlpane-agent -n owlpane --set endpoint=https://ingest.example.com --set cluster.name=t --set logs.enabled=true --set nodeAgent.kubeletInsecureSkipVerify=true -f "$TMP/integrations.yaml" > "$TMP/all.yaml"
  "$PYTHON" - "$TMP" <<'PY'
import sys, yaml
tmp = sys.argv[1]
for d in yaml.safe_load_all(open(f"{tmp}/all.yaml")):
    if d and d["kind"] == "ConfigMap" and "config.yaml" in d.get("data", {}):
        open(f"{tmp}/{d['metadata']['name']}.yaml", "w").write(d["data"]["config.yaml"])
PY
  # Stand-ins for the files Kubernetes mounts into a pod, so the receivers can start up.
  openssl req -x509 -newkey rsa:2048 -nodes -keyout /dev/null -out "$TMP/ca.crt" -subj /CN=test -days 1 >/dev/null 2>&1
  echo token > "$TMP/token"
  SA=/var/run/secrets/kubernetes.io/serviceaccount
  for f in "$TMP"/owlpane-*.yaml; do
    docker run --rm -e OWLPANE_INGEST_KEY=k -e K8S_NODE_NAME=n -e PG_USER_0=u -e PG_PASSWORD_0=p -e REDIS_PASSWORD_0=p \
      -e MYSQL_USER_0=u -e MYSQL_PASSWORD_0=p -e MONGO_USER_0=u -e MONGO_PASSWORD_0=p -e RABBIT_USER_0=u -e RABBIT_PASSWORD_0=p \
      -e KUBERNETES_SERVICE_HOST=127.0.0.1 -e KUBERNETES_SERVICE_PORT=6443 \
      -v "$TMP/ca.crt:$SA/ca.crt:ro" -v "$TMP/token:$SA/token:ro" -v "$f:/c.yaml:ro" "$IMG" validate --config=/c.yaml >/dev/null 2>"$TMP/err" || { echo "FAIL: collector rejects $(basename "$f")"; cat "$TMP/err"; exit 1; }
  done
  echo "PASS: the collector accepts every rendered configuration"
fi
