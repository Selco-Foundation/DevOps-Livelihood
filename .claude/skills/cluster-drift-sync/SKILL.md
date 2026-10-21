---
name: cluster-drift-sync
description: Sync the DevOps-Livelihood GitHub repo with manual changes made directly in the livelihood-dev cluster. Branches from `develop`, renders each service with helm dependency build + helm template (keys sorted with yq), diffs it against the live object from kubectl, patches the repo (charts and environment values) to match the cluster, and re-verifies. Use before migrating the dev environment to another cluster or whenever someone asks "is the repo up to date with the cluster?".
---

# cluster-drift-sync

Goal: make `develop` the source of truth again. Anything that was changed by hand in the cluster (image tags, env vars, replicas, resources, configmaps, ingress, etc.) must be reflected in the repo, so the repo can recreate the environment on a new cluster.

Repo root: `/home/bhcp0084/Desktop/work/Selco-Foundation/DevOps-Livelihood`
Helmfile entrypoint: `deploy-as-code/digit-helmfile.yaml`, which includes per-group helmfiles:

| Group | Helmfile | Namespace |
|---|---|---|
| core services | `deploy-as-code/charts/core-services/coreservices-helmfile.yaml` | `core` |
| backbone services | `deploy-as-code/charts/backbone-services/backboneservices-helmfile.yaml` | `backbone` |
| monitoring | `deploy-as-code/charts/monitoring/monitoring-helmfile.yaml` | (see file) |

Environment values: `deploy-as-code/charts/environments/livelihood-dev.yaml`, `livelihood-dev-tags.yaml` (image tags) and `livelihood-dev-secrets.yaml`. Helmfile reads them via `HELMFILE_ENV=livelihood-dev`.

**Many releases in these helmfiles are commented out**, and the entrypoint also comments out whole groups. "Commented" does not mean "not in the cluster". Always include them in the comparison if they are running in the cluster.

## Ground rules

- Cluster access is **read-only**: only `kubectl get/describe/diff/api-resources/config`. Never `apply`, `delete`, `patch`, `edit`, `rollout`, or `helm install/upgrade`. The goal is to change the repo, not the cluster.
- Confirm the context first: `kubectl config current-context` must be `arn:aws:eks:ap-south-2:654654556600:cluster/livelihood-dev`. If not, stop and ask.
- **Never print Secret values** (not in diffs, not in the report, not in commit messages). Exclude `kind: Secret` from `kubectl diff`/`get -o yaml` output. Compare Secrets by key names only (`kubectl get secret X -o json | jq '.data | keys'`). Real values belong only in `livelihood-dev-secrets.yaml`, and only if that file is already where they live. Do not copy any new secret value into git without asking the user.
- Use the scratchpad dir for all temp files, never commit them.
- Do not commit or push unless the user asks. Prepare the branch and the changes; report; let the user decide.
- Cluster state wins for "what is deployed", but use judgment: transient things (pod restarts, `deployment.kubernetes.io/revision`, `status`, HPA-driven replica counts, Argo/Helm bookkeeping annotations) are not drift. List anything ambiguous for the user instead of guessing.

## Step 1: Create a working branch from `develop`

If the user only asked to *check* drift, skip this step: run Steps 2–4 read-only, report the drift table, and create the branch only once they approve fixes.

```bash
cd /home/bhcp0084/Desktop/work/Selco-Foundation/DevOps-Livelihood
git fetch origin
git status --short            # must be clean (untracked .claude/ is fine), otherwise stop and ask
git checkout develop && git pull --ff-only origin develop
git checkout -b sync/cluster-drift-$(date +%Y%m%d)
```

(The user may say "repository" but means a branch off `develop`. Do not fork or create a new GitHub repo.)

## Step 2: Inventory what is in the cluster

Namespaces that matter: `core`, `backbone` (plus `argocd`, only to understand how things were deployed; check `kubectl -n argocd get applications.argoproj.io` and note whether Argo auto-sync/self-heal is on, since it affects which manual changes could even have survived).

```bash
SCR=<scratchpad dir>
mkdir -p $SCR/live
for ns in core backbone; do
  kubectl -n $ns get deploy,sts,ds,cronjob,job,svc,ingress,cm,hpa,pvc,sa -o name > $SCR/live/$ns-resources.txt
done
kubectl get deploy,sts -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,REPLICAS:.spec.replicas,IMAGE:.spec.template.spec.containers[*].image \
  | grep -E '^(core|backbone) ' > $SCR/live/workloads.txt
```

Build a list of **every release name** in the helmfiles, commented or not:

```bash
grep -hE '^\s*#?\s*-\s*name:' deploy-as-code/charts/*/*helmfile.yaml | sed -E 's/^\s*#?\s*-\s*name:\s*//; s/\s*#.*//' | sort -u
```

