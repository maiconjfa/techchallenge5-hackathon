# ☁️ Terraform — SolidaryTech (EKS + RDS + SQS + DynamoDB + VPC)

Infraestrutura como código para o ambiente de produção do Hackathon Fase 5.

O código é **executável e validado**, mas **não provisiona nada automaticamente**. O fluxo seguro é
sempre `init` → `fmt`/`validate` → `plan` → revisão → `apply`.

---

## 🏗️ O que é criado

| Camada | Recursos |
|---|---|
| **Rede** | VPC `10.0.0.0/16`, Internet Gateway, 4 subnets públicas (2 por AZ em `us-east-1a`/`1b`), route table e associações |
| **EKS** | Cluster, OIDC provider, managed node group (`t3.medium`, 2–4 nós, AL2023), add-ons `vpc-cni` (NetworkPolicy habilitada), `coredns`, `kube-proxy`, log group do control plane |
| **IAM** | Roles do control plane e dos nós + IRSA para `donation-service` (SQS) e `volunteer-service` (DynamoDB) + OIDC provider/role do GitHub Actions para push no ECR |
| **RDS** | 2 instâncias PostgreSQL `db.t3.micro` (`ngo_db` e `donation_db`), subnet group, storage gp3 criptografado, backup 7 dias |
| **Mensageria** | Fila SQS `solidarytech-donations` + DLQ `solidarytech-donations-dlq` (redrive após 5 tentativas) |
| **NoSQL** | Tabela DynamoDB `SolidaryTechVolunteers` (on-demand, PITR e criptografia) |
| **Registry** | Repositórios ECR `solidarytech/{ngo-service,donation-service,volunteer-service}` com scan on push e lifecycle policy |

O `volunteer-service` **não** tem RDS: usa DynamoDB, conforme o código da aplicação.

---

## 🏷️ Política de tags (FinOps)

Tags obrigatórias aplicadas via `provider.default_tags` **e** explicitamente em cada recurso:

| Tag | Valor |
|---|---|
| `Project` | `SolidaryTech` |
| `Environment` | `Production` |
| `CostCenter` | `NGO-Core` |
| `ManagedBy` | `Terraform` (extra) |

Guardrails implementados no código:

- `project`, `environment` e `cost_center` têm defaults fixos e `validation`.
- `extra_tags` não pode sobrescrever as três tags obrigatórias (validação `alltrue`).
- `default_tags` garante cobertura de todo recurso taggable, inclusive os criados no futuro.
- Recursos que não suportam tags (attachments, route table associations, lifecycle policies)
  são os únicos sem tags — por limitação da própria AWS.

---

## ✅ Pré-requisitos

- Terraform **>= 1.6** (validado com 1.11.3).
- AWS CLI configurado com o profile `tf` em `~/.aws/config` (conta `248530551510`, `us-east-1`).
- Permissões IAM para criar VPC, EKS, IAM, RDS, SQS, DynamoDB, ECR e CloudWatch.
- Nenhuma infraestrutura é criada durante o `plan`.

Confira o profile:

```bash
aws sts get-caller-identity --profile tf
```

---

## 🚀 Uso

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # opcional: defaults já atendem

terraform init -backend=false                  # validação local sem backend remoto
terraform fmt -recursive
terraform validate

# Revisão do plano (não cria nada)
terraform plan -out=tfplan

