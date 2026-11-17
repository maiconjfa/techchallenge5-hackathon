# 🔄 CI/CD & DevSecOps — GitHub Actions

Pipelines automatizados para os **3 microsserviços** e para a **infraestrutura**
(Terraform + Kubernetes), seguindo o padrão de **CI reutilizável**:
um workflow central (`_ci-reusable.yml`) e um workflow por serviço (`*-ci.yml`).

---

## 📁 Estrutura

```text
.github/
├── dependabot.yml        # Atualizações semanais de actions, pip, gomod, docker e terraform
└── workflows/
    ├── _ci-reusable.yml  # Pipeline DevSecOps reutilizável (chamado pelos 3 serviços)
    ├── ngo-ci.yml        # Wrapper do ngo-service (Python/Flask)
    ├── donation-ci.yml   # Wrapper do donation-service (Go)
    ├── volunteer-ci.yml  # Wrapper do volunteer-service (Python/Flask)
    ├── infra-ci.yml      # Terraform (fmt/validate/tflint/Trivy) + Kustomize/kubeconform
    └── README.md         # Este arquivo
```

---

## 🔀 Fluxo do pipeline de serviço

```text
PR / push na main
        │
        ▼
1. build-test ──► 2. lint ──► 3. security-scan ──► 4. sonar (opcional)
                                                        │
                          push na main apenas            ▼
                                          5. docker build + Trivy image + ECR push
                                                        │
                                                        ▼
                                          6. update-gitops (Kustomize + commit)
```

| Job | O que faz | Bloqueia o pipeline? |
|---|---|---|
| `build-test` | `go build` + `go vet` + `go test` ou instala deps Python + `pytest` | Sim |
| `lint` | `golangci-lint` (Go) / `flake8` + `pylint` (Python) | Sim |
| `security-scan` | SCA com **Trivy FS** (`vuln,secret,misconfig`) e SAST com **gosec** (Go) / **bandit** (Python) | Sim (CRITICAL/HIGH no SCA; HIGH no SAST) |
| `sonar` | **SonarQube/SonarCloud** (quality gate) | Somente se `SONAR_TOKEN` existir |
| `docker-build-scan-push` | Build da imagem, **Trivy image** (CRITICAL) e push no ECR via OIDC | Sim (CRITICAL na imagem) |
| `update-gitops` | Atualiza `images.newName/newTag` em `k8s/overlays/prod/kustomization.yaml` e faz commit | Sim |

Jobs **5 e 6** executam apenas em `push` na `main`. Pull Requests executam **1–4**
(sem push de imagem e sem commit).

---

## 🔐 Secrets e variáveis do repositório

Configure em **Settings → Secrets and variables → Actions**:

| Secret | Obrigatório | Uso |
|---|---|---|
| `AWS_ROLE_ARN` | Recomendado | Role assumida via OIDC para push no ECR. Sem ele, a imagem é construída e escaneada, mas **não** é enviada. |
| `SONAR_TOKEN` | Opcional | Habilita o job `sonar`. Sem ele o job é ignorado (`skipped`). |
| `SONAR_HOST_URL` | Opcional | Ex.: `https://sonarcloud.io` (SonarCloud) ou a URL do seu SonarQube. |
| `SONAR_ORGANIZATION` | Opcional | Organization do SonarCloud. |

### Como obter o `AWS_ROLE_ARN`

A role é criada pelo Terraform (`terraform/github-oidc.tf`) com trust policy
restrita a `repo:<owner>/<repo>:ref:refs/heads/main`:

```bash
cd terraform
terraform output -raw github_actions_role_arn
# arn:aws:iam::248530551510:role/solidarytech-prod-github-actions
```

Copie o valor para o secret `AWS_ROLE_ARN`. **Nenhuma chave estática**
(`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`) é usada.

Se a conta já possui um OIDC provider do GitHub, informe o ARN existente:

```hcl
github_oidc_provider_arn = "arn:aws:iam::248530551510:oidc-provider/token.actions.githubusercontent.com"
```

Parâmetros opcionais em `terraform/terraform.tfvars`:

```hcl
github_repository = "maiconjfa/techchallenge5-hackathon"
github_branch     = "main"
```

---

## 🚦 Gates de segurança aplicados

| Etapa | Ferramenta | Regra de bloqueio |
|---|---|---|
| Dependências (SCA) | Trivy FS `vuln,secret` | `CRITICAL` ou `HIGH` com correção disponível (`ignore-unfixed: true`) |
| Dockerfile / IaC do serviço | Trivy FS `misconfig` | `CRITICAL` |
| Código Go (SAST) | gosec | severidade `HIGH` |
| Código Python (SAST) | bandit | severidade `HIGH` (`-lll`) |
| Imagem container | Trivy image | `CRITICAL` com correção disponível |
| Terraform / Kubernetes | Trivy config | `CRITICAL` (exceções em `.trivyignore`) |
| Qualidade (opcional) | SonarQube | Quality Gate (`sonar.qualitygate.wait=true`) |

