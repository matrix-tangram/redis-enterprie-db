# redis-enterprise-db Helm chart

Manages the per-database custom resources of a Redis Enterprise cluster through Helm, for CI/CD
systems that deploy charts rather than raw manifests (usually ArgoCD). It does not install the
Redis Enterprise operator or the RedisEnterpriseCluster, nor create the external secrets
(e.g. in AWS Secrets Manager) that its ExternalSecrets read.

Requires the Redis Enterprise operator CRDs (tested with operator chart 8.2.0-18) and, for
`users.*.externalSecret` and `externalSecrets`, External Secrets Operator (`external-secrets.io/v1`, tested with 2.13.0).

| Values key            | Renders                                                          |
|-----------------------|------------------------------------------------------------------|
| `databases`           | RedisEnterpriseDatabase, plus an optional Ingress (TLS passthrough, SNI) |
| `acls`                | RedisEnterpriseACL                                               |
| `roles`               | RedisEnterpriseRole (scoped to databases by name or label selector) |
| `roleBindings`        | RedisEnterpriseRoleBinding                                       |
| `clusterRoles`        | RedisEnterpriseClusterRole (all databases)                       |
| `clusterRoleBindings` | RedisEnterpriseClusterRoleBinding                                |
| `users`               | RedisEnterpriseUser, plus an optional ExternalSecret for its password |
| `externalSecrets`     | any other ExternalSecret (e.g. application connection secrets)   |

Each key is a map from resource name to settings, empty by default, so any type can have zero or
more objects. `values.yaml` documents every field. Objects go to the release namespace, which must
be the namespace of the RedisEnterpriseCluster.

## Role ACLs: predefined or custom

```yaml
acls:
  read-only: { acl: "+@read ~*" }
roles:
  db1-full-access:
    acl: { predefined: Full Access }   # ACL built into the cluster (kind redis_acl)
    databases: [db1]
  db1-read-only:
    acl: { custom: read-only }         # a RedisEnterpriseACL, from acls or created elsewhere
    databases: [db1]
```

Setting both or neither fails the render. Which ACLs are predefined depends on the cluster; some predefine only `Full Access`.

## Example

A database with external access, a read-write and a read-only user whose passwords ESO syncs from
AWS Secrets Manager (secret JSON with key `REDIS_PASSWORD`), plus the ACL, roles and bindings above:

```yaml
databases:
  db1:
    spec: { memorySize: 1GB, shardCount: 2, replication: true, tlsMode: enabled, databaseServicePort: 6379 }
    ingress: { enabled: true, host: db1.db.example.com }
acls:
  read-only: { acl: "+@read ~*" }
roles:
  db1-full-access: { acl: { predefined: Full Access }, databases: [db1] }
  db1-read-only:   { acl: { custom: read-only },       databases: [db1] }
roleBindings:
  db1-full-access: { role: db1-full-access, users: [app-rw] }
  db1-read-only:   { role: db1-read-only,   users: [app-ro] }
users:
  app-rw: { externalSecret: { remoteRef: { key: redis/my-env/db1/app-rw, property: REDIS_PASSWORD } } }
  app-ro: { externalSecret: { remoteRef: { key: redis/my-env/db1/app-ro, property: REDIS_PASSWORD } } }
```

```bash
helm template db1 . -n redis -f my-values.yaml
```

## ArgoCD

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata: { name: redis-db1, namespace: argocd }
spec:
  project: default
  sources:
    - repoURL: https://github.com/matrix-tangram/redis-enterprie-db.git
      targetRevision: main
      path: .
      helm:
        valueFiles: [$values/redis/base.yaml, $values/redis/prod.yaml]   # merged in order
    - repoURL: <repository with your values files>
      targetRevision: main
      ref: values
  destination: { server: https://kubernetes.default.svc, namespace: redis }
  syncPolicy: { automated: { prune: true } }
```

- Entries merge across value files by name. Set an entry to `null` in a later file to remove it.
- Objects carry `argocd.argoproj.io/sync-wave` annotations: ExternalSecrets and ACLs (-1),
  databases (0), users and roles (1), bindings and Ingress (2).
- ArgoCD has no built-in health check for the Redis Enterprise kinds, so a database counts as
  healthy as soon as it is created. To make later waves wait until it is active, add to `argocd-cm`:

  ```yaml
  resource.customizations.health.app.redislabs.com_RedisEnterpriseDatabase: |
    hs = { status = "Progressing", message = "" }
    if obj.status ~= nil and obj.status.status ~= nil then
      hs.message = obj.status.status
      if obj.status.status == "active" then hs.status = "Healthy" end
    end
    return hs
  ```

- Removing a database from the values (or pruning it) deletes the database and its data. To guard
  against that, add `annotations: { argocd.argoproj.io/sync-options: Prune=false }` to the entry.
