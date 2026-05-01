# Valkey Helm Chart Tasks

# Run helm-unittest tests
test:
    @echo "=== Running Unit Tests ==="
    helm unittest ./valkey
    helm unittest ./valkey-operator
    helm unittest ./valkey-resources

# Lint the Helm charts
lint:
    @echo "=== Linting Helm Charts ==="
    helm lint ./valkey
    helm lint ./valkey-operator
    helm lint ./valkey-resources

# Render templates with default values
template:
    helm template valkey ./valkey

template-resources:
    helm template my-cluster ./valkey-resources

# Render templates with auth enabled
template-auth:
    helm template valkey ./valkey \
        --set auth.enabled=true \
        --set auth.generateDefaultUser.enabled=true

# Package the charts
package:
    helm package ./valkey
    helm package ./valkey-operator
    helm package ./valkey-resources

# Run all validations
validate: lint test
    @echo "=== All validations passed ==="

# Create the kind cluster and shared fixtures used by the functional suite
functional-setup:
    ./functional-tests/setup.sh

# Tear down fixtures (pass --cluster to also delete the kind cluster)
functional-teardown *ARGS:
    ./functional-tests/teardown.sh {{ARGS}}

# Run one scenario against the already-set-up kind cluster, e.g.
#   just functional-scenario off off on on off
functional-scenario tls auth shard rep istio:
    ./functional-tests/run-scenario.sh {{tls}} {{auth}} {{shard}} {{rep}} {{istio}}

# Run the full 32-scenario matrix (set FILTER='tls=on istio=on' to narrow)
functional-run:
    ./functional-tests/run-all.sh

# Full functional suite: setup + matrix + teardown including cluster
functional-test:
    ./functional-tests/setup.sh
    ./functional-tests/run-all.sh
    ./functional-tests/teardown.sh --cluster

