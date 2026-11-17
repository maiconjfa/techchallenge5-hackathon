# ☸️ Kubernetes — SolidaryTech (EKS)

Manifestos dos 3 microsserviços organizados com **Kustomize**:

- `base/` — Deployments, Services, ConfigMaps, ServiceAccounts, HPA, PDB, Ingress e NetworkPolicies.
- `overlays/dev/` — namespace `solidarytech-dev`, 1 réplica por serviço, HTTP, imagens `:dev`.
- `overlays/prod/` — namespace `solidarytech-prod`, HA mínima, HTTPS no ALB, imagens versionadas.

Os bancos e a mensageria **não sobem no cluster**: os serviços apontam para RDS, DynamoDB e SQS
externos, conforme a arquitetura da fase 5. Enquanto a infra AWS não existir, os pods de
`ngo-service` e `donation-service` vão reiniciar (o código faz conexão/ping no startup), e o
`volunteer-service` responderá `/health` mas falhará nas rotas que usam DynamoDB.

---

## 📁 Estrutura

```text
k8s/
├── base/
│   ├── kustomization.yaml
│   ├── ingress.yaml                 # Ingress ALB com rotas /ngos, /donations, /volunteers
│   ├── networkpolicy.yaml           # default-deny + allow por serviço
│   ├── ngo-service/
│   │   ├── configmap.yaml           # PORT
│   │   ├── deployment.yaml
│   │   ├── hpa.yaml
│   │   ├── pdb.yaml
│   │   ├── service.yaml
│   │   └── serviceaccount.yaml
│   ├── donation-service/            # idem + AWS_REGION/AWS_SQS_URL
│   └── volunteer-service/           # idem + AWS_REGION/AWS_DYNAMODB_TABLE
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml
    │   ├── namespace.yaml
    │   ├── patches/                 # replicas, HPA, IRSA, Ingress
    │   └── secrets/*.env.example    # DATABASE_URL (copiar e preencher)
    └── prod/                        # idem + HTTPS, PDB e resources
```

---

## ✅ Pré-requisitos no cluster

