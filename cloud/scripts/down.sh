#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

export AWS_PROFILE=dev
export AWS_PAGER=""
REGION="us-east-1"
CLUSTER_NAME="finanzwerk-cluster"

# S3 buckets that must be emptied before terraform destroy.
# Includes versioning-enabled buckets (CloudTrail, Config, raw data).
S3_BUCKETS=(
  "finanzwerk-cloudtrail-log-storage"
  "finanzwerk-config-log-storage"
  "finanzwerk-raw-ingestion-data"
  "finanzwerk-processed-data"
)

empty_bucket() {
  local bucket="$1"
  if ! aws s3api head-bucket --bucket "$bucket" --region "$REGION" 2>/dev/null; then
    echo "    s3://$bucket not found — skipping"
    return
  fi
  echo "    emptying s3://$bucket ..."
  # Delete versioned objects
  aws s3api list-object-versions --bucket "$bucket" --region "$REGION" \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
    --output json 2>/dev/null \
    | python3 -c "
import sys, json, subprocess
data = json.load(sys.stdin)
objs = [o for o in (data.get('Objects') or []) if o['VersionId'] is not None]
if objs:
    subprocess.run(['aws','s3api','delete-objects','--bucket','$bucket','--region','$REGION',
        '--delete', json.dumps({'Objects': objs, 'Quiet': True})], check=True)
print(f'    {len(objs)} versions deleted')
"
  # Delete delete markers
  aws s3api list-object-versions --bucket "$bucket" --region "$REGION" \
    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
    --output json 2>/dev/null \
    | python3 -c "
import sys, json, subprocess
data = json.load(sys.stdin)
objs = [o for o in (data.get('Objects') or []) if o['VersionId'] is not None]
if objs:
    subprocess.run(['aws','s3api','delete-objects','--bucket','$bucket','--region','$REGION',
        '--delete', json.dumps({'Objects': objs, 'Quiet': True})], check=True)
print(f'    {len(objs)} delete markers deleted')
"
  # Sweep remaining non-versioned objects
  aws s3 rm "s3://$bucket" --recursive --region "$REGION" 2>/dev/null || true
  echo "    s3://$bucket emptied"
}

# ── 1. Stop AWS Config (writes continuously to S3) ───────────────────────────
echo "==> Stopping AWS Config recorder"
aws configservice stop-configuration-recorder \
  --configuration-recorder-name main \
  --region "$REGION" 2>/dev/null && echo "    stopped" || echo "    not running or not found"

# ── 2. Stop CloudTrail (writes continuously to S3) ───────────────────────────
echo "==> Stopping CloudTrail"
TRAIL_ARN=$(aws cloudtrail describe-trails --region "$REGION" \
  --query "trailList[?Name=='main'].TrailARN" --output text 2>/dev/null || true)
if [[ -n "$TRAIL_ARN" ]]; then
  aws cloudtrail stop-logging --name "$TRAIL_ARN" --region "$REGION" 2>/dev/null && echo "    stopped" || true
else
  echo "    trail 'main' not found — skipping"
fi

# ── 3. Connect to cluster ─────────────────────────────────────────────────────
CLUSTER_REACHABLE=false
echo "==> Connecting to EKS cluster"
if aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME" --profile "$AWS_PROFILE" 2>/dev/null; then
  CLUSTER_REACHABLE=true
  echo "    connected"
else
  echo "    cluster unreachable — skipping k8s cleanup"
fi

# ── 4. Delete Kubernetes Ingress FIRST (lets LBC delete the ALB) ─────────────
# If we uninstall the LBC Helm release before deleting the ingress, nothing
# watches the ingress events and the ALB is left orphaned. Orphaned ALB
# security groups then block VPC deletion in terraform destroy.
if [[ "$CLUSTER_REACHABLE" == "true" ]]; then
  echo "==> Deleting Kubernetes Ingress (triggers ALB deletion by LBC)"
  kubectl delete ingress airflow -n airflow --ignore-not-found --timeout=60s 2>/dev/null || true

  echo "==> Waiting for ALB to be removed (up to 3 min)..."
  for i in $(seq 1 18); do
    INGRESS_HOST=$(kubectl get ingress airflow -n airflow \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
    if [[ -z "$INGRESS_HOST" ]]; then
      echo "    ALB gone"
      break
    fi
    echo "    waiting... ($((i * 10))s)"
    sleep 10
  done
fi

# ── 5. Uninstall remaining Helm releases ─────────────────────────────────────
if [[ "$CLUSTER_REACHABLE" == "true" ]]; then
  echo "==> Uninstalling all Helm releases"
  releases=$(helm list -A -q 2>/dev/null || true)
  if [[ -n "$releases" ]]; then
    while IFS= read -r release; do
      ns=$(helm list -A --filter "^${release}$" -o json 2>/dev/null \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d[0]['namespace'] if d else 'default')" 2>/dev/null || echo "default")
      helm uninstall "$release" -n "$ns" --wait --timeout 120s 2>/dev/null \
        && echo "    uninstalled $release ($ns)" || echo "    skipped $release"
    done <<< "$releases"
  else
    echo "    no Helm releases found"
  fi
fi

# ── 6. Empty S3 buckets ───────────────────────────────────────────────────────
echo "==> Emptying S3 buckets"
for bucket in "${S3_BUCKETS[@]}"; do
  empty_bucket "$bucket"
done

# ── 7. Force-delete namespaces (prevents stuck Terminating state) ─────────────
# Helm removes controllers before their CRDs' finalizers are processed, leaving
# namespaces stuck in Terminating. Use the finalize API to clear spec.finalizers
# directly — this is the Kubernetes-blessed way to unstick a namespace.
if [[ "$CLUSTER_REACHABLE" == "true" ]]; then
  echo "==> Force-finalizing namespaces"
  for ns in airflow spark data-tools; do
    if kubectl get namespace "$ns" &>/dev/null; then
      kubectl get namespace "$ns" -o json \
        | python3 -c "import sys,json; d=json.load(sys.stdin); d['spec']['finalizers']=[]; print(json.dumps(d))" \
        | kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - &>/dev/null \
        && echo "    $ns finalized" || true
    fi
  done
fi

# ── 8. terraform destroy ──────────────────────────────────────────────────────
echo "==> terraform destroy"
terraform destroy -auto-approve -input=false

echo ""
echo "==> Done. All resources destroyed."
