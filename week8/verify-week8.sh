#!/bin/bash

# ============================================================
# Week 8 Verification — GitOps with ArgoCD
# ============================================================

set +e

ARGO_NAMESPACE="argocd"
APP_NAME="cloud-native-notes"
APP_NAMESPACE="cloud-native-notes"

INGRESS_NAMESPACE="ingress-nginx"
INGRESS_CONTROLLER_DEPLOY="ingress-nginx-controller"

ARGO_HOST="argocd.127-0-0-1.nip.io"
ARGO_URL="https://${ARGO_HOST}"
ARGO_HOST_ALT="argocd.127.0.0.1.nip.io"
ARGO_URL_ALT="https://${ARGO_HOST_ALT}"

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

if command -v git >/dev/null 2>&1; then
    pass "git is installed"
else
    warn "git is not installed (helpful for verifying repo state)"
fi

# ------------------------------------------------------------
# 2. ArgoCD namespace and installation
# ------------------------------------------------------------

section "2. ARGOCD INSTALLATION"

if kubectl get namespace "$ARGO_NAMESPACE" >/dev/null 2>&1; then
    pass "Namespace $ARGO_NAMESPACE exists"
else
    fail "Namespace $ARGO_NAMESPACE does not exist"
fi

# CRDs
for crd in applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io; do
    if kubectl get crd "$crd" >/dev/null 2>&1; then
        pass "CRD $crd is installed"
    else
        fail "CRD $crd is missing"
    fi
done

# ------------------------------------------------------------
# 3. ArgoCD components running
# ------------------------------------------------------------

section "3. ARGOCD COMPONENTS"

