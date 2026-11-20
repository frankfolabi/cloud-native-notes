#!/bin/bash

# ============================================================
# Week 7 Verification — Observability
# ============================================================

set +e

NAMESPACE="cloud-native-notes"
MONITORING_NAMESPACE="monitoring"
BACKEND_DEPLOY="backend"
EXPECTED_IMAGE="cloud-native-notes:4.0"
SERVICE_MONITOR="backend-monitor"
BACKEND_SVC="backend"

GRAFANA_URL="http://status.notes.127-0-0-1.nip.io"
PROMETHEUS_URL="http://metrics.notes.127-0-0-1.nip.io"
NOTES_URL="http://notes.127-0-0-1.nip.io"

HELM_RELEASE="monitoring"

PASS=0
FAIL=0
WARN=0

# ------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------

pass() {
    echo "  ✅ PASS: $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "  ❌ FAIL: $1"
    FAIL=$((FAIL + 1))
}

warn() {
    echo "  ⚠️  WARN: $1"
    WARN=$((WARN + 1))
}

section() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
    echo
}

# ------------------------------------------------------------
# 1. Basic environment
# ------------------------------------------------------------

section "1. BASIC ENVIRONMENT"

if command -v kubectl >/dev/null 2>&1; then
    pass "kubectl is installed"
else
    fail "kubectl is not installed"
fi

if kubectl cluster-info >/dev/null 2>&1; then
    pass "Kubernetes cluster is accessible"
else
    fail "Kubernetes cluster is not accessible"
fi

if command -v curl >/dev/null 2>&1; then
    pass "curl is installed"
else
    fail "curl is not installed"
fi

if command -v helm >/dev/null 2>&1; then
    pass "helm is installed"
else
    fail "helm is not installed"
fi

# ------------------------------------------------------------
# 2. Week 7 image 4.0
# ------------------------------------------------------------

section "2. WEEK 7 IMAGE 4.0"

if command -v docker >/dev/null 2>&1; then
    if docker image inspect "$EXPECTED_IMAGE" >/dev/null 2>&1; then
        pass "Image $EXPECTED_IMAGE exists locally"
    else
        warn "Image $EXPECTED_IMAGE not found locally (may exist only in cluster)"
    fi
else
    warn "Docker not installed — skipping local image check"
fi

if kubectl get deployment "$BACKEND_DEPLOY" \
    -n "$NAMESPACE" >/dev/null 2>&1; then

    IMG=$(kubectl get deployment "$BACKEND_DEPLOY" \
        -n "$NAMESPACE" \
        -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)

    echo "       Backend deployment image: $IMG"

    if [ "$IMG" = "$EXPECTED_IMAGE" ]; then
        pass "Backend deployment uses image $EXPECTED_IMAGE"
    else
        fail "Backend deployment uses '$IMG' instead of $EXPECTED_IMAGE"
    fi
else
    fail "Backend deployment missing"
fi

# ------------------------------------------------------------
# 3. Backend rollout status
# ------------------------------------------------------------

section "3. BACKEND ROLLOUT"

