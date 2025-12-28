# Terraform State Storage Bootstrap

This directory contains a bootstrap configuration that creates the Azure Storage Account used for storing Terraform state files.

## Why Bootstrap?

Terraform state must be stored somewhere. For team collaboration and safety, we store it in Azure Blob Storage. However, we can't use remote state to create the storage account itself (chicken-and-egg problem). This bootstrap config uses **local state** to create the storage account, then the main infrastructure can use **remote state**.

## One-Time Setup

### Step 1: Initialize Bootstrap

```bash
cd infrastructure/opentofu/azure/bootstrap
tofu init
```

### Step 2: Review and Apply

```bash
# Review what will be created
tofu plan

# Create the storage account
tofu apply
```

This creates:
- Resource group: `terraform-state-rg`
- Storage account: `chertterraformstate`
- Blob container: `tfstate`

### Step 3: Set Environment Variable

```bash
# Get the storage account key
export ARM_ACCESS_KEY=$(tofu output -raw storage_account_primary_key)

# Or add to your shell profile
echo "export ARM_ACCESS_KEY=\"$(tofu output -raw storage_account_primary_key)\"" >> ~/.zshrc
source ~/.zshrc
```

### Step 4: Use Remote State in Main Config

```bash
cd ../  # Back to azure/ directory
tofu init
```

Now your main infrastructure will use remote state stored in Azure Blob Storage.

## Customization

If you need a different storage account name (must be globally unique):

```bash
tofu apply -var="storage_account_name=yourprojectname"
```

## Backup Local State

After running bootstrap, keep the local state file safe:

```bash
# Backup bootstrap state
cp terraform.tfstate terraform.tfstate.backup
```

This is your only copy of the bootstrap state since we're not using remote state for the bootstrap itself.

## Destroying Everything

If you need to tear down everything:

```bash
# Destroy main infrastructure first
cd ../
tofu destroy

# Then destroy bootstrap storage (removes all state)
cd bootstrap/
tofu destroy
```

⚠️ **Warning**: Destroying the bootstrap storage account will delete all Terraform state files!