check_deploy_ready() {
    local name="$1"
    if ! kubectl get deployment "$name" -n "$ARGO_NAMESPACE" >/dev/null 2>&1; then
        fail "Deployment $name not found"
        return
    fi
    local ready desired
    ready=$(kubectl get deployment "$name" -n "$ARGO_NAMESPACE" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    desired=$(kubectl get deployment "$name" -n "$ARGO_NAMESPACE" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null)
    ready=${ready:-0}
    desired=${desired:-0}

    if [ "$ready" -gt 0 ] && [ "$ready" -eq "$desired" ]; then
        pass "$name is ready ($ready/$desired)"
    else
        fail "$name not ready ($ready/$desired)"
    fi
}

check_deploy_ready "argocd-server"
check_deploy_ready "argocd-repo-server"
check_deploy_ready "argocd-redis"
check_deploy_ready "argocd-applicationset-controller"
check_deploy_ready "argocd-notifications-controller"

# application-controller is a StatefulSet
if kubectl get statefulset argocd-application-controller \
    -n "$ARGO_NAMESPACE" >/dev/null 2>&1; then
    ready=$(kubectl get statefulset argocd-application-controller \
        -n "$ARGO_NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    ready=${ready:-0}
    if [ "$ready" -ge 1 ]; then
        pass "argocd-application-controller is ready ($ready)"
    else
        fail "argocd-application-controller not ready"
    fi
else
    fail "argocd-application-controller StatefulSet not found"
fi

# ------------------------------------------------------------
# 4. ArgoCD admin password retrievable
# ------------------------------------------------------------

section "4. ARGOCD ADMIN PASSWORD"

if kubectl get secret argocd-initial-admin-secret \
    -n "$ARGO_NAMESPACE" >/dev/null 2>&1; then
    pass "Secret argocd-initial-admin-secret exists"

    ARGO_PASS=$(kubectl get secret argocd-initial-admin-secret \
        -n "$ARGO_NAMESPACE" -o jsonpath='{.data.password}' 2>/dev/null \
        | base64 -d 2>/dev/null)

    if [ -n "$ARGO_PASS" ]; then
        pass "Admin password retrievable (length: ${#ARGO_PASS})"
        echo "       Retrieve with:"
        echo "         kubectl get secret argocd-initial-admin-secret -n $ARGO_NAMESPACE -o jsonpath='{.data.password}' | base64 -d"
    else
        fail "Could not decode admin password"
    fi
else
    warn "argocd-initial-admin-secret not found (may have been deleted after first login)"
fi

# ------------------------------------------------------------
# 5. SSL passthrough enabled on ingress controller
# ------------------------------------------------------------

section "5. SSL PASSTHROUGH ON INGRESS CONTROLLER"

if kubectl get deployment "$INGRESS_CONTROLLER_DEPLOY" \
    -n "$INGRESS_NAMESPACE" >/dev/null 2>&1; then

    ARGS=$(kubectl get deployment "$INGRESS_CONTROLLER_DEPLOY" \
        -n "$INGRESS_NAMESPACE" \
        -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null)

    if echo "$ARGS" | grep -q "enable-ssl-passthrough"; then
        pass "Ingress controller has --enable-ssl-passthrough"
    else
        fail "Ingress controller is missing --enable-ssl-passthrough"
        echo "       Patch it with:"
        echo "         kubectl patch deployment $INGRESS_CONTROLLER_DEPLOY -n $INGRESS_NAMESPACE \\"
        echo "           --type='json' \\"
        echo "           -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--enable-ssl-passthrough\"}]'"
    fi
else
    fail "Ingress controller deployment not found in $INGRESS_NAMESPACE"
fi

# ------------------------------------------------------------
# 6. ArgoCD Ingress resource
# ------------------------------------------------------------

section "6. ARGOCD INGRESS"

ARGO_INGRESS_HOST=$(kubectl get ingress -n "$ARGO_NAMESPACE" \
    -o jsonpath='{range .items[*]}{.spec.rules[*].host}{"\n"}{end}' 2>/dev/null \
    | grep -E "argocd" | head -1)

if [ -n "$ARGO_INGRESS_HOST" ]; then
    pass "Ingress for ArgoCD exists (host: $ARGO_INGRESS_HOST)"
else
    fail "No Ingress found for ArgoCD in $ARGO_NAMESPACE"
fi

# Check that ssl-passthrough annotation is set on the ingress
if kubectl get ingress -n "$ARGO_NAMESPACE" -o yaml 2>/dev/null \
    | grep -q 'ssl-passthrough: "true"'; then
    pass "ArgoCD Ingress has ssl-passthrough annotation"
else
    warn "ArgoCD Ingress missing ssl-passthrough annotation (may still work if backend-protocol is HTTP)"
fi

# ------------------------------------------------------------
# 7. ArgoCD server reachable via Ingress
# ------------------------------------------------------------

section "7. ARGOCD UI REACHABLE"

# -k to allow self-signed certificate
ARGO_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 \
    "${ARGO_URL}" 2>/dev/null)

echo "       GET ${ARGO_URL} → HTTP $ARGO_CODE"

case "$ARGO_CODE" in
    200|302|307)
        pass "ArgoCD UI reachable ($ARGO_CODE)"
        ;;
    000)
        fail "ArgoCD UI NOT reachable (connection failed)"
        echo "       Check:"
        echo "         - Ingress controller has --enable-ssl-passthrough"
        echo "         - ArgoCD Ingress host resolves via nip.io"
        echo "         - argocd-server pod is Ready"
        ;;
    *)
        fail "ArgoCD UI returned unexpected HTTP $ARGO_CODE"
        ;;
esac

# ------------------------------------------------------------
# 8. ArgoCD Application exists
# ------------------------------------------------------------

section "8. ARGOCD APPLICATION"

if kubectl get application "$APP_NAME" -n "$ARGO_NAMESPACE" >/dev/null 2>&1; then
    pass "Application $APP_NAME exists in $ARGO_NAMESPACE"
else
    fail "Application $APP_NAME not found in $ARGO_NAMESPACE"
fi

if kubectl get application "$APP_NAME" -n "$ARGO_NAMESPACE" >/dev/null 2>&1; then

    REPO_URL=$(kubectl get application "$APP_NAME" -n "$ARGO_NAMESPACE" \
        -o jsonpath='{.spec.source.repoURL}' 2>/dev/null)
    TARGET_REV=$(kubectl get application "$APP_NAME" -n "$ARGO_NAMESPACE" \
        -o jsonpath='{.spec.source.targetRevision}' 2>/dev/null)
    APP_PATH=$(kubectl get application "$APP_NAME" -n "$ARGO_NAMESPACE" \
        -o jsonpath='{.spec.source.path}' 2>/dev/null)
    RECURSE=$(kubectl get application "$APP_NAME" -n "$ARGO_NAMESPACE" \
        -o jsonpath='{.spec.source.directory.recurse}' 2>/dev/null)
    DEST_NS=$(kubectl get application "$APP_NAME" -n "$ARGO_NAMESPACE" \
        -o jsonpath='{.spec.destination.namespace}' 2>/dev/null)

    echo "       repoURL        : $REPO_URL"
    echo "       targetRevision : $TARGET_REV"
    echo "       path           : $APP_PATH"
    echo "       recurse        : $RECURSE"
    echo "       dest namespace : $DEST_NS"

    if [ -n "$REPO_URL" ]; then
        pass "Application has a repoURL configured"
    else
        fail "Application has no repoURL"
    fi

    if [ -n "$APP_PATH" ]; then
        pass "Application has a source path configured ($APP_PATH)"
    else
        fail "Application has no source path (ArgoCD will look in repo root)"
    fi

    if [ "$RECURSE" = "true" ]; then
        pass "Application has directory.recurse=true (nested manifests will be picked up)"
    else
        warn "Application does not have directory.recurse=true"
    fi

    if [ "$DEST_NS" = "$APP_NAMESPACE" ]; then
        pass "Application targets namespace $APP_NAMESPACE"
    else
        fail "Application targets '$DEST_NS' instead of '$APP_NAMESPACE'"
    fi