if kubectl get deployment "$BACKEND_DEPLOY" \
    -n "$NAMESPACE" >/dev/null 2>&1; then

    READY=$(kubectl get deployment "$BACKEND_DEPLOY" \
        -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    DESIRED=$(kubectl get deployment "$BACKEND_DEPLOY" \
        -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null)
    READY=${READY:-0}
    DESIRED=${DESIRED:-0}

    if [ "$READY" -gt 0 ] && [ "$READY" -eq "$DESIRED" ]; then
        pass "Backend pods ready ($READY/$DESIRED)"
    else
        fail "Backend pods not all ready ($READY/$DESIRED)"
    fi

    UPDATED=$(kubectl get deployment "$BACKEND_DEPLOY" \
        -n "$NAMESPACE" -o jsonpath='{.status.updatedReplicas}' 2>/dev/null)
    UPDATED=${UPDATED:-0}

    if [ "$UPDATED" -eq "$DESIRED" ]; then
        pass "All backend replicas updated to the new spec"
    else
        fail "Only $UPDATED/$DESIRED replicas updated"
    fi
else
    fail "Backend deployment missing"
fi

# ------------------------------------------------------------
# 4. /metrics endpoint exposed
# ------------------------------------------------------------

section "4. /metrics ENDPOINT"

if curl -fsS --max-time 5 "${NOTES_URL}/metrics" >/tmp/week7_metrics.txt 2>/dev/null; then
    pass "/metrics reachable through Ingress ($NOTES_URL/metrics)"

    SIZE=$(wc -c </tmp/week7_metrics.txt | tr -d ' ')
    echo "       /metrics response size: $SIZE bytes"

    if [ "$SIZE" -gt 100 ]; then
        pass "/metrics returned a non-trivial payload"
    else
        fail "/metrics response looks empty"
    fi

    # Sanity check: Prometheus text format
    if grep -q "^# HELP" /tmp/week7_metrics.txt; then
        pass "/metrics is in Prometheus text format"
    else
        fail "/metrics is not in Prometheus text format"
    fi
else
    fail "/metrics NOT reachable through Ingress"
fi

# ------------------------------------------------------------
# 5. Application metric families present
# ------------------------------------------------------------

section "5. APPLICATION METRIC FAMILIES"

check_metric() {
    local name="$1"
    if grep -q "^# TYPE ${name}" /tmp/week7_metrics.txt 2>/dev/null; then
        pass "Metric family present: ${name}"
    else
        fail "Metric family missing: ${name}"
    fi
}

check_metric "http_requests_total"
check_metric "http_request_duration_seconds"
check_metric "notes_created_total"
check_metric "active_notes"
check_metric "redis_connected"

echo
echo "  --- Sample values ---"
grep -E '^(active_notes|redis_connected|notes_created_total)' /tmp/week7_metrics.txt | head -5 | sed 's/^/    /'

# ------------------------------------------------------------
# 6. ServiceMonitor exists and is correct
# ------------------------------------------------------------

section "6. SERVICEMONITOR"

if kubectl get servicemonitor "$SERVICE_MONITOR" \
    -n "$NAMESPACE" >/dev/null 2>&1; then
    pass "ServiceMonitor $SERVICE_MONITOR exists in $NAMESPACE"

    SM_PORT=$(kubectl get servicemonitor "$SERVICE_MONITOR" \
        -n "$NAMESPACE" -o jsonpath='{.spec.endpoints[0].port}' 2>/dev/null)
    SM_PATH=$(kubectl get servicemonitor "$SERVICE_MONITOR" \
        -n "$NAMESPACE" -o jsonpath='{.spec.endpoints[0].path}' 2>/dev/null)
    SM_LABEL=$(kubectl get servicemonitor "$SERVICE_MONITOR" \
        -n "$NAMESPACE" -o jsonpath='{.spec.selector.matchLabels.app}' 2>/dev/null)

    echo "       endpoint port : $SM_PORT"
    echo "       endpoint path : $SM_PATH"
    echo "       selector app  : $SM_LABEL"

    if [ "$SM_PORT" = "http" ]; then
        pass "ServiceMonitor endpoint port is 'http'"
    else
        fail "ServiceMonitor endpoint port is '$SM_PORT' (expected 'http')"
    fi

    if [ "$SM_PATH" = "/metrics" ]; then
        pass "ServiceMonitor endpoint path is '/metrics'"
    else
        fail "ServiceMonitor endpoint path is '$SM_PATH' (expected '/metrics')"
    fi

    if [ "$SM_LABEL" = "backend" ]; then
        pass "ServiceMonitor selects Service label app=backend"
    else
        fail "ServiceMonitor selects app='$SM_LABEL' (expected 'backend')"
    fi

    # The backend Service must actually have a named port 'http'
    SVC_PORT_NAMES=$(kubectl get svc "$BACKEND_SVC" \
        -n "$NAMESPACE" -o jsonpath='{.spec.ports[*].name}' 2>/dev/null)

    if echo "$SVC_PORT_NAMES" | tr ' ' '\n' | grep -q "^http$"; then
        pass "Backend Service has a port named 'http'"
    else
        fail "Backend Service has no port named 'http' (found: '$SVC_PORT_NAMES')"
    fi
else
    fail "ServiceMonitor $SERVICE_MONITOR does not exist"
fi

# ------------------------------------------------------------
# 7. Helm release installed
# ------------------------------------------------------------

section "7. HELM RELEASE ($HELM_RELEASE)"

if command -v helm >/dev/null 2>&1; then
    if helm status "$HELM_RELEASE" -n "$MONITORING_NAMESPACE" >/dev/null 2>&1; then
        pass "Helm release '$HELM_RELEASE' is deployed in $MONITORING_NAMESPACE"

        CHART=$(helm list -n "$MONITORING_NAMESPACE" -f "^$HELM_RELEASE$" -o json 2>/dev/null \
            | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["chart"])' 2>/dev/null)

        echo "       Helm chart: $CHART"

        if echo "$CHART" | grep -q "kube-prometheus-stack"; then
            pass "Chart is kube-prometheus-stack"
        else
            warn "Chart does not look like kube-prometheus-stack ($CHART)"
        fi
    else
        fail "Helm release '$HELM_RELEASE' not found in $MONITORING_NAMESPACE"
    fi
else
    fail "helm is not installed — cannot verify release"
fi

# ------------------------------------------------------------
# 8. Monitoring components running
# ------------------------------------------------------------

section "8. MONITORING COMPONENTS"

if kubectl get namespace "$MONITORING_NAMESPACE" >/dev/null 2>&1; then
    pass "Namespace $MONITORING_NAMESPACE exists"
else
    fail "Namespace $MONITORING_NAMESPACE missing"
fi

# Prometheus pods
PROM_READY=$(kubectl get pods -n "$MONITORING_NAMESPACE" \
    -l app.kubernetes.io/name=prometheus \
    -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)

if [ "$PROM_READY" = "true" ]; then
    pass "Prometheus pod is Ready"
else
    fail "Prometheus pod is not Ready"
fi

# Grafana pods
GRAFANA_READY=$(kubectl get pods -n "$MONITORING_NAMESPACE" \
    -l app.kubernetes.io/name=grafana \
    -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)

if [ "$GRAFANA_READY" = "true" ]; then
    pass "Grafana pod is Ready"
else
    fail "Grafana pod is not Ready"
fi

# Operator
OPERATOR_READY=$(kubectl get pods -n "$MONITORING_NAMESPACE" \
    -l app.kubernetes.io/name=kube-prometheus-stack-prometheus-operator \
    -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)

if [ "$OPERATOR_READY" = "true" ]; then
    pass "Prometheus Operator pod is Ready"
else
    warn "Prometheus Operator pod not detected as Ready"
fi

# ------------------------------------------------------------
# 9. Monitoring Ingress resources
# ------------------------------------------------------------

section "9. MONITORING INGRESS"

GRAFANA_INGRESS=$(kubectl get ingress -n "$MONITORING_NAMESPACE" \
    -o jsonpath='{range .items[*]}{.spec.rules[*].host}{"\n"}{end}' 2>/dev/null \
    | grep -q "status.notes.127-0-0-1.nip.io" && echo yes || echo no)

PROM_INGRESS=$(kubectl get ingress -n "$MONITORING_NAMESPACE" \
    -o jsonpath='{range .items[*]}{.spec.rules[*].host}{"\n"}{end}' 2>/dev/null \
    | grep -q "metrics.notes.127-0-0-1.nip.io" && echo yes || echo no)

if [ "$GRAFANA_INGRESS" = "yes" ]; then
    pass "Ingress for Grafana exists (host: status.notes.127-0-0-1.nip.io)"
else
    fail "No Ingress rule for status.notes.127-0-0-1.nip.io"
fi

if [ "$PROM_INGRESS" = "yes" ]; then
    pass "Ingress for Prometheus exists (host: metrics.notes.127-0-0-1.nip.io)"
else
    fail "No Ingress rule for metrics.notes.127-0-0-1.nip.io"
fi

# ------------------------------------------------------------
# 10. Grafana reachable via Ingress
# ------------------------------------------------------------

section "10. GRAFANA REACHABLE"

GRAFANA_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
    "${GRAFANA_URL}/login" 2>/dev/null)