# Quando estiver de acordo:
# terraform apply tfplan
```

> Para estado remoto (recomendado em equipe/CI), após criar o bucket S3 e a tabela de lock,
> copie `backend.tf.example` para `backend.tf` e rode `terraform init -migrate-state`.
> O estado contém senhas de RDS; use bucket criptografado e acesso restrito.

---

## 🧪 Validação executada

| Etapa | Resultado |
|---|---|
| `terraform fmt -recursive` | OK |
| `terraform validate` | `Success! The configuration is valid.` |
| `terraform plan` (profile `tf`, conta `248530551510`) | **54 recursos a criar**, 0 alterar, 0 destruir; sem warnings |
| Data source `aws_rds_engine_version` | PostgreSQL `16.15` |
| `terraform apply` | **não executado** |

O plano foi gerado apenas para validação. Nenhum recurso AWS foi criado.

---

## 🔎 Depois do apply: conectar no cluster

```bash
aws eks update-kubeconfig --region us-east-1 --name solidarytech-prod-eks --profile tf
kubectl get nodes
```

O criador do cluster recebe `cluster-admin` automaticamente
(`bootstrap_cluster_creator_admin_permissions = true`).

---

## 🔗 Integração com os manifests Kubernetes

Preencha os overlays a partir dos outputs:

```bash
terraform output -raw kubeconfig_command
terraform output -json ecr_repository_urls
terraform output -json irsa_role_arns
terraform output -raw github_actions_role_arn
terraform output -raw ngo_database_url
terraform output -raw donation_database_url
terraform output -raw sqs_queue_url
terraform output -raw dynamodb_table_name
```

| Output | Onde usar |
|---|---|
| `ecr_repository_urls` | `k8s/overlays/prod/kustomization.yaml` → `images.newName` |
| `ngo_database_url` / `donation_database_url` | `k8s/overlays/prod/secrets/*.env` (`DATABASE_URL`) |
| `sqs_queue_url` | `k8s/base/donation-service/configmap.yaml` → `AWS_SQS_URL` |
| `dynamodb_table_name` | já é `SolidaryTechVolunteers` (default do ConfigMap) |
| `irsa_role_arns` | `k8s/overlays/prod/patches/irsa-*.yaml` → `eks.amazonaws.com/role-arn` |
| `ecr_repository_urls` | também usado no `docker build/push` |
| `github_actions_role_arn` | secret `AWS_ROLE_ARN` do GitHub Actions (CI/CD via OIDC) |

Os nomes dos IAM Roles e repositórios ECR já foram escolhidos para casar com os overlays
(`solidarytech-prod-donation-service`, `solidarytech-prod-volunteer-service`,
`solidarytech/<serviço>`).

---

## 🤖 CI/CD (GitHub Actions via OIDC)

O arquivo `github-oidc.tf` cria:

- **OIDC provider** do GitHub (`token.actions.githubusercontent.com`), ou reutiliza um existente
  via `github_oidc_provider_arn`;
- **Role** `solidarytech-prod-github-actions` cuja trust policy aceita apenas
  `repo:<github_repository>:ref:refs/heads/<github_branch>`;
- **Policy** com permissão de push/pull nos 3 repositórios ECR do projeto.

```bash
terraform output -raw github_actions_role_arn
```

Salve o valor no secret `AWS_ROLE_ARN` do repositório. Nenhuma chave estática é usada.
Os pipelines estão documentados em [`.github/workflows/README.md`](../.github/workflows/README.md).

---

## ⚠️ Decisões e limitações conscientes

- **4 subnets públicas, sem NAT Gateway**: atende à especificação e reduz custo. As subnets têm
  `map_public_ip_on_launch = true`, então os nós do managed node group recebem IP público para
  acessar ECR/SSM. Em produção real, o padrão é subnets privadas + NAT ou VPC endpoints.
- **RDS em subnets públicas, porém `publicly_accessible = false`** e Security Group aceitando
  `5432` somente dos nós do EKS.
- **`db.t3.micro` e `multi_az = false`** por custo. `db_multi_az = true` é suportado via variável.
- **`skip_final_snapshot = true` e `deletion_protection = false`** no RDS, além de DynamoDB sem
  deletion protection, para permitir teardown do hackathon. Em produção real, inverta esses valores.
- **Sem backend remoto por padrão** (estado local). Use `backend.tf.example` para S3 + lock.
- **Não instala** AWS Load Balancer Controller nem metrics-server: são add-ons de cluster
  necessários ao Ingress/HPA, documentados em `k8s/README.md`. O cluster já cria a base
  (OIDC, IRSA, subnets tagueadas para o ALB e VPC CNI com NetworkPolicy).
- **ECR com tag mutável** para permitir o fluxo `:dev`; em produção use tags imutáveis/SHA.
- **Endpoint público do EKS aberto** (`0.0.0.0/0`) para facilitar o primeiro acesso. Restrinja
  `eks_public_access_cidrs` ao IP da equipe/CI.
- **Exceções do Trivy config** (`AVD-AWS-0040`, `AVD-AWS-0041`, `AVD-AWS-0104`) em `.trivyignore`,
  justificadas por estas mesmas decisões (endpoint público e egress sem NAT Gateway).
- **VPC Flow Logs, AWS WAF, Secrets Manager gerenciado e KMS dedicado** não foram incluídos para
  manter o custo/escopo do hackathon; são evoluções naturais.

---

## 💰 FinOps

- `default_tags` + tags explícitas permitem filtrar custo por `Project`, `Environment` e `CostCenter`.
- DynamoDB on-demand evita capacidade ociosa; SQS e ECR têm custo próximo de zero no volume do projeto.
- Managed node group com mínimo de 2 e máximo de 4; HPA do Kubernetes escala pods, e o node group
  pode ser integrado ao Cluster Autoscaler/Karpenter numa próxima fase.
- Logs do control plane com retenção de 30 dias.
- Lifecycle policy do ECR expira imagens sem tag em 14 dias.
- Sugestões: AWS Budgets com alerta em 80%/100%, Savings Plans para o node group, Spot para
  workloads tolerantes e agendamento de desligamento em ambientes de desenvolvimento.

---

## 🧨 Destruição

```bash
cd terraform
terraform destroy
```

Ordem importa: o EKS e os recursos de rede são removidos pelo dependency graph. Se houver
LoadBalancers/ENIs criados pelo ALB controller posteriormente, remova os Ingress/Services
`type=LoadBalancer` antes do destroy para evitar recursos órfãos.