fi

# ------------------------------------------------------------
# 9. Application sync + health status
# ------------------------------------------------------------

section "9. APPLICATION SYNC AND HEALTH"

if kubectl get application "$APP_NAME" -n "$ARGO_NAMESPACE" >/dev/null 2>&1; then

    SYNC_STATUS=$(kubectl get application "$APP_NAME" -n "$ARGO_NAMESPACE" \
        -o jsonpath='{.status.sync.status}' 2>/dev/null)
    HEALTH_STATUS=$(kubectl get application "$APP_NAME" -n "$ARGO_NAMESPACE" \
        -o jsonpath='{.status.health.status}' 2>/dev/null)

    echo "       sync.status   : $SYNC_STATUS"
    echo "       health.status : $HEALTH_STATUS"

    if [ "$SYNC_STATUS" = "Synced" ]; then
        pass "Application is Synced"
    else
        fail "Application sync status is '$SYNC_STATUS' (expected 'Synced')"
    fi

    if [ "$HEALTH_STATUS" = "Healthy" ]; then
        pass "Application is Healthy"
    else
        fail "Application health status is '$HEALTH_STATUS' (expected 'Healthy')"
    fi

    # Comparison error (repo/path unreachable)
    if kubectl get application "$APP_NAME" -n "$ARGO_NAMESPACE" -o yaml 2>/dev/null \
        | grep -q "ComparisonError"; then
        fail "Application has a ComparisonError (repo/path not resolvable)"
        echo "       Check the spec.source.path and that the repo is reachable"
    else
        pass "No ComparisonError on the Application"
    fi
else
    warn "Skipping sync/health checks — Application missing"
fi

# ------------------------------------------------------------
# 10. Sync policy (automated + self-heal)
# ------------------------------------------------------------

section "10. SYNC POLICY"

if kubectl get application "$APP_NAME" -n "$ARGO_NAMESPACE" >/dev/null 2>&1; then

    AUTOMATED=$(kubectl get application "$APP_NAME" -n "$ARGO_NAMESPACE" \
        -o jsonpath='{.spec.syncPolicy.automated}' 2>/dev/null)
    PRUNE=$(kubectl get application "$APP_NAME" -n "$ARGO_NAMESPACE" \
        -o jsonpath='{.spec.syncPolicy.automated.prune}' 2>/dev/null)
    SELF_HEAL=$(kubectl get application "$APP_NAME" -n "$ARGO_NAMESPACE" \
        -o jsonpath='{.spec.syncPolicy.automated.selfHeal}' 2>/dev/null)

    if [ -n "$AUTOMATED" ]; then
        pass "Automated sync is enabled"

        if [ "$PRUNE" = "true" ]; then
            pass "Automated prune is enabled"
        else
            warn "Automated prune is disabled (orphaned resources won't be cleaned up)"
        fi

        if [ "$SELF_HEAL" = "true" ]; then
            pass "Self-heal is enabled"
        else
            warn "Self-heal is disabled (drift won't be corrected)"
        fi
    else
        warn "Automated sync is not enabled (manual sync required)"
    fi
else
    warn "Skipping sync policy checks — Application missing"
fi

# ------------------------------------------------------------
# 11. Managed resources are healthy
# ------------------------------------------------------------

section "11. MANAGED RESOURCES"