echo "       GET ${GRAFANA_URL}/login → HTTP $GRAFANA_CODE"

case "$GRAFANA_CODE" in
    200|302)
        pass "Grafana login reachable ($GRAFANA_CODE)"
        ;;
    000)
        fail "Grafana NOT reachable (connection failed)"
        ;;
    *)
        fail "Grafana returned HTTP $GRAFANA_CODE"
        ;;
esac

# ------------------------------------------------------------
# 11. Grafana admin password retrievable
# ------------------------------------------------------------

section "11. GRAFANA ADMIN PASSWORD"

# Grafana chart convention: secret name is <release>-grafana
GF_SECRET="${HELM_RELEASE}-grafana"

if kubectl get secret "$GF_SECRET" -n "$MONITORING_NAMESPACE" >/dev/null 2>&1; then
    pass "Secret $GF_SECRET exists"

    GF_PASS=$(kubectl get secret "$GF_SECRET" -n "$MONITORING_NAMESPACE" \
        -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d 2>/dev/null)

    if [ -n "$GF_PASS" ]; then
        pass "Grafana admin password retrievable (length: ${#GF_PASS})"
        echo "       (Not printing password — retrieve with:)"
        echo "       kubectl get secret $GF_SECRET -n $MONITORING_NAMESPACE -o jsonpath='{.data.admin-password}' | base64 -d"
    else
        fail "Grafana admin password could not be decoded"
    fi
