#!/bin/bash

# ============================================================
# Week 4 Configuration, Secrets and Storage
# ============================================================

set +e

NAMESPACE="cloud-native-notes"
EXPECTED_IMAGE="cloud-native-notes:3.0"
BACKEND_DEPLOYMENT="backend"
REDIS_DEPLOYMENT="redis"
REDIS_SERVICE="redis-service"
BACKEND_SERVICE="backend"
CONFIGMAP="app-config"
SECRET="redis-secret"

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
# 1. Basic tools
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

# ------------------------------------------------------------
# 2. Week 4 image
# ------------------------------------------------------------

section "2. BACKEND IMAGE 3.0"

if command -v docker >/dev/null 2>&1; then

    if docker image inspect "$EXPECTED_IMAGE" >/dev/null 2>&1; then
        pass "Backend image $EXPECTED_IMAGE exists locally"
    else
        fail "Backend image $EXPECTED_IMAGE was not found locally"
    fi

else
    warn "Docker is not installed; skipping local image check"
fi

# ------------------------------------------------------------
# 3. Namespace
# ------------------------------------------------------------

section "3. KUBERNETES NAMESPACE"

if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    pass "Namespace $NAMESPACE exists"
else
    fail "Namespace $NAMESPACE does not exist"
fi

# ------------------------------------------------------------
# 4. Backend deployment
# ------------------------------------------------------------

section "4. BACKEND DEPLOYMENT"

if kubectl get deployment "$BACKEND_DEPLOYMENT" \
    -n "$NAMESPACE" >/dev/null 2>&1; then

    pass "Backend deployment exists"

    BACKEND_IMAGE=$(kubectl get deployment "$BACKEND_DEPLOYMENT" \
        -n "$NAMESPACE" \
        -o jsonpath='{.spec.template.spec.containers[0].image}' \
        2>/dev/null)

    if [ "$BACKEND_IMAGE" = "$EXPECTED_IMAGE" ]; then
        pass "Backend deployment uses image $EXPECTED_IMAGE"
    else
        fail "Backend deployment uses image '$BACKEND_IMAGE' instead of $EXPECTED_IMAGE"
    fi

else
    fail "Backend deployment does not exist"
fi

# ------------------------------------------------------------
# 5. Backend pods
# ------------------------------------------------------------

section "5. BACKEND PODS"

if kubectl get deployment "$BACKEND_DEPLOYMENT" \
    -n "$NAMESPACE" >/dev/null 2>&1; then

    READY=$(kubectl get deployment "$BACKEND_DEPLOYMENT" \
        -n "$NAMESPACE" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null)

    DESIRED=$(kubectl get deployment "$BACKEND_DEPLOYMENT" \
        -n "$NAMESPACE" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null)

    READY=${READY:-0}
    DESIRED=${DESIRED:-0}

    if [ "$READY" -gt 0 ] && [ "$READY" -eq "$DESIRED" ]; then
        pass "All backend pods are ready ($READY/$DESIRED)"
    else
        fail "Backend pods are not all ready ($READY/$DESIRED)"
    fi

else
    fail "Cannot check backend pods because deployment does not exist"
fi

# ------------------------------------------------------------
# 6. ConfigMap
# ------------------------------------------------------------

section "6. CONFIGMAP"

if kubectl get configmap "$CONFIGMAP" \
    -n "$NAMESPACE" >/dev/null 2>&1; then

    pass "ConfigMap $CONFIGMAP exists"

    CONFIGMAP_DATA=$(kubectl get configmap "$CONFIGMAP" \
        -n "$NAMESPACE" \
        -o jsonpath='{.data}' 2>/dev/null)

    if [ -n "$CONFIGMAP_DATA" ]; then
        pass "ConfigMap $CONFIGMAP contains configuration data"
    else
        fail "ConfigMap $CONFIGMAP exists but contains no data"
    fi

else
    fail "ConfigMap $CONFIGMAP does not exist"
fi

# ------------------------------------------------------------
# 7. Secret
# ------------------------------------------------------------

