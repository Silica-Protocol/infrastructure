# OCI testnet (validators) – publishing a public image

This module starts validator VMs that run Silica from a container image you provide via `container_image`.

## 1) Publish the image (public GHCR)

This repo includes a GitHub Actions workflow that builds and pushes a multi-arch image to GHCR:

- Workflow: `.github/workflows/publish-silica-image.yml`
- Dockerfile: `protocol/Dockerfile`

### Steps

1. Push this repo to GitHub and ensure you have a `main` branch.
2. Trigger the workflow by pushing to `main` (or run it via **Actions → Publish Silica Container Image → Run workflow**).
3. After the first successful push, make the GHCR package public:
   - GitHub UI: **Packages → (your image) → Package settings → Change visibility → Public**

### Resulting image reference

By default the workflow publishes:

- `ghcr.io/<owner>/<repo>:latest`
- `ghcr.io/<owner>/<repo>:testnet-latest`
- `ghcr.io/<owner>/<repo>:<git-sha>`

## 2) Point the OCI nodes at your image

Edit your `terraform.tfvars` (or start from `terraform.tfvars.example`) and set:

- `container_image = "ghcr.io/<owner>/<repo>:testnet-latest"`

Then:

- `tofu init`
- `tofu apply`

## 3) Update already-created nodes (no reprovision)

If the VMs already exist and you just want to switch images + restart:

- `python3 scripts/silica_nodes.py set-image --image ghcr.io/<owner>/<repo>:testnet-latest`

## 4) Quick health checks

- `python3 scripts/silica_nodes.py status`
- `python3 scripts/silica_nodes.py logs validator-0`

From your machine:

- `curl -fsS http://<node-public-ip>:8545/health`
