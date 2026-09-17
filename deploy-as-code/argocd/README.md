# ArgoCD — Livelihood GitOps

A single ArgoCD instance, hosted on **`livelihood-prod`**, deploys and reconciles the
`core-services` Helm charts across three environments (dev / uat / prod) by watching
three git branches. This replaces manual `helmfile apply` runs with git-driven
continuous deployment.

## Architecture

```
kubectl apply bootstrap-<env>.yaml        (one-time, by hand, per environment)
  └─ Application "gitops-platform-<env>"  (installed into argocd/, on the hub)
       └─ renders platform/ chart with values-<env>.yaml
            ├─ AppProject "livelihood-devops-<env>"       (security boundary)
            └─ ApplicationSet "livelihood-devops-<env>"   (git directory generator)
                 └─ scans core-services/* on the env's branch
                      └─ N child Applications (one per service directory)
                           └─ rendered via the sops-helm CMP plugin:
                                helm template <svc> . -f <env>.yaml \
                                                        -f <env>-tags.yaml \
                                                        -f <(decrypted) <env>-secrets.yaml
                           └─ applied to the env's destination cluster/namespace
```

Everything below `bootstrap/` is GitOps-managed. `bootstrap/` itself is the only
manual step per environment.

## Files, and why each exists

| Path | Purpose |
|---|---|
| `helm/` | Vendored `argo-helm/argo-cd` chart (v10.1.3 / ArgoCD v3.4.5) — the ArgoCD control plane itself (server, repo-server, application-controller, dex, redis). Only local edit: `global.domain`. |
| `repo-server-cmp/values.yaml` | Adds the **`sops-helm` Config Management Plugin** sidecar to `argocd-repo-server`, so SOPS-encrypted `*-secrets.yaml` files are decrypted at render time (see [CMP plugin](#cmp-plugin-sops-helm) below). Grants the repo-server an IRSA identity for KMS decrypt. |
| `controller-cross-cluster-values.yaml` | Grants `argocd-application-controller` an IRSA identity and registers `livelihood-dev` / `livelihood-uat` as remote clusters, so one hub ArgoCD can manage all three environments' clusters. |
| `node-placement-values.yaml` | Pins every ArgoCD component onto the node reserved for this workload on `livelihood-prod` (taint `cpu=true:NoSchedule`, label `accelerator=none`), via `global.nodeSelector` / `global.tolerations`. |
| `platform/` | Small chart templating exactly two objects per environment: an `AppProject` (security boundary — one source repo, one destination, no `Ingress`, no cluster-scoped resources) and an `ApplicationSet` (git directory generator over `core-services/*`). `values-{dev,uat,prod}.yaml` set the branch, destination cluster, and sync policy per env. |
| `bootstrap/` | One `Application` per environment (app-of-apps root), installed once by hand into the hub's `argocd` namespace, pointing at `platform/` with the matching values file. |

## Install

```bash
helm upgrade --install argocd deploy-as-code/argocd/helm -n argocd --create-namespace \
  -f deploy-as-code/argocd/helm/values.yaml \
  -f deploy-as-code/argocd/repo-server-cmp/values.yaml \
  -f deploy-as-code/argocd/controller-cross-cluster-values.yaml \
  -f deploy-as-code/argocd/node-placement-values.yaml \
  --kube-context <livelihood-prod context>
```

Then, per environment:

```bash
kubectl --context <livelihood-prod context> apply -f deploy-as-code/argocd/bootstrap/bootstrap-uat.yaml
```

## Cross-cluster authentication

`livelihood-dev`, `livelihood-uat`, `livelihood-prod` are separate EKS clusters in
separate VPCs. The hub reaches the other two via IRSA + EKS access entries — no
static kubeconfigs or long-lived tokens.

| Role | Trusts (OIDC + subject) | Grants |
|---|---|---|
| `livelihood-prod-cross-cluster-access` | `livelihood-prod` OIDC → SA `argocd:argocd-application-controller` | Nothing extra — `awsAuthConfig` token exchange needs only the trust relationship. |
| `livelihood-prod-eks-kms-access` | `livelihood-prod` OIDC → SA `argocd:argocd-repo-server` | `kms:Decrypt` + `kms:DescribeKey` on the prod/dev/uat SOPS keys (`charts/.sops.yaml`). |

Authorization on the *target* cluster is separate from authentication: each managed
cluster needs an **EKS access entry** mapping `livelihood-prod-cross-cluster-access`
to a Kubernetes group, plus a namespace-scoped `Role`/`RoleBinding` for that group
(scoped to `core`, matching the `AppProject`). Example (UAT):

```bash
aws eks create-access-entry \
  --cluster-name livelihood-uat --region ap-south-2 \
  --principal-arn arn:aws:iam::<account>:role/livelihood-prod-cross-cluster-access \
  --type STANDARD --kubernetes-groups argocd-cross-cluster
# + a Role/RoleBinding for that group in namespace `core` on livelihood-uat
```

Cluster registration in `controller-cross-cluster-values.yaml` uses `awsAuthConfig`
(ArgoCD's native AWS SDK auth), **not** `execProviderConfig`/`aws eks get-token` —
the stock ArgoCD image has no `aws` CLI binary, so the exec-based approach doesn't
work.

## CMP plugin: `sops-helm`

Every `core-services` chart is rendered through a plugin (defined in
`repo-server-cmp/values.yaml`) rather than plain Helm, because the
`*-secrets.yaml` value files are SOPS/KMS-encrypted in git:

```bash
helm dependency build                  # init — resolves the `common` chart dependency
# generate:
release_name="${PARAM_RELEASE_NAME:-$ARGOCD_APP_NAME}"
for each PARAM_VALUES_FILES_N:
  if filename contains "secrets": decrypt with `sops -d` into a real temp file (mktemp), pass -f <tempfile>
  else:                            pass -f <file> as-is
helm template "$release_name" . "${values_args[@]}"
```

**Note on the decrypt step:** this uses `mktemp` + `trap ... EXIT` to clean up,
*not* bash process substitution (`<(sops -d "$file")`). Process substitution
originally failed with `open /dev/fd/N: no such file or directory` — ArgoCD's CMP
server execs this script through its own gRPC/exec wrapper, which tears down the
process-substitution pipe before the separately-exec'd `helm` binary can open it.
Real temp files (unique per invocation, `0600`, owned by the sidecar's non-root
user) sidestep this entirely.

## Sync policy per environment

| Env | Branch | Destination | Sync |
|---|---|---|---|
| dev | `develop` | remote `livelihood-dev` | automated (`prune`, `selfHeal`) |
| uat | `uat` | remote `livelihood-uat` | **manual** — UAT's `core` namespace has ~34 pre-existing helmfile-managed releases; manual sync lets each one be diffed and adopted deliberately instead of ArgoCD taking over (and potentially pruning) on first contact |
| prod | `Prod` | in-cluster (`https://kubernetes.default.svc`) | **manual** |

The `bootstrap/*.yaml` Applications themselves are auto-synced (`automated:
{prune: true, selfHeal: true}`) regardless of environment — that only keeps the
`AppProject`/`ApplicationSet` **definitions** current with git on the hub. It does
not affect the sync policy of the generated child Applications that actually touch
workloads in `core`, which is controlled separately by `platform/values-<env>.yaml`.

Flip an environment to auto-sync by adding an `automated:` block under
`applicationset.syncPolicy` in its `values-<env>.yaml` (see `values-dev.yaml` for
the shape when the key is omitted entirely, vs. `values-uat.yaml` /
`values-prod.yaml` for the manual form).

## Operational notes

- **Manifest cache**: the repo-server caches failed manifest generations. After
  fixing a plugin/config issue, force `kubectl -n argocd annotate application
  <name> argocd.argoproj.io/refresh=hard --overwrite` rather than waiting — a
  normal refresh can replay a stale cached error.
- **Config changes to `repo-server-cmp/values.yaml` or `controller-cross-cluster-values.yaml`**
  require both a `helm upgrade` (to update the ConfigMap) and a
  `kubectl rollout restart deploy/argocd-repo-server` (the CMP sidecar reads its
  plugin config at process start, not on every call).
- **UAT adoption**: on first sync per app, ArgoCD does not create or touch a Helm
  release object — it renders with `helm template` and applies via
  `kubectl apply`/server-side apply, so it coexists with (and can incrementally
  adopt) resources originally deployed via `helmfile`.