if kubectl get application "$APP_NAME" -n "$ARGO_NAMESPACE" >/dev/null 2>&1; then

    # Count resources ArgoCD is tracking
    RESOURCE_COUNT=$(kubectl get application "$APP_NAME" -n "$ARGO_NAMESPACE" \
        -o jsonpath='{.status.resources}' 2>/dev/null \
        | grep -o '"kind"' | wc -l | tr -d ' ')
    RESOURCE_COUNT=${RESOURCE_COUNT:-0}

    echo "       ArgoCD is tracking $RESOURCE_COUNT resources"

    if [ "$RESOURCE_COUNT" -gt 0 ]; then
        pass "Application tracks $RESOURCE_COUNT resources"
    else
        fail "Application tracks 0 resources (path or recurse may be wrong)"
    fi

    # List any resources not in Synced state
    OUT_OF_SYNC=$(kubectl get application "$APP_NAME" -n "$ARGO_NAMESPACE" \
        -o jsonpath='{range .status.resources[*]}{.kind}/{.name}={.status}{"\n"}{end}' 2>/dev/null \
        | grep -v "=Synced" | grep -v "=$" | head -10)

    if [ -z "$OUT_OF_SYNC" ]; then
        pass "All tracked resources are Synced"
    else
        warn "Some resources are not Synced:"
        echo "$OUT_OF_SYNC" | sed 's/^/         /'
    fi
fi

# ------------------------------------------------------------
# 12. Core workload healthy (from ArgoCD-managed manifests)
# ------------------------------------------------------------

section "12. CORE WORKLOAD HEALTH"

# The manifests under k8s/ should still have created these in the cluster.
if kubectl get namespace "$APP_NAMESPACE" >/dev/null 2>&1; then
    pass "Namespace $APP_NAMESPACE exists"
else
    fail "Namespace $APP_NAMESPACE does not exist"
fi

for dep in backend redis frontend; do
    if kubectl get deployment "$dep" -n "$APP_NAMESPACE" >/dev/null 2>&1; then
        ready=$(kubectl get deployment "$dep" -n "$APP_NAMESPACE" \
            -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
        desired=$(kubectl get deployment "$dep" -n "$APP_NAMESPACE" \
            -o jsonpath='{.spec.replicas}' 2>/dev/null)
        ready=${ready:-0}
        desired=${desired:-0}

        if [ "$ready" -gt 0 ] && [ "$ready" -eq "$desired" ]; then
            pass "$dep ready ($ready/$desired)"
        else
            fail "$dep not ready ($ready/$desired)"
        fi
    else
        fail "Deployment $dep not found in $APP_NAMESPACE"
    fi
done

# ------------------------------------------------------------
# 13. GitOps drift correction (informational)
# ------------------------------------------------------------

section "13. DRIFT CORRECTION (INFORMATIONAL)"

echo "  To test self-healing manually:"
echo "    1. Scale a deployment out of band:"
echo "         kubectl scale deployment backend -n $APP_NAMESPACE --replicas=5"
echo "    2. Wait ~3 minutes (ArgoCD default poll interval) or force a refresh:"
echo "         kubectl annotate application $APP_NAME -n $ARGO_NAMESPACE \\"
echo "           argocd.argoproj.io/refresh=hard --overwrite"
echo "    3. Verify the replica count reverts to what's declared in Git:"
echo "         kubectl get deployment backend -n $APP_NAMESPACE \\"
echo "           -o jsonpath='{.spec.replicas}'"
echo

# ------------------------------------------------------------
# 14. App-of-apps pattern (extra challenge)
# ------------------------------------------------------------

section "14. APP OF APPS (EXTRA CHALLENGE)"

APP_COUNT=$(kubectl get applications -n "$ARGO_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
APP_COUNT=${APP_COUNT:-0}

echo "       Total Applications in $ARGO_NAMESPACE: $APP_COUNT"

if [ "$APP_COUNT" -gt 1 ]; then
    pass "App-of-apps pattern in use ($APP_COUNT Applications)"
    kubectl get applications -n "$ARGO_NAMESPACE" --no-headers 2>/dev/null \
        | sed 's/^/         /'
else
    warn "Only one Application present (app-of-apps is an extra challenge)"
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
    echo "🎉 WEEK 8 VERIFICATION PASSED!"
    echo
    echo "All automatically verifiable Week 8 tasks"
    echo "have been successfully verified."
else
    echo "⚠️ WEEK 8 VERIFICATION INCOMPLETE"
    echo
    echo "Fix the failed checks and run the script again."
fi

echo
echo "=========================================="

# Exit with failure if verification failed
if [ "$FAIL" -gt 0 ]; then
    exit 1
else
    exit 0
fi
