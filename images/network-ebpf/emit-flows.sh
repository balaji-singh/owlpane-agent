#!/bin/sh
# P2 bootstrap: host /proc/tcp sampling with owlpane.flow.source=ebpf-capture.
# Real CO-RE BPF capture replaces this loop in a later image tag (see kubeshark-p2-epic).
set -u
ENDPOINT="${OWLPANE_INGEST_ENDPOINT:?}/v1/logs"
KEY="${OWLPANE_INGEST_KEY:?missing ingest key}"
CLUSTER="${OWLPANE_CLUSTER_NAME:?}"
ENV="${OWLPANE_ENVIRONMENT:-production}"
NODE="${K8S_NODE_NAME:-node}"
INTERVAL="${OWLPANE_EMIT_INTERVAL:-30}"
PORTS="${OWLPANE_CAPTURE_PORTS:-}"

nano() { echo "$(date +%s)000000000"; }

hex_ip() {
  h="$1"
  a=$(printf %s "$h" | cut -c7-8)
  b=$(printf %s "$h" | cut -c5-6)
  c=$(printf %s "$h" | cut -c3-4)
  d=$(printf %s "$h" | cut -c1-2)
  printf "%d.%d.%d.%d" "$((0x$a))" "$((0x$b))" "$((0x$c))" "$((0x$d))"
}

port_ok() {
  [ -z "$PORTS" ] && return 0
  for p in $PORTS; do
    [ "$p" = "$1" ] && return 0
  done
  return 1
}

post_batch() {
  records="$1"
  [ -n "$records" ] || return 0
  curl -sfS -X POST "$ENDPOINT" \
    -H "Authorization: Bearer ${KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"resourceLogs\":[{\"resource\":{\"attributes\":[
      {\"key\":\"service.name\",\"value\":{\"stringValue\":\"owlpane-network-ebpf\"}},
      {\"key\":\"k8s.cluster.name\",\"value\":{\"stringValue\":\"${CLUSTER}\"}},
      {\"key\":\"k8s.node.name\",\"value\":{\"stringValue\":\"${NODE}\"}},
      {\"key\":\"deployment.environment.name\",\"value\":{\"stringValue\":\"${ENV}\"}}
    ]},\"scopeLogs\":[{\"scope\":{\"name\":\"owlpane-network-ebpf\"},\"logRecords\":[${records}]}]}]}"
}

flow_record() {
  srcip="$1"; sport="$2"; dstip="$3"; dport="$4"; proto="$5"; bytes="$6"
  printf '{"timeUnixNano":"%s","severityText":"INFO","body":{"stringValue":"ebpf capture flow"},"attributes":[' "$(nano)"
  printf '{"key":"owlpane.flow.source","value":{"stringValue":"ebpf-capture"}},'
  printf '{"key":"owlpane.flow.src.namespace","value":{"stringValue":"host"}},'
  printf '{"key":"owlpane.flow.src.service","value":{"stringValue":"%s"}},' "$NODE"
  printf '{"key":"owlpane.flow.src.ip","value":{"stringValue":"%s"}},' "$srcip"
  printf '{"key":"owlpane.flow.src.port","value":{"stringValue":"%s"}},' "$sport"
  printf '{"key":"owlpane.flow.dst.namespace","value":{"stringValue":"external"}},'
  printf '{"key":"owlpane.flow.dst.service","value":{"stringValue":"%s"}},' "$dstip"
  printf '{"key":"owlpane.flow.dst.ip","value":{"stringValue":"%s"}},' "$dstip"
  printf '{"key":"owlpane.flow.dst.port","value":{"stringValue":"%s"}},' "$dport"
  printf '{"key":"owlpane.flow.protocol","value":{"stringValue":"%s"}},' "$proto"
  printf '{"key":"owlpane.flow.bytes","value":{"stringValue":"%s"}},' "$bytes"
  printf '{"key":"owlpane.flow.verdict","value":{"stringValue":"allowed"}}]}'
}

emit_tcp() {
  file="$1"
  [ -r "$file" ] || return 0
  batch=""
  while read -r _ laddr raddr st _ _ _ _ _; do
    [ "$st" = "01" ] || continue
    sport=$(echo "$laddr" | cut -d: -f2)
    dport=$(echo "$raddr" | cut -d: -f2)
    port_ok "$dport" || continue
    srcip=$(hex_ip "$(echo "$laddr" | cut -d: -f1)")
    dstip=$(hex_ip "$(echo "$raddr" | cut -d: -f1)")
    rec=$(flow_record "$srcip" "$sport" "$dstip" "$dport" "tcp" "0")
    if [ -n "$batch" ]; then batch="$batch,$rec"; else batch="$rec"; fi
    if [ "$(echo "$batch" | grep -o 'timeUnixNano' | wc -l | tr -d ' ')" -ge 50 ]; then
      post_batch "$batch"
      batch=""
    fi
  done < "$file"
  post_batch "$batch"
}

while true; do
  emit_tcp /host/proc/net/tcp
  emit_tcp /host/proc/net/tcp6
  sleep "$INTERVAL"
done
