#!/usr/bin/env bash
# =============================================================================
# Manual deploy helper. CI runs the same steps via buildspec.yml; this script
# is for first-time bootstrapping or break-glass deploys.
#
# Usage:
#   AWS_PROFILE=atmos-dev ./scripts/deploy.sh dev
# =============================================================================
set -euo pipefail

ENV="${1:-dev}"
case "$ENV" in dev|qa|prod) ;; *) echo "Usage: $0 <dev|qa|prod>"; exit 1;; esac

REGION="${AWS_REGION:-eu-central-1}"
PREFIX="atm-plat-prime-${ENV}"
APP_DIR="$(cd "$(dirname "$0")/../app" && pwd)"
TF_DIR="$(cd "$(dirname "$0")/../terraform" && pwd)"

echo "==> [1/5] Terraform init/plan/apply ($ENV)"
cd "$TF_DIR"
terraform init -backend-config=envs/${ENV}.backend.hcl -reconfigure
terraform plan  -var-file=envs/${ENV}.tfvars -out=tfplan.bin
read -rp "Apply this plan? [y/N] " ANS
[[ "$ANS" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
terraform apply tfplan.bin

ECR_URI="$(terraform output -raw ecr_repository_url)"
CLUSTER="${PREFIX}-ecs"
SERVICE="${PREFIX}-svc-api"

echo "==> [2/5] Logging in to ECR"
aws ecr get-login-password --region "$REGION" \
    | docker login --username AWS --password-stdin "${ECR_URI%/*}"

IMG_TAG="$(git -C "$APP_DIR/.." rev-parse --short HEAD 2>/dev/null || date +%s)"
echo "==> [3/5] Building image $ECR_URI:$IMG_TAG"
docker build -t "${ECR_URI}:${IMG_TAG}" -t "${ECR_URI}:latest" "$APP_DIR"

echo "==> [4/5] Pushing image"
docker push "${ECR_URI}:${IMG_TAG}"
docker push "${ECR_URI}:latest"

echo "==> [5/5] Forcing rolling deploy on ECS"
aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" \
    --force-new-deployment --region "$REGION" >/dev/null
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE" --region "$REGION"

echo "==> Done. Internal ALB:"
terraform output -raw alb_dns_name
echo
echo "==> Smoke test (run after connecting to Client VPN):"
terraform output -raw deploy_url
