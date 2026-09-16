# CMP sidecar image for the argocd-repo-server: decrypts SOPS-encrypted
# Helm value files (selco-<env>-secrets.yaml) with AWS KMS before
# handing them to `helm template`. See values.yaml for the sidecar wiring.
FROM alpine:3.20

ARG HELM_VERSION=3.15.4
ARG SOPS_VERSION=3.9.1
ARG TARGETARCH=amd64

RUN apk add --no-cache bash ca-certificates curl git \
    && curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" -o /tmp/helm.tar.gz \
    && tar -zxf /tmp/helm.tar.gz -C /tmp \
    && mv "/tmp/linux-${TARGETARCH}/helm" /usr/local/bin/helm \
    && rm -rf /tmp/helm.tar.gz "/tmp/linux-${TARGETARCH}" \
    && curl -fsSL "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.${TARGETARCH}" -o /usr/local/bin/sops \
    && chmod +x /usr/local/bin/sops

USER 999