else
    fail "Secret $GF_SECRET not found in $MONITORING_NAMESPACE"
fi

# ------------------------------------------------------------
# 12. Prometheus reachable via Ingress
# ------------------------------------------------------------

section "12. PROMETHEUS REACHABLE"

PROM_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
    "${PROMETHEUS_URL}/-/healthy" 2>/dev/null)

echo "       GET ${PROMETHEUS_URL}/-/healthy → HTTP $PROM_CODE"

case "$PROM_CODE" in
    200|302)
        pass "Prometheus reachable ($PROM_CODE)"
        ;;
    000)
        fail "Prometheus NOT reachable (connection failed)"
        ;;
    *)
        fail "Prometheus returned HTTP $PROM_CODE"
        ;;
esac

# Prometheus UI root
PROM_UI_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
    "${PROMETHEUS_URL}/" 2>/dev/null)

if [ "$PROM_UI_CODE" = "200" ] || [ "$PROM_UI_CODE" = "302" ]; then
    pass "Prometheus UI reachable (HTTP $PROM_UI_CODE)"
else
    warn "Prometheus UI root returned HTTP $PROM_UI_CODE"
fi


# ------------------------------------------------------------
# 13. PromQL queries return data
# ------------------------------------------------------------

section "13. PROMQL QUERIES"

query_prom() {
    local expr="$1"
    local url="${PROMETHEUS_URL}/api/v1/query?query=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$expr")"
    curl -fsS --max-time 5 "$url" 2>/dev/null
}