Os relatórios completos (todas as severidades) rodam com `continue-on-error: true`
para visibilidade, e o SARIF é enviado ao **GitHub code scanning** quando disponível.

### Exceções documentadas (`.trivyignore`)

O gate de Terraform ignora apenas decisões de arquitetura já documentadas em
`terraform/README.md`:

- `AVD-AWS-0040` / `AVD-AWS-0041` — endpoint público do EKS (facilita o primeiro acesso; restrinja `eks_public_access_cidrs` em produção).
- `AVD-AWS-0104` — egress irrestrito: o cluster usa subnets públicas sem NAT Gateway, então os nós precisam alcançar ECR/SQS/DynamoDB/STS.

---

## 🐳 Imagens e ECR

| Serviço | Repositório ECR | Porta |
|---|---|---|
| `ngo-service` | `248530551510.dkr.ecr.us-east-1.amazonaws.com/solidarytech/ngo-service` | 8081 |
| `donation-service` | `248530551510.dkr.ecr.us-east-1.amazonaws.com/solidarytech/donation-service` | 8082 |
| `volunteer-service` | `248530551510.dkr.ecr.us-east-1.amazonaws.com/solidarytech/volunteer-service` | 8083 |

Tags publicadas em `push` na `main`:

- `v1.0.0-<sha7>` (imutável por commit, usada pelo overlay de produção)
- `latest`

---

## 🚀 CD (GitOps)

Após o push da imagem, o job `update-gitops`:

1. Atualiza `images[].newName` e `images[].newTag` do serviço em
   `k8s/overlays/prod/kustomization.yaml`;
2. Commita como `github-actions[bot]` (`ci(<serviço>): bump image to <tag>`);
3. Faz `git pull --rebase` e `git push`.

O commit no diretório `k8s/` dispara o `infra-ci.yml`, que valida os manifestos
(kustomize build + kubeconform + Trivy). A sincronização com o cluster fica a
cargo do ArgoCD/FluxCD (próxima etapa) — o pipeline **não** executa `kubectl apply`.

> **Pré-requisitos:** em **Settings → Actions → General → Workflow permissions**,
> selecione **Read and write permissions**. Se a `main` tiver branch protection,
> permita o bypass do `github-actions[bot]` ou troque o fluxo para Pull Request.

---

## 🧪 Infra CI (`infra-ci.yml`)

Dispara quando `terraform/**`, `k8s/**`, `.tflint.hcl`, `.trivyignore` ou o próprio
workflow mudam:

- **Terraform:** `fmt -check`, `init -backend=false`, `validate`, `tflint` e Trivy config.
- **Kubernetes:** `kustomize build` dos overlays `dev` e `prod`, `kubeconform -strict`
  e Trivy config.

O workflow **não** executa `terraform plan/apply` e **não** requer credenciais AWS.
O provisionamento continua manual (`terraform plan` → revisão → `apply`).

---

## ✅ Validação local (sem GitHub)

```bash
# Python (dentro de cada serviço Python)
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt pytest flake8 pylint bandit
pytest
flake8 app.py --count --select=E9,F63,F7,F82 --show-source --statistics
pylint app.py --disable=all --enable=E --score=no
bandit -r app.py -lll --skip B101

# Go
cd donation-service
go build ./... && go vet ./... && go test -v -cover ./...

# Segurança
trivy fs --scanners vuln,secret --severity CRITICAL,HIGH --ignore-unfixed --exit-code 1 ngo-service
trivy config --severity CRITICAL --exit-code 1 --ignorefile .trivyignore terraform

# Workflows
actionlint

# Infra
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform validate
tflint --chdir=terraform --init && tflint --chdir=terraform

# Kubernetes
cp k8s/overlays/prod/secrets/{ngo-service,donation-service}.env.example k8s/overlays/prod/secrets/
kustomize build k8s/overlays/prod | kubeconform -strict -summary -ignore-missing-schemas
rm -f k8s/overlays/prod/secrets/*.env
```

Ferramentas usadas nos workflows: `actions/checkout@v7`, `actions/setup-go@v7`,
`actions/setup-python@v7`, `golangci/golangci-lint-action@v9`,
`aquasecurity/trivy-action@v0.36.0`, `github/codeql-action@v4`,
`aws-actions/configure-aws-credentials@v6`, `aws-actions/amazon-ecr-login@v2.2.0`,
`SonarSource/sonarqube-scan-action@v8`, `hashicorp/setup-terraform@v4` e
`terraform-linters/setup-tflint@v6`.

---

## 🤖 Dependabot

`.github/dependabot.yml` abre PRs semanais para actions, dependências Python,
módulos Go, imagens base Docker e providers do Terraform. Todos passam pelo
pipeline de CI antes do merge.
