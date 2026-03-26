```mermaid
   graph TD
    %% Node Definitions with Styling Classes
    subgraph Client_Layer [External Access]
        User((User))
        IGW[Internet Gateway]
        ALB[AWS Load Balancer]
    end
    
    subgraph Security_Layer [Authentication]
        Cognito[AWS Cognito / JWT]
    end
    
    subgraph Cluster_Layer [EKS Cluster - Private Subnet]
        NGINX[NGINX Ingress Controller]
        Apps[Microservices: Flask & Node.js]
        Helm[Helm Charts]
        Argo[Argo CD]
    end

    subgraph Data_Layer [Database & Storage]
        Mongo[(MongoDB Atlas)]
        S3[(S3 & DynamoDB State)]
    end
    
    subgraph Observability [Monitoring]
        DD[Datadog]
        CW[CloudWatch]
    end
    
    subgraph CI_CD [Automation Pipeline]
        Git[GitHub]
        Jenkins[Jenkins]
        ECR[Amazon ECR]
    end

    %% Infrastructure as Code
    Terraform[Terraform IaC]
    VPC{AWS VPC Network}

    %% Connections
    User --> IGW
    IGW --> ALB
    ALB --> Cognito
    Cognito -.-> NGINX
    NGINX --> Apps
    Apps --> Helm
    Argo -->|GitOps Sync| Apps
    Apps --> Mongo
    Apps --> DD
    Apps --> CW
    Git --> Jenkins
    Git --> Argo
    Jenkins --> ECR
    ECR --> Apps
    Terraform -->|Backend Config| S3
    Terraform -->|Provisions| VPC
    VPC --- Cluster_Layer

    %% Assigning Classes for Colors
    class User,IGW,ALB,VPC,Cognito,ECR,CW aws
    class NGINX,Apps,Helm,Argo k8s
    class Mongo,S3,Redis db
    class Terraform,Jenkins,Git,DD tool
    class Client_Layer,Security_Layer,Cluster_Layer,Data_Layer,Observability,CI_CD layers

    %% Style Definitions
    classDef aws fill:#FF9900,stroke:#232F3E,stroke-width:2px,color:#fff;
    classDef k8s fill:#326CE5,stroke:#1f448d,stroke-width:2px,color:#fff;
    classDef db fill:#47A248,stroke:#3b823b,stroke-width:2px,color:#fff;
    classDef tool fill:#623CE4,stroke:#4829b2,stroke-width:2px,color:#fff;
    classDef layers fill:#f9f9f9,stroke:#d3d3d3,stroke-dasharray: 5 5;


eof
```
# EKS Cloud-Native Platform

