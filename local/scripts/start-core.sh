#!/bin/bash
minikube start \
  --cpus=4 \
  --memory=10240 \
  --disk-size=50g \
  --driver=docker

# Wait for API server to be ready
kubectl wait --for=condition=Ready node/minikube --timeout=120s

cd "$(dirname "$0")/.."

minikube addons enable ingress
minikube addons enable ingress-dns