section "7. REDIS SECRET"

if kubectl get secret "$SECRET" \
    -n "$NAMESPACE" >/dev/null 2>&1; then

    pass "Secret $SECRET exists"

    SECRET_KEYS=$(kubectl get secret "$SECRET" \
        -n "$NAMESPACE" \
        -o jsonpath='{.data}' 2>/dev/null)

    if [ -n "$SECRET_KEYS" ]; then
        pass "Secret $SECRET contains secret data"
    else
        fail "Secret $SECRET contains no data"
    fi

else
    fail "Secret $SECRET does not exist"
fi

# ------------------------------------------------------------
# 8. Patch / envFrom verification
# ------------------------------------------------------------

section "8. BACKEND CONFIGURATION PATCH"

if kubectl get deployment "$BACKEND_DEPLOYMENT" \
    -n "$NAMESPACE" >/dev/null 2>&1; then

    if kubectl get deployment "$BACKEND_DEPLOYMENT" \
        -n "$NAMESPACE" \
        -o yaml 2>/dev/null |
        grep -q "configMapRef:"; then

        pass "Backend deployment references a ConfigMap through envFrom"
    else
        fail "Backend deployment does not reference a ConfigMap through envFrom"
    fi

    if kubectl get deployment "$BACKEND_DEPLOYMENT" \
        -n "$NAMESPACE" \
        -o yaml 2>/dev/null |
        grep -q "name: $CONFIGMAP"; then

        pass "Backend deployment references $CONFIGMAP"
    else
        fail "Backend deployment does not reference $CONFIGMAP"
    fi

    if kubectl get deployment "$BACKEND_DEPLOYMENT" \
        -n "$NAMESPACE" \
        -o yaml 2>/dev/null |
        grep -q "secretRef:"; then

        pass "Backend deployment references a Secret through envFrom"
    else
        fail "Backend deployment does not reference a Secret through envFrom"
    fi

    if kubectl get deployment "$BACKEND_DEPLOYMENT" \
        -n "$NAMESPACE" \
        -o yaml 2>/dev/null |
        grep -q "name: $SECRET"; then

        pass "Backend deployment references $SECRET"
    else
        fail "Backend deployment does not reference $SECRET"
    fi

else
    fail "Cannot verify configuration patch because backend deployment is missing"
fi

# ------------------------------------------------------------
# 9. Redis deployment
# ------------------------------------------------------------

section "9. REDIS DEPLOYMENT"

if kubectl get deployment "$REDIS_DEPLOYMENT" \
    -n "$NAMESPACE" >/dev/null 2>&1; then

    pass "Redis deployment exists"

    REDIS_READY=$(kubectl get deployment "$REDIS_DEPLOYMENT" \
        -n "$NAMESPACE" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null)

    REDIS_DESIRED=$(kubectl get deployment "$REDIS_DEPLOYMENT" \
        -n "$NAMESPACE" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null)

    REDIS_READY=${REDIS_READY:-0}
    REDIS_DESIRED=${REDIS_DESIRED:-0}

    if [ "$REDIS_READY" -gt 0 ] &&
       [ "$REDIS_READY" -eq "$REDIS_DESIRED" ]; then

        pass "Redis pods are ready ($REDIS_READY/$REDIS_DESIRED)"
    else
        fail "Redis pods are not all ready ($REDIS_READY/$REDIS_DESIRED)"
    fi

else
    fail "Redis deployment does not exist"
fi

# ------------------------------------------------------------
# 10. Redis service
# ------------------------------------------------------------

section "10. REDIS SERVICE"

if kubectl get service "$REDIS_SERVICE" \
    -n "$NAMESPACE" >/dev/null 2>&1; then

    pass "Redis service $REDIS_SERVICE exists"

    REDIS_PORT=$(kubectl get service "$REDIS_SERVICE" \
        -n "$NAMESPACE" \
        -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)

    if [ "$REDIS_PORT" = "6379" ]; then
        pass "Redis service exposes port 6379"
    else
        fail "Redis service exposes port $REDIS_PORT instead of 6379"
    fi