[![Terraform](https://img.shields.io/badge/terraform-%3E%3D1.5.0-623CE4?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-EKS%20%7C%20Cognito%20%7C%20API%20Gateway-232F3E?logo=amazon-aws)](https://aws.amazon.com/)
[![Kubernetes](https://img.shields.io/badge/kubernetes-1.28%2B-326CE5?logo=kubernetes)](https://kubernetes.io/)
[![MongoDB](https://img.shields.io/badge/MongoDB-Atlas-47A248?logo=mongodb)](https://www.mongodb.com/atlas)
[![Datadog](https://img.shields.io/badge/Datadog-Monitoring-632CA6?logo=datadog)](https://www.datadoghq.com/)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-GitOps-EF4444?logo=argo)](https://argo-cd.readthedocs.io/)

Enterprise-ready platform for running a microservices voting application on **Amazon EKS**, with full Infrastructure as Code, CI/CD, and managed data. The stack includes Terraform (AWS, EKS), Jenkins pipelines, **ArgoCD** for GitOps, Helm (NGINX Ingress), and **MongoDB Atlas** as the managed database.

**Key technologies:** AWS EKS · Terraform · Jenkins · **ArgoCD** (GitOps) · Helm · Kubernetes · NGINX Ingress · API Gateway · Cognito · **MongoDB Atlas** · **Datadog** (monitoring) · Redis · Flask · Node.js

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Repository Structure](#repository-structure)
- [Environments](#environments)
- [Pipelines](#pipelines)
- [Platform Components](#platform-components)
- [Secrets and Registry](#secrets-and-registry)
- [Observability](#observability)
- [Security](#security)
- [Quick Start](#quick-start)
- [Operations](#operations)
- [Cleanup](#cleanup)
- [Documentation](#documentation)

---

## Overview

This repository provides everything needed to build, deploy, and operate the voting application in AWS:

| Area               | Description                                                                                                                                                                                                            |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Infrastructure** | VPC, IAM, EKS cluster, node group, API Gateway, Cognito, and VPC Link — all defined in Terraform.                                                                                                                      |
| **CI/CD**          | Jenkins pipelines for Cluster, Ingress, application build/deploy, and Api-Cognito; **ArgoCD** for GitOps-based deployment and sync.                                                                                    |
| **Platform**       | NGINX Ingress Controller (Helm) on EKS; API Gateway with JWT auth at the edge.                                                                                                                                         |
| **Application**    | Voting microservices (vote, result, worker) with Kubernetes manifests and source in `app/`.                                                                                                                            |
| **Database**       | **MongoDB Atlas** — managed database. You must create a Kubernetes Secret in the cluster with your Atlas connection URL (see [Secrets and Registry](#secrets-and-registry)). No secret file is committed in this repo. |

---

## Architecture

**Traffic flow**

```
  Client → API Gateway (Cognito JWT) → VPC Link → NLB → NGINX Ingress → EKS (vote / result)
```

1. API Gateway receives requests and validates the JWT using Cognito.
2. Valid requests are sent through **VPC Link** to the internal **Network Load Balancer** (created by the NGINX Ingress Service).
3. The NLB forwards to the **NGINX Ingress Controller** in the EKS cluster.
4. Ingress routes to the voting app services (vote, result).

**Application endpoints**

| Path      | Service        | Stack   |
| --------- | -------------- | ------- |
| `/vote`   | Vote frontend  | Flask   |
| `/result` | Result service | Node.js |

**Data store**

| Component         | Role                                                                                                                                                                   |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **MongoDB Atlas** | Primary database for the voting application. You must create a Secret in the cluster containing your MongoDB Atlas URL; no secret file is included in this repository. |
| **Redis**         | Used by the voting app stack (e.g. session/cache) as defined in `k8s/`.                                                                                                |

**Network**

- **VPC** `10.0.0.0/16`: two public subnets (`10.0.1.0/24`, `10.0.2.0/24`) and two private subnets (`10.0.11.0/24`, `10.0.12.0/24`) across two availability zones.
- EKS control plane and node group run in the private subnets; outbound traffic uses a NAT Gateway.

---

## Repository Structure

| Path                  | Purpose                                                                                                                                                |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `Cluster/`            | Terraform: VPC, EKS cluster, IAM roles, node group.                                                                                                    |
| `Ingress/`            | Terraform + Helm: NGINX Ingress Controller on EKS.                                                                                                     |
| `Api-Cognito/`        | Terraform: Cognito User Pool, API Gateway HTTP API, VPC Link, JWT authorizer.                                                                          |
| `k8s/`                | Kubernetes manifests: voting app (vote, result, worker), Redis, Ingress. (MongoDB connection is via a Secret you create in the cluster — not in repo.) |
| `app/`                | Application source and Dockerfiles (votingapp, result, worker).                                                                                        |
| `Jenkinsfile.yaml`    | Jenkins pipeline — Cluster (Terraform init/plan/apply).                                                                                                |
| `IngressPipline.yaml` | Jenkins pipeline — Ingress.                                                                                                                            |
| `App-pip.yaml`        | Jenkins pipeline — Application.                                                                                                                        |
| `ApiPipeline.yaml`    | Jenkins pipeline — Api-Cognito.                                                                                                                        |

---

## Environments

- **Environments:** `nonprod` (default) and `prod`, via the Terraform variable `environment`.
- **Naming:** Cluster name is `nti-${environment}-eks` (e.g. `nti-nonprod-eks`).
- **Configuration:** Use `terraform.tfvars` per module or pipeline variables. Do not commit real secrets; use `terraform.tfvars.example` and store sensitive values in Jenkins or a secrets manager.

---

## Pipelines

| Pipeline              | Purpose                               | Notes                                                     |
| --------------------- | ------------------------------------- | --------------------------------------------------------- |
| `Jenkinsfile.yaml`    | Terraform init/plan/apply for Cluster | `ACTION`: `apply` \| `destroy`; credentials: `aws_cred`.  |
| `IngressPipline.yaml` | Install NGINX Ingress (Helm) on EKS   | Runs in `Ingress/`; cluster `nti-nonprod-eks` must exist. |
| `App-pip.yaml`        | Build and deploy voting application   | Builds images and deploys to Kubernetes.                  |
| `ApiPipeline.yaml`    | Terraform for Api-Cognito             | Needs VPC ID, subnet IDs, and NLB from Cluster/Ingress.   |

---

## Platform Components

| Module          | What it provisions                                                                                                                                              |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Cluster**     | VPC (public/private subnets), NAT Gateway, Internet Gateway; EKS cluster and node group (`m7i-flex.large`, min 2 / max 6); IAM roles for cluster and nodes.     |
| **Ingress**     | NGINX Ingress Controller (official Helm chart), exposed as a Network Load Balancer.                                                                             |
| **Api-Cognito** | Cognito User Pool, resource server (read/write), app client (client_credentials); API Gateway HTTP API, VPC Link to NLB, JWT authorizer, route `ANY /{proxy+}`. |

---

## Secrets and Registry

**MongoDB Atlas (required)**

The voting app uses **MongoDB Atlas**. **No secret file is stored in this repository.** Anyone using this project **must** create a Kubernetes Secret **inside the cluster** and put the MongoDB Atlas connection URL in it, before deploying the application.

- **Where:** In the same namespace where the voting app runs (e.g. `default` or `voting-app`).
- **Secret name:** `mongo-secret`.
- **Key:** `MONGO_URI` (or `connection-string`, depending on how the app reads it). **Value:** your MongoDB Atlas connection string (e.g. `mongodb+srv://user:password@cluster0.xxxxx.mongodb.net/...`).

Example (replace with your real URL and namespace):

```bash
kubectl create secret generic mongo-secret \
  --from-literal=MONGO_URI='mongodb+srv://USER:PASSWORD@cluster0.xxxxx.mongodb.net/?retryWrites=true&w=majority' \
  -n default
```

Create this secret **before** running `kubectl apply -f k8s/`. Do not commit the connection string to the repo.

**Cognito**

- The app client is created with `generate_secret = true`. Store the client secret in a secure store (e.g. AWS Secrets Manager); do not commit or log it.

**Registry**

- For a private container registry, configure image pull secrets in the namespace where the voting app runs.

---

## Observability

- **Datadog** — This project uses **Datadog** for monitoring (metrics, logs, APM). Configure the Datadog agent or operator in the cluster and provide the required API key (e.g. via Kubernetes Secret or pipeline variable) as per your Datadog setup.
- **Logs and events:** You can also use `kubectl logs` and `kubectl get events` for quick checks (see [Operations](#operations)).

---

## Security

- **IAM** — EKS cluster and nodes use IAM roles; no long-lived credentials in pods.
- **Network** — Workloads run in private subnets; outbound only via NAT Gateway.
- **Edge** — API Gateway and Cognito provide an optional JWT authentication layer.
- **Terraform state** — Stored in S3 with DynamoDB locking; restrict access via IAM.
- **Secrets** — Do not commit `terraform.tfvars` or real DB credentials; `.gitignore` excludes `*.tfvars`.

---

## Quick Start

**Prerequisites:** Terraform ≥ 1.5, AWS CLI (configured), kubectl, Helm 3.x (for Ingress). Jenkins is required for pipeline-based deployment.

### 1. Deploy infrastructure (Cluster)

```bash
cd Cluster
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 2. Configure kubectl

```bash
aws eks update-kubeconfig --region us-east-1 --name nti-nonprod-eks
kubectl get nodes
```

### 3. Deploy Ingress

```bash
cd Ingress
terraform init
terraform plan
terraform apply
```

Save the output `nginx_ingress_lb_hostname` for the Api-Cognito module.

### 4. Deploy Api-Cognito

Create `Api-Cognito/terraform.tfvars` with `region`, `vpc_id`, and `subnet_ids`. Ensure the NLB data source in `Api-Cognito/main.tf` matches your NLB. Then:

```bash
cd Api-Cognito
terraform init
terraform plan
terraform apply
```

### 5. Create MongoDB Atlas secret, then deploy app

**Required:** Create the `mongo-secret` in the cluster with your MongoDB Atlas URL (no secret file is in the repo). Example:

```bash
kubectl create secret generic mongo-secret \
  --from-literal=MONGO_URI='YOUR_MONGODB_ATLAS_CONNECTION_STRING' \
  -n default
```

Then deploy the application:

```bash
kubectl apply -f k8s/
```

Verify:

```bash
kubectl get pods,svc -n default
kubectl get ingress -A
```

---

## Operations

**Routine checks**

```bash
kubectl get ingress -A
kubectl get svc -n ingress-nginx
kubectl get deploy,svc,pods -n default
kubectl logs -l app=vote --tail=50
kubectl logs -l app=result --tail=50
kubectl get events -n default --sort-by='.lastTimestamp'
```

Use Terraform outputs from Cluster, Ingress, and Api-Cognito for `cluster_endpoint`, `nginx_ingress_lb_hostname`, `api_endpoint`, and Cognito IDs.

---

## Cleanup

Remove application workloads first, then destroy infrastructure in reverse order:

```bash
kubectl delete -f k8s/
cd Api-Cognito && terraform destroy
cd ../Ingress && terraform destroy
cd ../Cluster && terraform destroy
```

---

## Documentation

| Reference       | Description                                                                                                                                                            |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| This README     | Architecture, structure, pipelines, **ArgoCD** (GitOps), quick start, operations, security, **MongoDB Atlas** secret (create in cluster), **Datadog** monitoring.      |
| `Cluster/`      | Variables: `region`, `environment`, `vpc_cidr`. Outputs: `vpc_id`, `private_subnets`, `public_subnets`, `cluster_name`, `cluster_endpoint`, `cluster_ca_certificate`.  |
| `Ingress/`      | Variables: `nginx_namespace`, `replica_count`, `service_type`, `aws_lb_type`, `aws_lb_internal`. Outputs: `nginx_ingress_lb_hostname`, `nginx_ingress_namespace`.      |
| `Api-Cognito/`  | Variables: `region`, `vpc_id`, `subnet_ids`, `project_name`, `environment`. Outputs: `api_endpoint`, `user_pool_id`, `app_client_id`, `cognito_domain`, `vpc_link_id`. |
| `State backend` | S3 and DynamoDB: `Cluster/backend.tf`, `Ingress/backend.tf`.                                                                                                           |

---

|          |                                  |
| -------- | -------------------------------- |
| **Role** | DevOps Engineer / Cloud Engineer |

_For internal or organizational use. Ensure compliance with AWS, HashiCorp, MongoDB Atlas, and Datadog terms of use._
