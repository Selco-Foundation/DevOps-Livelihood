#!/bin/bash -e

# Allow user supplied pre userdata code
${pre_userdata}

# Amazon Linux 2023 - use nodeadm
# IMPORTANT: Update the CIDR value for your environment!
# To get your cluster's CIDR: aws eks describe-cluster --name <cluster-name> --region <region> --query 'cluster.kubernetesNetworkConfig.serviceIpv4Cidr'
cat > /tmp/nodeadm-config.yaml <<'NODEADM_EOF'
---
apiVersion: node.eks.aws/v1alpha1
kind: NodeConfig
spec:
  cluster:
    name: ${cluster_name}
    apiServerEndpoint: ${endpoint}
    certificateAuthority: ${cluster_auth_base64}
    # UPDATE THIS CIDR FOR YOUR ENVIRONMENT!
    # new-selco-dev: 172.20.0.0/16
    # new-selco-uat: 10.100.0.0/16
    # new-selco-prod: 10.100.0.0/16
    cidr: 10.100.0.0/16
  kubelet:
    config:
      maxPods: 110
    flags:
      - ${kubelet_extra_args}
      - --max-pods=110
NODEADM_EOF
/usr/bin/nodeadm init -c file:///tmp/nodeadm-config.yaml

# Allow user supplied userdata code
${additional_userdata}
