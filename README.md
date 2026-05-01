# Prime Service - End-to-End Case Study Solution

This repository implements the three tasks from the *ATMOS Space Cargo - Cloud
& Software Engineer* case study:

1. **Task 1 - Application Development.** A FastAPI micro-service that returns
   every prime in a user-supplied range and records each execution in
   PostgreSQL.
2. **Task 2 - Containerization & Orchestration.** Two independent containers
   (api + db) on a private bridge network, with a WireGuard VPN gateway as the
   only ingress path. The API is **never** published to the host.
3. **Task 3 - Cloud Deployment.** Modular Terraform that stands up the same
   topology on AWS - VPC across 2 AZs, AWS Client VPN (mTLS) replacing
   WireGuard, ECS Fargate behind an internal ALB, RDS Postgres (Multi-AZ in
   prod), ECR, IAM groups for human access, and a CodeBuild/GitHub-Actions
   delivery pipeline.

The end-to-end design is documented in `prime-service-playbook.docx`, which
mirrors the structure of the Google Cloud "Cloud Foundations Playbook" we
were asked to follow as a reference (org structure -> resource deployment
-> AuthN/AuthZ -> networking -> data security -> logging -> monitoring ->
container security -> DevSecOps).

## Repository layout

```
.
+-- README.md                        # this file
+-- prime-service-playbook.docx      # architecture playbook (Word doc)
+-- architecture.svg                 # AWS reference architecture
+-- app/                             # Task 1
|   +-- src/
|   |   +-- main.py                  # FastAPI app + endpoints
|   |   +-- primes.py                # segmented Sieve of Eratosthenes
|   |   +-- database.py              # SQLAlchemy engine + session
|   |   +-- models.py                # ORM model: prime_requests
|   +-- tests/test_primes.py
|   +-- Dockerfile                   # multi-stage, non-root, healthcheck
|   +-- requirements.txt
|   +-- requirements-dev.txt
+-- docker/                          # Task 2
|   +-- docker-compose.yml           # api + db + wireguard, private net
|   +-- .env.example
|   +-- postgres/init.sql
|   +-- wireguard/README.md
+-- terraform/                       # Task 3 - AWS IaC
|   +-- providers.tf, variables.tf, locals.tf, main.tf, outputs.tf
|   +-- envs/{dev,prod}.tfvars + *.backend.hcl
|   +-- modules/
|       +-- network/                 # VPC, subnets, NAT, flow logs
|       +-- database/                # RDS Postgres + Secrets Manager
|       +-- compute/                 # ECS Fargate + internal ALB + autoscaling
|       +-- iam/                     # human IAM groups + ECS task roles
|       +-- client_vpn/              # AWS Client VPN endpoint (mTLS)
+-- ci/
|   +-- buildspec.yml                # CodeBuild: lint -> test -> build -> push -> deploy
|   +-- buildspec-iac.yml            # CodeBuild: terraform fmt/validate/plan
|   +-- github-actions.yml           # equivalent GH Actions workflow
+-- scripts/
    +-- deploy.sh                    # one-shot manual deploy
    +-- setup-vpn-client.sh          # easy-rsa cert helper for Client VPN
```

---

## Task 1 - Run the API locally (no Docker)

```bash
cd app
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
DATABASE_URL=sqlite:///./prime_dev.db uvicorn src.main:app --reload
# OpenAPI docs: http://127.0.0.1:8000/docs
```

Try:
```bash
curl 'http://127.0.0.1:8000/api/v1/primes?low=1&high=100'
curl 'http://127.0.0.1:8000/api/v1/history?limit=5'
```

Run tests:
```bash
cd app && pytest -q
```

### Algorithm choice
`primes.py` uses a **segmented Sieve of Eratosthenes**. Memory stays bounded at
`O(sqrt(high) + 65 536)` regardless of `high`, and computing the ~9 592 primes
in `[1, 100 000]` takes a few milliseconds. The `MAX_RANGE` env var caps the
worst-case request span (default 10 000 000) to keep the API responsive.

### API surface
| Method | Path                  | Purpose                                |
|--------|-----------------------|----------------------------------------|
| GET    | `/healthz`            | Liveness (no DB hit)                   |
| GET    | `/readyz`             | Readiness (`SELECT 1`)                 |
| GET    | `/api/v1/primes`      | Primes in `[low, high]` (+ `limit`)    |
| GET    | `/api/v1/history`     | Recent executions (audit)              |

