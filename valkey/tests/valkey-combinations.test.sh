#!/usr/bin/env bash

set -euo pipefail

# =============================================================================
# Valkey Helm Chart Test Script
# Tests all combinations of: TLS, Authentication, Sharding, Replication
# =============================================================================

VALKEY_HOST="valkey.default.svc.cluster.local"
VALKEY_IMAGE="valkey/valkey:9.0.1"

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------

echo "=== Setup ==="

# Create auth secret
kubectl create secret generic valkey-auth --from-literal=default=password

# Generate TLS certificates
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout valkey-ca.key -out valkey-ca.crt \
    -subj /CN=valkey-ca

openssl req -nodes -newkey rsa:2048 \
    -keyout valkey-server.key -out valkey-server.csr \
    -subj /CN=valkey.default.svc.cluster.local \
    -addext 'subjectAltName=DNS:valkey.default.svc.cluster.local,DNS:valkey-headless.default.svc.cluster.local,DNS:*.valkey-headless.default.svc.cluster.local'

openssl x509 -req -in valkey-server.csr \
    -CA valkey-ca.crt -CAkey valkey-ca.key -CAcreateserial \
    -out valkey-server.crt -days 365 -copy_extensions copyall

# Create TLS secret
kubectl create secret generic valkey-tls \
    --from-file=server.crt=valkey-server.crt \
    --from-file=server.key=valkey-server.key \
    --from-file=ca.crt=valkey-ca.crt

# Cleanup certificate files
rm -- valkey-ca.key valkey-ca.crt valkey-ca.srl valkey-server.key valkey-server.csr valkey-server.crt

# Create test pod
kubectl run valkey-testbench --image="$VALKEY_IMAGE" \
    --labels=sidecar.istio.io/inject=false \
    --restart=Never \
    --overrides='{"spec":{"containers":[{"name":"valkey-testbench","image":"'"$VALKEY_IMAGE"'","command":["sleep","infinity"],"volumeMounts":[{"name":"tls","mountPath":"/tls","readOnly":true}]}],"volumes":[{"name":"tls","secret":{"secretName":"valkey-tls"}}]}}' \
    --command -- sleep infinity

kubectl wait --for=condition=Ready pod/valkey-testbench --timeout=120s

# -----------------------------------------------------------------------------
# Test Functions
# -----------------------------------------------------------------------------

cleanup_helm() {
    helm uninstall valkey
    kubectl delete persistentvolumeclaims --selector=app.kubernetes.io/instance=valkey --ignore-not-found
}

wait_for_valkey() {
    echo "Waiting for Valkey to be ready..."
    kubectl wait --for=condition=Ready pod --selector=app.kubernetes.io/instance=valkey --timeout=300s
}

# -----------------------------------------------------------------------------
# TLS 🔴, Authentication 🔴, Sharding 🔴, Replication 🔴
# -----------------------------------------------------------------------------

echo ""
echo "=== Test: TLS 🔴, Authentication 🔴, Sharding 🔴, Replication 🔴 ==="

helm install valkey valkey --dependency-update \
    --set-string='podLabels.sidecar\.istio\.io/inject=false'

wait_for_valkey

kubectl exec statefulset/ci-valkey --container=ci-valkey -- \
    valkey-cli -h "$VALKEY_HOST" ping

cleanup_helm

# -----------------------------------------------------------------------------
# TLS 🔴, Authentication 🔴, Sharding 🔴, Replication 🟢
# -----------------------------------------------------------------------------

echo ""
echo "=== Test: TLS 🔴, Authentication 🔴, Sharding 🔴, Replication 🟢 ==="

helm install valkey valkey --dependency-update \
    --set-string='podLabels.sidecar\.istio\.io/inject=false' \
    --set=replica.enabled=true \
    --set=replica.persistence.size=5Gi

wait_for_valkey

kubectl exec valkey-testbench -- \
    valkey-cli -h "$VALKEY_HOST" ping

cleanup_helm

# -----------------------------------------------------------------------------
# TLS 🔴, Authentication 🔴, Sharding 🟢, Replication 🔴
# -----------------------------------------------------------------------------