check_query() {
    local name="$1"
    local expr="$2"
    local body
    body=$(query_prom "$expr")

    if [ -z "$body" ]; then
        fail "PromQL query failed: $name"
        return
    fi

    RESULT_COUNT=$(echo "$body" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print(0); sys.exit(0)
res = d.get("data", {}).get("result", [])
print(len(res))
' 2>/dev/null)

    RESULT_COUNT=${RESULT_COUNT:-0}

    if [ "$RESULT_COUNT" -gt 0 ]; then
        pass "PromQL '$name' returned $RESULT_COUNT series"
    else
        fail "PromQL '$name' returned 0 series (query: $expr)"
    fi
}

check_query "http_requests_total"    "http_requests_total"
check_query "notes_created_total"    "notes_created_total"
check_query "active_notes"           "active_notes"
check_query "redis_connected"        "redis_connected"

# ------------------------------------------------------------
# 14. End-to-end: generate traffic, verify metric moves
# ------------------------------------------------------------

section "14. END-TO-END METRIC FLOW"

BEFORE=$(curl -fsS --max-time 5 \
    "${PROMETHEUS_URL}/api/v1/query?query=notes_created_total" 2>/dev/null \
    | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    r = d["data"]["result"]
    print(r[0]["value"][1] if r else "0")
except Exception:
    print("0")
' 2>/dev/null)
BEFORE=${BEFORE:-0}
echo "       notes_created_total before: $BEFORE"

# Create a note through the Ingress
NOTE_JSON=$(curl -fsS --max-time 5 -X POST \
    "${NOTES_URL}/api/notes" \
    -H "Content-Type: application/json" \
    -d '{"title":"Week 7 Verification","content":"Generated by verify-week7.sh"}' \
    2>/dev/null)

NOTE_ID=""
if [ -n "$NOTE_JSON" ]; then
    NOTE_ID=$(echo "$NOTE_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("id",""))' 2>/dev/null)
fi

if [ -n "$NOTE_ID" ]; then
    pass "Created test note via Ingress (id=$NOTE_ID)"
else
    fail "Could not create test note via Ingress"
fi

# Wait for Prometheus to scrape (default interval 15-30s)
echo "       Waiting 20s for Prometheus to scrape..."
sleep 20

AFTER=$(curl -fsS --max-time 5 \
    "${PROMETHEUS_URL}/api/v1/query?query=notes_created_total" 2>/dev/null \
    | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    r = d["data"]["result"]
    print(r[0]["value"][1] if r else "0")
except Exception:
    print("0")
' 2>/dev/null)
AFTER=${AFTER:-0}
echo "       notes_created_total after : $AFTER"

# Numeric comparison via awk (float-safe)
if awk -v a="$AFTER" -v b="$BEFORE" 'BEGIN { exit !(a > b) }'; then
    pass "notes_created_total increased after traffic ($BEFORE → $AFTER)"
else
    fail "notes_created_total did NOT increase ($BEFORE → $AFTER)"
fi

# Clean up the test note
if [ -n "$NOTE_ID" ]; then
    curl -fsS --max-time 5 -X DELETE \
        "${NOTES_URL}/api/notes/$NOTE_ID" >/dev/null 2>&1 \
        && pass "Cleaned up test note" \
        || warn "Could not delete test note (id=$NOTE_ID)"
fi


# ------------------------------------------------------------
# FINAL SCORE
# ------------------------------------------------------------

echo
echo "=========================================="
echo "          VERIFICATION SUMMARY"
echo "=========================================="
echo

echo "Passed checks : $PASS"
echo "Failed checks : $FAIL"
echo "Warnings      : $WARN"

TOTAL=$((PASS + FAIL))
if [ "$TOTAL" -gt 0 ]; then
    SCORE=$((PASS * 100 / TOTAL))
else
    SCORE=0
fi

echo "Verification score: $SCORE%"
echo

if [ "$FAIL" -eq 0 ]; then
    echo "🎉 WEEK 7 VERIFICATION PASSED!"
    echo
    echo "All automatically verifiable Week 7 tasks"
    echo "have been successfully verified."
else
    echo "⚠️ WEEK 7 VERIFICATION INCOMPLETE"
    echo
    echo "Fix the failed checks and run the script again."
fi

echo
echo "=========================================="

rm -f /tmp/week7_metrics.txt

if [ "$FAIL" -gt 0 ]; then
    exit 1
else
    exit 0
fi
