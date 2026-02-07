Azure Storage Security Lab — Service Endpoints & Private Endpoints (Bicep)
📌 Overview

This project demonstrates how to secure an Azure Storage Account using Virtual Network controls, Service Endpoints, and Private Endpoints.
All infrastructure is deployed using Azure Bicep (Infrastructure as Code).

The lab shows how to:

Restrict storage public access

Allow access only from selected subnets

Use Service Endpoints for subnet-based access control

Use Private Endpoints + Private DNS for private connectivity

🏗️ Architecture Components

Virtual Network

Subnets:

snet-se — Service Endpoint enabled (Microsoft.Storage)

snet-pe — Private Endpoint subnet

snet-vm — test subnet (optional)

Azure Storage Account (public access restricted)

Private Endpoint (Blob)

Private DNS Zone — privatelink.blob.core.windows.net

VNet link to Private DNS zone

🔐 Security Features Implemented

Storage Account public access restricted

Network default action set to Deny

Virtual Network rule added for service-endpoint subnet

Service Endpoint enabled for Microsoft.Storage

Private Endpoint created for Blob service

Private DNS zone linked to VNet for private name resolution

📂 Repo Structure
infra-bicep/
  main.bicep
  params/dev.parameters.json

scripts/
  test.ps1

🚀 Deployment

Create resource group:

az group create -n rg-pe-se-lab-aue-001 -l australiaeast


Deploy Bicep:

az deployment group create \
  -g rg-pe-se-lab-aue-001 \
  -f infra-bicep/main.bicep \
  -p infra-bicep/params/dev.parameters.json

✅ Validation Performed

Verified Service Endpoint enabled on subnet (Microsoft.Storage)

Verified Storage network rules include VNet subnet

Verified Private Endpoint created with private IP

Verified Private DNS zone and VNet link

Confirmed secure networking configuration via Azure Portal and CLI

🧠 Key Learnings

Difference between Service Endpoint and Private Endpoint

How subnet service endpoints work at network level

How Private Link uses private IP + private DNS

How to restrict PaaS access using VNet rules

Implementing secure patterns using Bicep IaC

🧹 Cleanup
az group delete -n rg-pe-se-lab-aue-001 --yes --no-wait