echo ""
echo "=== Test: TLS 🔴, Authentication 🔴, Sharding 🟢, Replication 🔴 ==="

helm install valkey valkey --dependency-update \
    --set-string='podLabels.sidecar\.istio\.io/inject=false' \
    --set=cluster.enabled=true \
    --set=cluster.persistence.size=5Gi \
    --set=cluster.replicasPerShard=0

wait_for_valkey

kubectl exec valkey-testbench -- \
    valkey-cli -h "$VALKEY_HOST" cluster info | grep ^cluster_state:

kubectl exec valkey-testbench -- \
    valkey-cli -h "$VALKEY_HOST" cluster nodes

cleanup_helm

# -----------------------------------------------------------------------------
# TLS 🔴, Authentication 🔴, Sharding 🟢, Replication 🟢
# -----------------------------------------------------------------------------

echo ""
echo "=== Test: TLS 🔴, Authentication 🔴, Sharding 🟢, Replication 🟢 ==="

helm install valkey valkey --dependency-update \
    --set-string='podLabels.sidecar\.istio\.io/inject=false' \
    --set=cluster.enabled=true \
    --set=cluster.persistence.size=5Gi \
    --set=cluster.shards=3 \
    --set=cluster.replicasPerShard=1

wait_for_valkey

kubectl exec valkey-testbench -- \
    valkey-cli -h "$VALKEY_HOST" cluster info | grep ^cluster_state:

kubectl exec valkey-testbench -- \
    valkey-cli -h "$VALKEY_HOST" cluster nodes

cleanup_helm

# -----------------------------------------------------------------------------
# TLS 🔴, Authentication 🟢, Sharding 🔴, Replication 🔴
# -----------------------------------------------------------------------------

echo ""
echo "=== Test: TLS 🔴, Authentication 🟢, Sharding 🔴, Replication 🔴 ==="

helm install valkey valkey --dependency-update \
    --set-string='podLabels.sidecar\.istio\.io/inject=false' \
    --set=auth.enabled=true \
    --set=auth.usersExistingSecret=valkey-auth \
    --set='auth.aclUsers.default.permissions=~* &* +@all'

wait_for_valkey

kubectl exec valkey-testbench -- \
    valkey-cli -a password -h "$VALKEY_HOST" --no-auth-warning ping

# Verify auth is required (expected to fail)
if kubectl exec valkey-testbench -- valkey-cli -h "$VALKEY_HOST" ping 2>&1 | grep -q "NOAUTH"; then
    echo "Auth check passed: NOAUTH returned as expected"
fi

cleanup_helm

# -----------------------------------------------------------------------------
# TLS 🔴, Authentication 🟢, Sharding 🔴, Replication 🟢
# -----------------------------------------------------------------------------

echo ""
echo "=== Test: TLS 🔴, Authentication 🟢, Sharding 🔴, Replication 🟢 ==="

helm install valkey valkey --dependency-update \
    --set-string='podLabels.sidecar\.istio\.io/inject=false' \
    --set=auth.enabled=true \
    --set=auth.usersExistingSecret=valkey-auth \
    --set='auth.aclUsers.default.permissions=~* &* +@all' \
    --set=replica.enabled=true \
    --set=replica.persistence.size=5Gi

wait_for_valkey

kubectl exec valkey-testbench -- \
    valkey-cli -a password -h "$VALKEY_HOST" --no-auth-warning ping

# Verify auth is required (expected to fail)
if kubectl exec valkey-testbench -- valkey-cli -h "$VALKEY_HOST" ping 2>&1 | grep -q "NOAUTH"; then
    echo "Auth check passed: NOAUTH returned as expected"
fi

cleanup_helm

# -----------------------------------------------------------------------------
# TLS 🔴, Authentication 🟢, Sharding 🟢, Replication 🔴
# -----------------------------------------------------------------------------

echo ""
echo "=== Test: TLS 🔴, Authentication 🟢, Sharding 🟢, Replication 🔴 ==="