else
    fail "Redis service $REDIS_SERVICE does not exist"
fi

# ------------------------------------------------------------
# 11. Backend service
# ------------------------------------------------------------

section "11. BACKEND SERVICE"

if kubectl get service "$BACKEND_SERVICE" \
    -n "$NAMESPACE" >/dev/null 2>&1; then

    pass "Backend service exists"

    BACKEND_PORT=$(kubectl get service "$BACKEND_SERVICE" \
        -n "$NAMESPACE" \
        -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)

    if [ "$BACKEND_PORT" = "3000" ]; then
        pass "Backend service exposes port 3000"
    else
        fail "Backend service exposes port $BACKEND_PORT instead of 3000"
    fi

else
    fail "Backend service does not exist"
fi

# ------------------------------------------------------------
# 12. Existing backend port-forward / application test
# ------------------------------------------------------------

section "12. APPLICATION TEST"

PF_PID=""

# Try an existing port-forward first
echo "Checking for an existing port-forward on localhost:3000..."

if curl -fsS --max-time 3 \
    http://localhost:3000/health >/tmp/week4_health.json 2>/dev/null; then

    pass "Backend /health endpoint is reachable through port 3000"

else
    # Start our own port-forward in the background
    echo "  → No port-forward detected. Starting one in the background..."

    kubectl port-forward \
        -n "$NAMESPACE" \
        svc/"$BACKEND_SERVICE" 3000:3000 \
        >/tmp/week4_pf.log 2>&1 &
    PF_PID=$!

    # Wait up to 15s for the port-forward to be ready
    READY=0
    for i in $(seq 1 15); do
        if curl -fsS --max-time 2 \
            http://localhost:3000/health >/dev/null 2>&1; then
            READY=1
            break
        fi
        sleep 1
    done

    if [ "$READY" -eq 1 ]; then
        pass "Started port-forward on localhost:3000 (pid $PF_PID)"
    else
        fail "Could not start port-forward on localhost:3000"
        echo "       See /tmp/week4_pf.log for details"
    fi
fi

# Re-check health now that port-forward may be up
if curl -fsS --max-time 3 \
    http://localhost:3000/health >/tmp/week4_health.json 2>/dev/null; then

    pass "Backend /health endpoint is reachable through port 3000"

    if grep -qi "healthy" /tmp/week4_health.json; then
        pass "Backend health endpoint reports healthy"
    else
        warn "Backend responded, but 'healthy' was not found in the response"
    fi
else
    fail "Backend /health endpoint is not reachable on localhost:3000"
fi

# ------------------------------------------------------------
# 13. Notes API
# ------------------------------------------------------------

section "13. NOTES API"

if curl -fsS --max-time 3 \
    http://localhost:3000/api/notes >/tmp/week4_notes.json 2>/dev/null; then

    pass "Notes API is reachable"

    if command -v python3 >/dev/null 2>&1; then

        if python3 - <<'PY' >/dev/null 2>&1
import json
with open("/tmp/week4_notes.json") as f:
    data = json.load(f)
assert isinstance(data, (list, dict))
PY
        then
            pass "Notes API returned valid JSON"
        else
            fail "Notes API did not return valid JSON"
        fi
    else
        warn "python3 is unavailable; JSON structure was not checked"
    fi
else
    fail "Notes API is not reachable"
fi


# ------------------------------------------------------------
# 14. Redis communication
# ------------------------------------------------------------

section "14. REDIS COMMUNICATION"

REDIS_PING=""
REDIS_TEST=""