---

## Task 2 - Run the full stack with Docker + WireGuard

```bash
cd docker
cp .env.example .env       # set POSTGRES_PASSWORD etc.
docker compose up -d --build
```

* The API container is **not** bound to any host port. The only published port
  is `UDP/51820` on the WireGuard gateway.
* Peer configs are auto-generated under `docker/wireguard/config/peer1/peer1.conf`.
  Import that file into a WireGuard client (or scan the matching QR code) and
  the tunnel routes you to `172.28.0.0/24`.
* From the WireGuard client you can now reach `http://172.28.0.20:8080`.

Verify the API is unreachable from the host:
```bash
curl -m 2 http://localhost:8080/healthz   # should fail / connect refused
```

---

## Task 3 - Deploy to AWS

The cloud topology is the same shape as Task 2, with WireGuard replaced by
**AWS Client VPN** (mTLS). See `architecture.svg` and section 1.5 of the
playbook for the diagram.

### Prerequisites
1. AWS account, an IAM principal with admin permission for the bootstrap.
2. S3 bucket + DynamoDB table for Terraform state - update
   `terraform/envs/dev.backend.hcl`.
3. Mutual-TLS certs uploaded to ACM (`scripts/setup-vpn-client.sh`).
4. Terraform >= 1.6, AWS CLI v2, Docker.

### Deploy
```bash
# (one-time) generate certs and import to ACM
./scripts/setup-vpn-client.sh developer-1
# fill in the resulting ARNs in terraform/envs/dev.tfvars

# infra + first image push + ECS deploy
AWS_PROFILE=atmos-dev ./scripts/deploy.sh dev
```

`deploy.sh` runs `terraform init/plan/apply`, builds and pushes the image
tagged with the git SHA, and forces a rolling deploy. CI does the same via
`ci/buildspec.yml` (CodeBuild) or `ci/github-actions.yml`.

### Access the API
1. Download the .ovpn template:
   ```bash
   aws ec2 export-client-vpn-client-configuration \
     --client-vpn-endpoint-id $(cd terraform && terraform output -raw client_vpn_endpoint_id) \
     --output text > prime.ovpn
   ```
2. Append your peer cert and key (the script prints the exact heredoc).
3. Connect with the AWS Client VPN client (or any OpenVPN-compatible client).
4. Once the tunnel is up:
   ```bash
   curl "http://<internal-alb-dns>/api/v1/primes?low=1&high=100"
   ```
   `<internal-alb-dns>` comes from `terraform output alb_dns_name`. Without an
   active VPN session, this DNS name resolves to private IPs in the VPC and is
   unreachable from the public internet.

---

## Design choices, in plain language

* **Why segmented sieve over `sympy.primerange` or a library?** The exercise
  forbade copying logic, and the segmented sieve is the standard right-sized
  algorithm: predictable memory, no probabilistic primality checks, trivial
  to test.
* **Why FastAPI over Flask/Django?** Type-hint-driven validation via Pydantic,
  auto-generated OpenAPI docs (free `/docs`), and ASGI for cheap concurrency
  on a single Fargate task.
* **Why ECS Fargate over Kubernetes?** A single micro-service does not justify
  a control plane. Fargate gives us the same isolation guarantees with no
  node management. If/when the platform grows past a handful of services,
  EKS becomes worth its overhead.
* **Why Client VPN with mTLS instead of public ALB + IP allow-list?** The case
  study explicitly requires "secure inbound communication only from the VPN".
  Client VPN gives mutual-TLS auth, per-peer revocation, connection logging,
  and SAML federation when ATMOS needs it - all of which an IP allow-list
  cannot.
* **Why two `tfvars` environments?** Mirrors the playbook's dev/prod folder
  separation. `prod` enables Multi-AZ RDS, larger ECS sizes, deletion
  protection, and tighter cert/secret rotation knobs.
* **Why immutable ECR tags + git-sha tagging?** Reproducibility and rollback.
  `force-new-deployment` with the same tag on rollback is a one-liner.
* **Why no public ALB?** There is no public traffic. The only humans who hit
  the API are operators and CI; both go through Client VPN. This shrinks
  the attack surface to the VPN endpoint.

See `prime-service-playbook.docx` for the long-form rationale, the IAM
groups -> roles table, the IP allocation table, and the DevSecOps pipeline
description.