Cross-check against cluster workloads and note three buckets:
1. In cluster and in helmfile (active): diff normally.
2. In cluster, helmfile entry **commented out**: diff it too (Step 3 enables it).
3. In cluster, **no chart/helmfile entry at all**: this is a missing chart. Needs a new chart under `deploy-as-code/charts/...`. Reverse-engineer from `kubectl get ... -o yaml` (strip status/uid/resourceVersion/managedFields/creationTimestamp), following the layout of a similar existing chart (see `charts/common-chart-template` and a sibling like `charts/core-services/vendor-registry`).

Also note the reverse: releases enabled in the helmfile but not in the cluster.

## Step 3: Render each service with `helm template`

Work **per service** (release), not per helmfile. No helmfile copies are needed, so commented-out releases are handled by simply naming the chart directory. Chart dirs live at `deploy-as-code/charts/<group>/<svc>` (group = `core-services`, `backbone-services`, `monitoring`, ...). The namespace comes from the `namespace:` of the release's helmfile (`core` for core-services, `backbone` for backbone-services; check `templates.default` or the release itself).

Normalization lives in [normalize.yq](normalize.yq) (next to this file). It drops status/uid/resourceVersion/managedFields/helm bookkeeping/restart and deployment-timestamp annotations, sorts every named list (containers, env, ports, volumes) by `name`, drops null values and empty maps, strips quoting style and comments, and sorts map keys, so both sides are comparable.

```bash
SK=/home/bhcp0084/Desktop/work/Selco-Foundation/DevOps-Livelihood/.claude/skills/cluster-drift-sync
SCR=<scratchpad dir>; mkdir -p $SCR/repo $SCR/live
cd /home/bhcp0084/Desktop/work/Selco-Foundation/DevOps-Livelihood/deploy-as-code/charts
GROUP=core-services; SVC=asset-registry; NS=core      # per service; NS from the helmfile
mkdir -p $SCR/repo/$SVC

# 1. fetch chart dependencies (e.g. the `common` library chart); artifacts are gitignored
helm dependency build $GROUP/$SVC

# 2. render with the environment values (same order as the helmfile: tags, secrets, env),
#    drop Secrets, normalize + sort keys with yq
helm template $SVC $GROUP/$SVC -n $NS --set namespace=$NS \
    -f environments/livelihood-dev-tags.yaml \
    -f environments/livelihood-dev-secrets.yaml \
    -f environments/livelihood-dev.yaml \
  | yq 'select(.kind == "Deployment")' \
  | yq -P --from-file $SK/normalize.yq | cat > $SCR/repo/$SVC/Deployment.yaml
```

Notes:
- **yq is the snap build (`/snap/bin/yq`, mikefarah v4)**. It is confined: it can read files under `$HOME` but **not under `/tmp`**, and it **exits 1 silently with no output whenever its stdout is not a pipe**: any `> file` redirect (even under `$HOME`) and even the Bash tool's own captured output. So: always feed it through **stdin** (`cmd | yq ...`), and end **every** yq pipeline with `| cat` (`| cat > file` to save). Empty output from a yq command means this, not "no result". keep the filter file in the skill dir (`--from-file`, not `-f`, which is `--front-matter`), and do not use `yq -s` (it writes split files to cwd). To split a multi-doc render into per-kind files, run one `select(.kind == "<Kind>")` pass per kind, as above.
- Do the `select(...)` before the normalize pass (as in the pipeline) so `normalize.yq` sees a single document.
- `--set namespace=$NS` is required: the helmfile passes `namespace` as a value, and charts use it for `metadata.namespace`. The env files are keyed by release name at the top level (e.g. `asset-registry:`), so no per-release extraction is needed.
- Never write Secrets to disk or print them: render only the kinds you diff and never `select(.kind == "Secret")`. Compare Secrets by key names only.
- Render the other kinds the chart emits the same way (`Service`, `Ingress`, `HorizontalPodAutoscaler`, `ConfigMap`, `StatefulSet`, `CronJob`, ...). List them with `helm template ... | yq '.kind' | sort | uniq -c` (stdin).
- Render errors (missing values, bad templates, missing dependency) are drift symptoms too. Report them.

To loop over every release: take the names from the inventory in Step 2 (commented or not), map each to its group dir, and repeat. Releases with no chart dir are the "missing chart" bucket from Step 2.

## Step 4: Compare rendered vs live, per service

Fetch the same object from the cluster, normalize it with the same filter, and diff (`-` = live, `+` = repo):

```bash
kubectl get deployment -n $NS $SVC -o yaml \
  | yq -P --from-file $SK/normalize.yq | cat > $SCR/live/$SVC-Deployment.yaml

diff -u $SCR/live/$SVC-Deployment.yaml $SCR/repo/$SVC/Deployment.yaml
```