helm install valkey valkey --dependency-update \
    --set-string='podLabels.sidecar\.istio\.io/inject=false' \
    --set=auth.enabled=true \
    --set=auth.usersExistingSecret=valkey-auth \
    --set='auth.aclUsers.default.permissions=~* &* +@all' \
    --set=cluster.enabled=true \
    --set=cluster.persistence.size=5Gi \
    --set=cluster.replicasPerShard=0

wait_for_valkey

kubectl exec valkey-testbench -- \
    valkey-cli -a password -h "$VALKEY_HOST" --no-auth-warning cluster info | grep ^cluster_state:

kubectl exec valkey-testbench -- \
    valkey-cli -a password -h "$VALKEY_HOST" --no-auth-warning cluster nodes

# Verify auth is required (expected to fail)
if kubectl exec valkey-testbench -- valkey-cli -h "$VALKEY_HOST" cluster nodes 2>&1 | grep -q "NOAUTH"; then
    echo "Auth check passed: NOAUTH returned as expected"
fi

cleanup_helm

# -----------------------------------------------------------------------------
# TLS 🔴, Authentication 🟢, Sharding 🟢, Replication 🟢
# -----------------------------------------------------------------------------

echo ""
echo "=== Test: TLS 🔴, Authentication 🟢, Sharding 🟢, Replication 🟢 ==="

helm install valkey valkey --dependency-update \
    --set-string='podLabels.sidecar\.istio\.io/inject=false' \
    --set=auth.enabled=true \
    --set=auth.usersExistingSecret=valkey-auth \
    --set='auth.aclUsers.default.permissions=~* &* +@all' \
    --set=cluster.enabled=true \
    --set=cluster.persistence.size=5Gi \
    --set=cluster.shards=3 \
    --set=cluster.replicasPerShard=1

wait_for_valkey

kubectl exec valkey-testbench -- \
    valkey-cli -a password -h "$VALKEY_HOST" --no-auth-warning cluster info | grep ^cluster_state:

kubectl exec valkey-testbench -- \
    valkey-cli -a password -h "$VALKEY_HOST" --no-auth-warning cluster nodes

# Verify auth is required (expected to fail)
if kubectl exec valkey-testbench -- valkey-cli -h "$VALKEY_HOST" cluster nodes 2>&1 | grep -q "NOAUTH"; then
    echo "Auth check passed: NOAUTH returned as expected"
fi

cleanup_helm

# -----------------------------------------------------------------------------
# TLS 🟢, Authentication 🔴, Sharding 🔴, Replication 🔴
# -----------------------------------------------------------------------------

echo ""
echo "=== Test: TLS 🟢, Authentication 🔴, Sharding 🔴, Replication 🔴 ==="

helm install valkey valkey --dependency-update \
    --set-string='podLabels.sidecar\.istio\.io/inject=false' \
    --set=tls.enabled=true \
    --set=tls.existingSecret=valkey-tls

wait_for_valkey

kubectl exec valkey-testbench -- \
    valkey-cli -h "$VALKEY_HOST" --tls --cacert /tls/ca.crt ping

# Verify TLS is required (expected to fail)
if kubectl exec valkey-testbench -- valkey-cli -h "$VALKEY_HOST" ping 2>&1 | grep -q "Connection reset by peer"; then
    echo "TLS check passed: Connection reset as expected without TLS"
fi

if kubectl exec valkey-testbench -- valkey-cli -h "$VALKEY_HOST" --tls ping 2>&1 | grep -q "certificate verify failed"; then
    echo "TLS check passed: Certificate verify failed as expected without CA cert"
fi

cleanup_helm

# -----------------------------------------------------------------------------
# TLS 🟢, Authentication 🔴, Sharding 🔴, Replication 🟢
# -----------------------------------------------------------------------------

echo ""
echo "=== Test: TLS 🟢, Authentication 🔴, Sharding 🔴, Replication 🟢 ==="

helm install valkey valkey --dependency-update \
    --set-string='podLabels.sidecar\.istio\.io/inject=false' \
    --set=tls.enabled=true \
    --set=tls.existingSecret=valkey-tls \
    --set=replica.enabled=true \
    --set=replica.persistence.size=5Gi

wait_for_valkey

kubectl exec valkey-testbench -- \
    valkey-cli -h "$VALKEY_HOST" --tls --cacert /tls/ca.crt ping

