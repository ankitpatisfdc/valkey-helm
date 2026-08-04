# valkey Helm Chart

Helm charts for Valkey on Kubernetes.

| Chart | Description |
|---|---|
| [valkey](valkey/) | Standalone, replication, or cluster deployments managed directly by Helm |
| [valkey-operator](valkey-operator/) | Installs the valkey-operator for operator-managed clusters |
| [valkey-resources](valkey-resources/) | Installs operator-managed CRs (`ValkeyCluster`) |

---

## TL;DR

```bash
helm repo add valkey https://valkey.io/valkey-helm/
helm install valkey valkey/valkey
```

Cluster mode can be deployed directly with the `valkey` chart:

```bash
helm install my-cluster valkey/valkey --set cluster.enabled=true --set cluster.persistence.size=5Gi
```

Alternatively, deploy an operator-managed cluster with the `valkey-operator` and `valkey-resources` charts:

```bash
helm install valkey-operator valkey/valkey-operator -n valkey-operator-system --create-namespace
helm install my-cluster valkey/valkey-resources -n valkey
```

---

## Introduction

These charts bootstrap Valkey using the Helm package manager.

---

## Prerequisites

* Kubernetes 1.20+
* Helm 3.5+

---

## Maintainers

| Name     | Email         |
| -------- | ------------- |
| mk-raven | maikebit at gmail.com |
| sgissi   | silvio at gissilabs.com |
| jdheyburn   | joseph.heyburn at braze.com |
| Bloodraven21   | ishanij10115 at gmail.com |

---

## Slack

You can also provide feedback or join the conversation with other developers, users, and contributors on the #[Valkey-helm](https://valkey-oss-developer.slack.com/archives/C09JZ6N2AAV) Slack channel.

---

## License

BSD 3-Clause License