- A `-` line (live) absent from the repo means the repo must **gain** it. A `+` line means the repo is ahead (or someone reverted it by hand): ask the user which wins.
- Use the same pattern for the other kinds the chart renders (`service`, `ingress`, `hpa`, `configmap`, `statefulset`, ...). If the workload is a StatefulSet/DaemonSet/CronJob, use that kind in both the `select` and the `kubectl get`. Never fetch or print `secret` objects (key names only).
- Server-defaulted fields appear as live-only noise: `terminationMessagePath/Policy`, `dnsPolicy`, `restartPolicy`, `schedulerName`, `terminationGracePeriodSeconds`, `progressDeadlineSeconds`, `revisionHistoryLimit`, `strategy.type`/`maxSurge`, `scheme: HTTP` on probes, `port.protocol`, `clusterIP*`, `ingress.status`. A repo-only `metadata.annotations: {}` is also noise. Ignore them, plus transient items such as HPA-driven replica counts. List anything ambiguous instead of guessing.
- Live object missing for a rendered resource = "repo only". Live resource of the service with no rendered counterpart = "cluster only" (compare against `$SCR/live/*-resources.txt` from Step 2). Ignore system-managed objects: `kube-root-ca.crt`, service account tokens, `sh.helm.release.v1.*`, Argo bookkeeping, kube-system stuff, and controller-generated children (ReplicaSets, Pods, Endpoints, EndpointSlices).
- Optional context: `helm get manifest $SVC -n $NS` shows the last release, to tell "repo changed since last deploy" from "cluster hand-edited". `kubectl get deployment -n $NS $SVC --show-managed-fields -o json` lists the field managers (`kubectl-edit`, `kubectl-rollout`, `helm`) with timestamps. For image drift, the ReplicaSet history shows every hand-set image and when:
  `kubectl -n $NS get rs -l app=$SVC --sort-by=.metadata.creationTimestamp -o custom-columns=REV:.metadata.annotations.deployment\\.kubernetes\\.io/revision,CREATED:.metadata.creationTimestamp,IMAGE:.spec.template.spec.containers[0].image`

Produce a **drift table** before changing anything: release, resource, field, repo value, cluster value, proposed fix location (chart template / chart `values.yaml` / `livelihood-dev*.yaml`), and confidence (clear drift / ambiguous). Show it to the user if there are ambiguous items.

## Step 5: Fix the repo

For each confirmed drift, change the **right layer**, in this order of preference:
1. Image tags: `charts/environments/livelihood-dev-tags.yaml`. The image **name** is not there: it is `image.repository` in the chart's `values.yaml`, so a changed image name goes there.
2. Env-specific config (URLs, hosts, replicas, resources, feature flags): `charts/environments/livelihood-dev.yaml`, or the chart's `values.yaml` if the chart keeps its defaults there. Follow where sibling charts already put the same kind of value.
3. Structural changes (new env var plumbing, ports, probes, volumes, ingress paths, new resources): the chart's `templates/` and `values.yaml`. To drop a resource that is gone from the cluster, use the `common` chart's toggle in the chart's `values.yaml` instead of deleting the template (e.g. HPA: `hparam.enabled: false`, as `core-services/rms-service` does).
4. Missing release/chart: new chart dir plus an entry in the right helmfile (active, not commented, since it runs in the cluster). If an existing release is in the cluster but commented out in the helmfile, **do not silently uncomment it**. Flag it in the report and uncomment only if the user agrees (they probably will, since a new cluster should get it).
5. Secrets: add missing *keys* with placeholder values (`CHANGE_ME`) to the secrets file only if the file's convention allows it; never real values.

Keep edits minimal and match surrounding style. No reformatting of unrelated YAML.

## Step 6: Verify

1. Re-render exactly as in Step 3 (`helm dependency build` + `helm template` per changed service, since the repo changed).
2. Re-run the Step 4 diff. Expected result: no meaningful differences except the documented/accepted ones (HPA-managed replicas, bookkeeping annotations, ambiguous items the user chose to leave).
3. If differences remain, go back to Step 5. Repeat until clean. Do not claim "no drift" without re-running the diff and reading its output.
4. Cleanup: remove any `charts/` / `Chart.lock` artifacts left by `helm dependency build` that are not gitignored, then `git status` to ensure only intended files changed, and `git diff --stat`.

## Step 7: Report

Reply with:
- Context/cluster checked and branch name.
- Counts: releases compared, releases with drift, resources only in cluster, resources only in repo.
- The drift table with what changed in which file (use `[file](path)` links).
- Items needing a user decision (ambiguous drift, repo-ahead items, commented-out releases that are live, secrets needing real values).
- Verification result: state plainly if the final diff is clean or list what remains.
- Remind that nothing was committed/pushed (unless asked), and suggest the commit message / PR into `develop`.

If the user asks to commit: commit on the sync branch, push it, and open a PR to `develop` (not `main`). Don't push to `develop` directly.
