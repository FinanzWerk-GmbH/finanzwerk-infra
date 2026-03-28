#!/bin/bash
minikube start \
  --cpus=4 \
  --memory=8192 \
  --disk-size=50g \
  --driver=docker

# Wait for API server to be ready
kubectl wait --for=condition=Ready node/minikube --timeout=120s

cd "$(dirname "$0")/.." || exit 1

minikube addons enable ingress
minikube addons enable ingress-dns

kubectl apply --server-side -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.29/releases/cnpg-1.29.0.yaml
kubectl wait --for=condition=established crd/clusters.postgresql.cnpg.io --timeout=60s
kubectl rollout status deployment/cnpg-controller-manager -n cnpg-system --timeout=120s

sudo -E minikube tunnel