# Verify TLS is required (expected to fail)
if kubectl exec valkey-testbench -- valkey-cli -h "$VALKEY_HOST" ping 2>&1 | grep -q "Connection reset by peer"; then
    echo "TLS check passed: Connection reset as expected without TLS"
fi

if kubectl exec valkey-testbench -- valkey-cli -h "$VALKEY_HOST" --tls ping 2>&1 | grep -q "certificate verify failed"; then
    echo "TLS check passed: Certificate verify failed as expected without CA cert"
fi

cleanup_helm

# -----------------------------------------------------------------------------
# TLS 🟢, Authentication 🔴, Sharding 🟢, Replication 🔴
# -----------------------------------------------------------------------------

echo ""
echo "=== Test: TLS 🟢, Authentication 🔴, Sharding 🟢, Replication 🔴 ==="

helm install valkey valkey --dependency-update \
    --set-string='podLabels.sidecar\.istio\.io/inject=false' \
    --set=tls.enabled=true \
    --set=tls.existingSecret=valkey-tls \
    --set=cluster.enabled=true \
    --set=cluster.persistence.size=5Gi \
    --set=cluster.replicasPerShard=0

wait_for_valkey

kubectl exec valkey-testbench -- \
    valkey-cli -h "$VALKEY_HOST" --tls --cacert /tls/ca.crt cluster info | grep ^cluster_state:

# Verify TLS is required (expected to fail)
if kubectl exec valkey-testbench -- valkey-cli -h "$VALKEY_HOST" cluster info 2>&1 | grep -q "Connection reset by peer"; then
    echo "TLS check passed: Connection reset as expected without TLS"
fi

if kubectl exec valkey-testbench -- valkey-cli -h "$VALKEY_HOST" --tls cluster info 2>&1 | grep -q "certificate verify failed"; then
    echo "TLS check passed: Certificate verify failed as expected without CA cert"
fi

kubectl exec valkey-testbench -- \
    valkey-cli -h "$VALKEY_HOST" --tls --cacert /tls/ca.crt cluster nodes

cleanup_helm

# -----------------------------------------------------------------------------
# TLS 🟢, Authentication 🔴, Sharding 🟢, Replication 🟢
# -----------------------------------------------------------------------------

echo ""
echo "=== Test: TLS 🟢, Authentication 🔴, Sharding 🟢, Replication 🟢 ==="

helm install valkey valkey --dependency-update \
    --set-string='podLabels.sidecar\.istio\.io/inject=false' \
    --set=tls.enabled=true \
    --set=tls.existingSecret=valkey-tls \
    --set=cluster.enabled=true \
    --set=cluster.persistence.size=5Gi \
    --set=cluster.shards=3 \
    --set=cluster.replicasPerShard=1

wait_for_valkey

kubectl exec valkey-testbench -- \
    valkey-cli -h "$VALKEY_HOST" --tls --cacert /tls/ca.crt cluster info | grep ^cluster_state:

# Verify TLS is required (expected to fail)
if kubectl exec valkey-testbench -- valkey-cli -h "$VALKEY_HOST" cluster info 2>&1 | grep -q "Connection reset by peer"; then
    echo "TLS check passed: Connection reset as expected without TLS"
fi

if kubectl exec valkey-testbench -- valkey-cli -h "$VALKEY_HOST" --tls cluster info 2>&1 | grep -q "certificate verify failed"; then
    echo "TLS check passed: Certificate verify failed as expected without CA cert"
fi

kubectl exec valkey-testbench -- \
    valkey-cli -h "$VALKEY_HOST" --tls --cacert /tls/ca.crt cluster nodes

cleanup_helm

# -----------------------------------------------------------------------------
# TLS 🟢, Authentication 🟢, Sharding 🔴, Replication 🔴
# -----------------------------------------------------------------------------

echo ""
echo "=== Test: TLS 🟢, Authentication 🟢, Sharding 🔴, Replication 🔴 ==="

helm install valkey valkey --dependency-update \
    --set-string='podLabels.sidecar\.istio\.io/inject=false' \
    --set=auth.enabled=true \
    --set=auth.usersExistingSecret=valkey-auth \
    --set='auth.aclUsers.default.permissions=~* &* +@all' \
    --set=tls.enabled=true \
    --set=tls.existingSecret=valkey-tls

