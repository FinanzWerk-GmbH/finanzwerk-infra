#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

export AWS_PROFILE=dev
export AWS_PAGER=""

echo "==> terraform init (upgrade)"
terraform init -upgrade -input=false

echo "==> terraform apply"
terraform apply -auto-approve -input=false

echo "==> Configuring kubectl"
aws eks update-kubeconfig --region us-east-1 --name finanzwerk-cluster

echo "==> Airflow URL:"
kubectl get ingress -n airflow airflow \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null && echo "" || true