| Item | Por quê |
|---|---|
| Cluster EKS com OIDC provider habilitado | IRSA para SQS/DynamoDB |
| [AWS Load Balancer Controller](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html) | criar o ALB a partir do Ingress |
| Subnets públicas com `kubernetes.io/role/elb=1` | ALB `internet-facing` |
| [metrics-server](https://github.com/kubernetes-sigs/metrics-server) | HPA de CPU |
| VPC CNI com Network Policy (opcional) | aplicar as NetworkPolicies |
| IAM Roles para os ServiceAccounts | `donation-service` (SQS) e `volunteer-service` (DynamoDB) |
| Repositórios ECR | `solidarytech/ngo-service`, `solidarytech/donation-service`, `solidarytech/volunteer-service` |

O cluster **não** foi provisionado por este repositório ainda. Nenhum recurso AWS é criado
pelos manifestos.

### Permissões IAM esperadas (IRSA)

- `donation-service`: `sqs:SendMessage` na fila `solidarytech-donations`.
- `volunteer-service`: `dynamodb:PutItem`, `dynamodb:Scan` na tabela `SolidaryTechVolunteers`.
- `ngo-service`: nenhuma permissão AWS (apenas RDS via `DATABASE_URL`).

Os pods **não** usam `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`. As credenciais vêm do token
projetado pelo IRSA.

---

## 🐳 1. Build e push das imagens

Os Dockerfiles já existem em cada serviço. Exemplo (ajuste conta/região):

```bash
AWS_ACCOUNT_ID=000000000000
AWS_REGION=us-east-1
REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

# Repita para ngo-service e volunteer-service
docker build -t "$REGISTRY/solidarytech/donation-service:v1.0.0" donation-service
docker push "$REGISTRY/solidarytech/donation-service:v1.0.0"
```

Os repositórios ECR precisam existir antes do push (Terraform futuro). Em EKS, o pull do ECR
funciona pelo IAM do node group (ou Pod Identity); não há `imagePullSecrets` nos manifestos.

---

## ⚙️ 2. Ajustar placeholders

Substitua nos overlays:

| Placeholder | Onde |
|---|---|
| `000000000000` | `images.newName`, `eks.amazonaws.com/role-arn`, `certificate-arn` |
| `REPLACE_RDS_ENDPOINT`, `REPLACE_USER`, `REPLACE_PASSWORD` | `secrets/*.env` |
| `000000000000` em `AWS_SQS_URL` | `base/donation-service/configmap.yaml` |
| `dev.solidarytech.example.com` / `api.solidarytech.example.com` | `patches/ingress.yaml` |
| `REPLACE_CERTIFICATE_ID` | `overlays/prod/patches/ingress.yaml` |
| `10.0.0.0/16` | `base/networkpolicy.yaml` (CIDR da VPC) |
| `v1.0.0` | `overlays/prod/kustomization.yaml` (use tag imutável/SHA) |

> Em produção, prefira tags imutáveis por digest (`@sha256:...`) ou o SHA do commit.
> Os Deployments usam `imagePullPolicy: Always` para que uma tag reutilizada (ex.: `:dev`) seja
> atualizada no cluster. Com tags imutáveis, `IfNotPresent` reduz chamadas ao ECR.

---

## 🔐 3. Criar os Secrets

Os valores reais ficam fora do Git (`.gitignore` ignora `k8s/overlays/*/secrets/*.env`).

```bash
cp k8s/overlays/dev/secrets/ngo-service.env.example \
   k8s/overlays/dev/secrets/ngo-service.env
cp k8s/overlays/dev/secrets/donation-service.env.example \
   k8s/overlays/dev/secrets/donation-service.env

# edite os dois arquivos e repita para prod
```

O `secretGenerator` cria `ngo-service-secrets` e `donation-service-secrets` com a chave
`DATABASE_URL`, sem sufixo de hash (os nomes são referenciados pelos Deployments).

Para ambientes mais maduros, troque o `secretGenerator` por **External Secrets Operator**,
**Sealed Secrets** ou **SOPS** — o formato do Secret consumido pelos pods não muda.

---

## 🚀 4. Validar e aplicar

```bash
# Renderiza sem aplicar (falha se faltar secret ou YAML inválido)
kubectl kustomize k8s/overlays/dev > /tmp/solidarytech-dev.yaml
kubectl kustomize k8s/overlays/prod > /tmp/solidarytech-prod.yaml

# Aplica
kubectl apply -k k8s/overlays/dev

# Acompanha
kubectl -n solidarytech-dev get pods,svc,ingress,hpa,pdb -w
kubectl -n solidarytech-dev rollout status deploy/ngo-service
kubectl -n solidarytech-dev rollout status deploy/donation-service
kubectl -n solidarytech-dev rollout status deploy/volunteer-service
```

Após o ALB ficar `ACTIVE`:

```bash
kubectl -n solidarytech-dev get ingress solidarytech \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

curl -i http://<ALB_DNS>/ngos
curl -i -X POST http://<ALB_DNS>/donations \
  -H 'Content-Type: application/json' \
  -d '{"ngo_id":1,"amount":50.0,"donor_name":"Maria"}'
```

O DNS do ALB não é criado automaticamente. Aponte o host do Ingress via Route 53
(ou instale o ExternalDNS).

Para remover:

```bash
kubectl delete -k k8s/overlays/dev
```

---

## 🛡️ Decisões de SRE / resiliência

- **RollingUpdate** com `maxUnavailable: 0` e `maxSurge: 1`: nenhum pod é derrubado antes do novo ficar Ready.
- **Probes** de startup/readiness/liveness em `/health`. A probe é *shallow* (não valida RDS/SQS/DynamoDB): evita cascata de reinícios quando a dependência oscila.
- **preStop sleep 5s** + `terminationGracePeriodSeconds: 30`: dá tempo do ALB desregistrar o pod.
- **PDB**: `minAvailable: 1` (2 no `donation-service` em prod) protege drenagens de node. Em dev, com 1 réplica, o PDB é trocado por `maxUnavailable: 1` para não travar manutenções.
- **topologySpreadConstraints** por zona e por nó: reduz blast radius de falha de AZ.
- **HPA** por CPU (70% do request): `donation-service` escala mais rápido (hot path).
- **NetworkPolicy** default-deny + allow por porta: reduz movimento lateral.
- **Pod Security Admission `restricted`**, `runAsNonRoot`, rootfs read-only, `drop: ALL` e `seccomp: RuntimeDefault`.

## 💰 FinOps

- Requests enxutos e limits separados; `donation-service` recebe mais CPU por ser hot path.
- HPA reduz capacidade ociosa; `scaleDown` com janela de 5 min evita flapping.
- Dev com 1 réplica e teto menor de HPA.
- Tags `Project`, `Environment` e `ManagedBy` propagadas ao ALB.
- Próximos passos: `ResourceQuota`/`LimitRange` por namespace, VPA em modo recomendação,
  Karpenter/Cluster Autoscaler com node pools Spot para cargas tolerantes, budgets no AWS Budgets.

---

## 🔭 Observabilidade (próxima etapa)

As aplicações ainda **não expõem** endpoint de métricas (`/metrics`). Por isso não há
`ServiceMonitor`/anotações de scrape. Quando instrumentar com OpenTelemetry/Prometheus:

1. adicione o exporter no serviço;
2. crie um `ServiceMonitor` (se houver Prometheus Operator) ou anote o pod com
   `prometheus.io/scrape: "true"`;
3. exponha SLIs de latência/erro/taxa por rota e conecte aos SLOs.

## 🔄 GitOps

Os overlays foram pensados para ArgoCD/Flux: a imagem é definida apenas em
`kustomization.yaml > images`, e o restante é declarativo. Flux pode atualizar a tag com
`flux set image`; ArgoCD Image Updater funciona sem mudanças estruturais.

O pipeline de CI/CD (`.github/workflows/_ci-reusable.yml`) já faz a parte de **build e
atualização do GitOps**: após o push da imagem no ECR, ele atualiza `images.newName`/`newTag`
do serviço em `k8s/overlays/prod/kustomization.yaml` e commita a mudança. A sincronização
com o cluster (aplicar o manifesto) fica a cargo de ArgoCD/Flux — o workflow não executa
`kubectl apply`.

---

## ⚠️ Limitações conhecidas

- Sem a infra AWS provisionada, `ngo-service` e `donation-service` entram em `CrashLoopBackOff`
  por não conectarem ao PostgreSQL. É o comportamento esperado do código atual.
- O `/health` não valida dependências; readiness verde não garante RDS/DynamoDB acessíveis.
- O Ingress usa um único `healthcheck-path` (`/health`) para os 3 target groups — válido porque
  todos os serviços expõem a rota.
- As NetworkPolicies exigem VPC CNI com suporte habilitado; sem isso os objetos são aceitos e
  ignorados, sem bloquear tráfego.
- Secrets via `secretGenerator` são um bootstrap; para produção real use um cofre/operator.