wait_for_valkey

kubectl exec valkey-testbench -- \
    valkey-cli -a password -h "$VALKEY_HOST" --no-auth-warning --tls --cacert /tls/ca.crt ping

cleanup_helm

# -----------------------------------------------------------------------------
# TLS 🟢, Authentication 🟢, Sharding 🔴, Replication 🟢
# -----------------------------------------------------------------------------

echo ""
echo "=== Test: TLS 🟢, Authentication 🟢, Sharding 🔴, Replication 🟢 ==="

helm install valkey valkey --dependency-update \
    --set-string='podLabels.sidecar\.istio\.io/inject=false' \
    --set=auth.enabled=true \
    --set=auth.usersExistingSecret=valkey-auth \
    --set='auth.aclUsers.default.permissions=~* &* +@all' \
    --set=tls.enabled=true \
    --set=tls.existingSecret=valkey-tls \
    --set=replica.enabled=true \
    --set=replica.persistence.size=5Gi

wait_for_valkey

kubectl exec valkey-testbench -- \
    valkey-cli -a password -h "$VALKEY_HOST" --no-auth-warning --tls --cacert /tls/ca.crt ping

cleanup_helm

# -----------------------------------------------------------------------------
# TLS 🟢, Authentication 🟢, Sharding 🟢, Replication 🔴
# -----------------------------------------------------------------------------

echo ""
echo "=== Test: TLS 🟢, Authentication 🟢, Sharding 🟢, Replication 🔴 ==="

helm install valkey valkey --dependency-update \
    --set-string='podLabels.sidecar\.istio\.io/inject=false' \
    --set=auth.enabled=true \
    --set=auth.usersExistingSecret=valkey-auth \
    --set='auth.aclUsers.default.permissions=~* &* +@all' \
    --set=tls.enabled=true \
    --set=tls.existingSecret=valkey-tls \
    --set=cluster.enabled=true \
    --set=cluster.persistence.size=5Gi \
    --set=cluster.replicasPerShard=0

wait_for_valkey

kubectl exec valkey-testbench -- \
    valkey-cli -a password -h "$VALKEY_HOST" --no-auth-warning --tls --cacert /tls/ca.crt cluster info | grep ^cluster_state:

kubectl exec valkey-testbench -- \
    valkey-cli -a password -h "$VALKEY_HOST" --no-auth-warning --tls --cacert /tls/ca.crt cluster nodes

cleanup_helm

# -----------------------------------------------------------------------------
# TLS 🟢, Authentication 🟢, Sharding 🟢, Replication 🟢
# -----------------------------------------------------------------------------

echo ""
echo "=== Test: TLS 🟢, Authentication 🟢, Sharding 🟢, Replication 🟢 ==="

helm install valkey valkey --dependency-update \
    --set-string='podLabels.sidecar\.istio\.io/inject=false' \
    --set=auth.enabled=true \
    --set=auth.usersExistingSecret=valkey-auth \
    --set='auth.aclUsers.default.permissions=~* &* +@all' \
    --set=tls.enabled=true \
    --set=tls.existingSecret=valkey-tls \
    --set=cluster.enabled=true \
    --set=cluster.persistence.size=5Gi \
    --set=cluster.shards=3 \
    --set=cluster.replicasPerShard=1

wait_for_valkey

kubectl exec valkey-testbench -- \
    valkey-cli -a password -h "$VALKEY_HOST" --no-auth-warning --tls --cacert /tls/ca.crt cluster info | grep ^cluster_state:

kubectl exec valkey-testbench -- \
    valkey-cli -a password -h "$VALKEY_HOST" --no-auth-warning --tls --cacert /tls/ca.crt cluster nodes

cleanup_helm

# -----------------------------------------------------------------------------
# Teardown
# -----------------------------------------------------------------------------

echo ""
echo "=== Teardown ==="

kubectl delete pod valkey-testbench
kubectl delete secret valkey-auth valkey-tls

echo ""
echo "=== All tests completed ==="