if kubectl get deployment "$BACKEND_DEPLOYMENT" \
    -n "$NAMESPACE" >/dev/null 2>&1 &&
   kubectl get deployment "$REDIS_DEPLOYMENT" \
    -n "$NAMESPACE" >/dev/null 2>&1; then

    # ---- Test 1: PING Redis using env vars (host, port, password) ----
    REDIS_PING=$(kubectl exec \
        -n "$NAMESPACE" \
        deploy/"$BACKEND_DEPLOYMENT" \
        -- python -c "
import os
import redis

host = os.getenv('REDIS_HOST')
port = int(os.getenv('REDIS_PORT', '6379'))
password = os.getenv('REDIS_PASSWORD')

print('HOST:', host)
print('PORT:', port)
print('PASSWORD SET:', bool(password))

r = redis.Redis(host=host, port=port, password=password, decode_responses=True)
print('PING:', r.ping())
" 2>/dev/null)

    if echo "$REDIS_PING" | grep -q "PING: True"; then
        pass "Backend can PING Redis (using env vars)"
    else
        fail "Backend cannot PING Redis"
        echo "       Output was:"
        echo "$REDIS_PING" | sed 's/^/         /'
    fi

    # ---- Test 2: Read/write using env vars for host, port, password ----
    REDIS_TEST=$(kubectl exec \
        -n "$NAMESPACE" \
        deploy/"$BACKEND_DEPLOYMENT" \
        -- python -c "
import os
import json
import redis

r = redis.Redis(
    host=os.getenv('REDIS_HOST', 'redis-service'),
    port=int(os.getenv('REDIS_PORT', '6379')),
    password=os.getenv('REDIS_PASSWORD'),
    decode_responses=True,
)
r.set('test:verification', json.dumps({'status': 'working'}))
print(r.get('test:verification'))
r.delete('test:verification')
" 2>/dev/null)

    if echo "$REDIS_TEST" | grep -q '"status": "working"'; then
        pass "Backend can write to and read from Redis (using env vars)"
    else
        fail "Backend cannot complete Redis read/write test"
        echo "       Output was:"
        echo "$REDIS_TEST" | sed 's/^/         /'
    fi

else
    fail "Cannot test Redis communication because required deployments are missing"
fi

# ------------------------------------------------------------
# 15. Secret security
# ------------------------------------------------------------

section "15. SECRET SECURITY"

echo "Checking whether redis-secret exists as a Kubernetes Secret."

if kubectl get secret "$SECRET" \
    -n "$NAMESPACE" >/dev/null 2>&1; then

    pass "A Kubernetes Secret is being used for Redis credentials"

else
    warn "redis-secret was not found"
fi

# ------------------------------------------------------------
# 16. Extra challenge - Redis communication
# ------------------------------------------------------------

section "16. SERVICE COMMUNICATION"

if echo "$REDIS_PING" | grep -q "PING: True" &&
   echo "$REDIS_TEST" | grep -q '"status": "working"'; then

    pass "Backend ↔ Redis service communication verified"

else
    fail "Backend ↔ Redis service communication could not be verified"

fi

# ------------------------------------------------------------
# 17. Data persistence after backend restart
# ------------------------------------------------------------

section "17. DATA PERSISTENCE AFTER BACKEND RESTART"

if ! kubectl get deployment "$BACKEND_DEPLOYMENT" \
    -n "$NAMESPACE" >/dev/null 2>&1; then
    fail "Cannot test persistence because backend deployment is missing"
else

    # --- Step 1: Write a persistence marker directly to Redis ---
    echo "  → Writing persistence marker to Redis via backend pod..."

    PERSIST_KEY="test:persistence:$(date +%s)"
    PERSIST_VALUE='{"status":"persisted","title":"Persistence Test"}'

    WRITE_RESULT=$(kubectl exec \
        -n "$NAMESPACE" \
        deploy/"$BACKEND_DEPLOYMENT" \
        -- python -c "
import os, redis
r = redis.Redis(
    host=os.getenv('REDIS_HOST', 'redis-service'),
    port=int(os.getenv('REDIS_PORT', '6379')),
    password=os.getenv('REDIS_PASSWORD'),
    decode_responses=True,
)
r.set('$PERSIST_KEY', '$PERSIST_VALUE')
print('WROTE:', r.get('$PERSIST_KEY'))
" 2>/dev/null)

    if echo "$WRITE_RESULT" | grep -q "WROTE:"; then
        pass "Persistence marker written to Redis before restart"
    else
        fail "Could not write persistence marker to Redis"
        echo "       Output was:"
        echo "$WRITE_RESULT" | sed 's/^/         /'
    fi

    # --- Step 2: Restart the backend deployment ---
    echo "  → Restarting backend deployment..."

    if kubectl rollout restart deployment/"$BACKEND_DEPLOYMENT" \
        -n "$NAMESPACE" >/dev/null 2>&1; then
        pass "Backend deployment restarted successfully"
    else
        fail "Failed to restart backend deployment"
    fi

    # --- Step 3: Wait for rollout to complete ---
    echo "  → Waiting for backend rollout to complete..."

    if kubectl rollout status deployment/"$BACKEND_DEPLOYMENT" \
        -n "$NAMESPACE" --timeout=120s >/dev/null 2>&1; then
        pass "Backend rollout completed"
    else
        fail "Backend rollout did not complete within timeout"
    fi

    # --- Step 4: Wait for at least one pod to be ready ---
    READY_AFTER=0
    for i in $(seq 1 30); do
        READY_AFTER=$(kubectl get deployment "$BACKEND_DEPLOYMENT" \
            -n "$NAMESPACE" \
            -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
        READY_AFTER=${READY_AFTER:-0}
        if [ "$READY_AFTER" -gt 0 ]; then
            break
        fi
        sleep 2
    done

    if [ "$READY_AFTER" -gt 0 ]; then
        pass "Backend pod is ready after restart ($READY_AFTER ready)"
    else
        fail "Backend pod did not become ready after restart"
    fi

    # --- Step 5: Read back the persistence marker from Redis ---
    echo "  → Reading persistence marker back from Redis..."

    READ_RESULT=$(kubectl exec \
        -n "$NAMESPACE" \
        deploy/"$BACKEND_DEPLOYMENT" \
        -- python -c "
import os, redis
r = redis.Redis(
    host=os.getenv('REDIS_HOST', 'redis-service'),
    port=int(os.getenv('REDIS_PORT', '6379')),
    password=os.getenv('REDIS_PASSWORD'),
    decode_responses=True,
)
val = r.get('$PERSIST_KEY')
print('READ:', val)
r.delete('$PERSIST_KEY')
" 2>/dev/null)

    # Strip the "READ: " prefix and check the JSON content robustly
    READ_JSON=$(echo "$READ_RESULT" | sed -n 's/^READ: //p')

    if command -v python3 >/dev/null 2>&1; then
        if python3 - "$READ_JSON" <<'PY' >/dev/null 2>&1
import json, sys
raw = sys.argv[1].strip()
if not raw or raw == "None":
    sys.exit(1)
data = json.loads(raw)
assert data.get("status") == "persisted"
PY
        then
            pass "Data persisted in Redis after backend restart"
        else
            fail "Data was NOT found in Redis after backend restart"
            echo "       Output was:"
            echo "$READ_RESULT" | sed 's/^/         /'
        fi
    else
        # Fallback: match both spaced and unspaced JSON formats
        if echo "$READ_JSON" | grep -qE '"status"[[:space:]]*:[[:space:]]*"persisted"'; then
            pass "Data persisted in Redis after backend restart"
        else
            fail "Data was NOT found in Redis after backend restart"
            echo "       Output was:"
            echo "$READ_RESULT" | sed 's/^/         /'
        fi
    fi

    

fi

# ============================================================
# FINAL SCORE
# ============================================================

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

    echo "🎉 WEEK 4 VERIFICATION PASSED!"
    echo
    echo "Congrats! All Week 4 core tasks"
    echo "have been successfully verified."

else

    echo "⚠️ WEEK 4 VERIFICATION INCOMPLETE"
    echo
    echo "Fix the failed checks and run the script again."

fi

echo
echo "=========================================="

rm -f /tmp/week4_health.json
rm -f /tmp/week4_notes.json
rm -f /tmp/week4_notes_after.json

# Exit with failure if verification failed
if [ "$FAIL" -gt 0 ]; then
    exit 1
else
    exit 0
fi