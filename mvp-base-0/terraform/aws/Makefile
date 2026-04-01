# terraform/aws/Makefile
# Convenient commands for managing Terraform infrastructure

.PHONY: help init plan apply destroy validate fmt clean status outputs list-resources

# Colors for output
RESET := \033[0m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
BLUE := \033[0;34m

help: ## Show this help message
	@echo "$(BLUE)DocVerifier Fabric AWS Terraform Commands$(RESET)"
	@echo ""
	@echo "$(GREEN)Setup:$(RESET)"
	@echo "  make init              Initialize Terraform (run first)"
	@echo "  make validate          Validate Terraform configuration"
	@echo "  make fmt               Format Terraform files"
	@echo ""
	@echo "$(GREEN)Deployment:$(RESET)"
	@echo "  make plan              Show infrastructure changes (review before applying)"
	@echo "  make apply             Create/update AWS infrastructure"
	@echo "  make destroy           Delete all AWS infrastructure (CAUTION)"
	@echo ""
	@echo "$(GREEN)Monitoring:$(RESET)"
	@echo "  make status            Check infrastructure status"
	@echo "  make outputs           Show infrastructure outputs"
	@echo "  make list-resources    List all created resources"
	@echo ""
	@echo "$(GREEN)Utilities:$(RESET)"
	@echo "  make cost              Show cost estimation"
	@echo "  make clean             Clean local Terraform files"
	@echo "  make ssh-backend       SSH to backend instance"
	@echo ""

init: ## Initialize Terraform
	@echo "$(BLUE)Initializing Terraform...$(RESET)"
	@if [ ! -f terraform.tfvars ]; then \
		echo "$(YELLOW)Note: terraform.tfvars not found. Copying from example...$(RESET)"; \
		cp terraform.tfvars.example terraform.tfvars; \
		echo "$(YELLOW)⚠️  Edit terraform.tfvars with your values before proceeding!$(RESET)"; \
		exit 1; \
	fi
	terraform init
	@echo "$(GREEN)✓ Terraform initialized$(RESET)"

validate: ## Validate Terraform configuration
	@echo "$(BLUE)Validating Terraform configuration...$(RESET)"
	terraform validate
	@echo "$(GREEN)✓ Configuration is valid$(RESET)"

fmt: ## Format Terraform files
	@echo "$(BLUE)Formatting Terraform files...$(RESET)"
	terraform fmt -recursive .
	@echo "$(GREEN)✓ Files formatted$(RESET)"

plan: validate ## Show infrastructure changes
	@echo "$(BLUE)Planning infrastructure changes...$(RESET)"
	@echo "$(YELLOW)Review the output below carefully before running 'make apply'$(RESET)"
	@echo ""
	terraform plan -out=tfplan
	@echo ""
	@echo "$(YELLOW)To apply these changes, run: make apply$(RESET)"

apply: ## Create/update AWS infrastructure
	@echo "$(RED)⚠️  CAUTION: This will create AWS resources and incur charges$(RESET)"
	@read -p "Are you sure? Type 'yes' to continue: " confirm && \
	[ "$$confirm" = "yes" ] || (echo "Cancelled"; exit 1)
	@echo ""
	@echo "$(BLUE)Applying Terraform changes...$(RESET)"
	terraform apply tfplan || terraform apply
	@echo ""
	@echo "$(GREEN)✓ Infrastructure deployed successfully$(RESET)"
	@make outputs

destroy: ## Delete all AWS infrastructure
	@echo "$(RED)⚠️  DANGER: This will DELETE all AWS resources$(RESET)"
	@read -p "Type 'destroy' to confirm: " confirm && \
	[ "$$confirm" = "destroy" ] || (echo "Cancelled"; exit 1)
	@echo ""
	@echo "$(RED)Destroying infrastructure...$(RESET)"
	terraform destroy
	@echo "$(GREEN)✓ Infrastructure destroyed$(RESET)"

status: ## Check infrastructure status
	@echo "$(BLUE)Infrastructure Status:$(RESET)"
	@echo ""
	@echo "$(GREEN)EC2 Instances:$(RESET)"
	@aws ec2 describe-instances \
		--filters "Name=tag:Project,Values=DocVerifier" "Name=instance-state-name,Values=running" \
		--query 'Reservations[*].Instances[*].[Tags[?Key==`Name`].Value|[0],InstanceType,State.Name,PrivateIpAddress]' \
		--output table || echo "No instances found"
	@echo ""
	@echo "$(GREEN)RDS Status:$(RESET)"
	@aws rds describe-db-clusters \
		--query 'DBClusters[?contains(DBClusterIdentifier, `docverifier`)].[DBClusterIdentifier,Status,Endpoint]' \
		--output table || echo "No RDS clusters found"
	@echo ""
	@echo "$(GREEN)Load Balancer:$(RESET)"
	@aws elbv2 describe-load-balancers \
		--query 'LoadBalancers[?contains(LoadBalancerName, `docverifier`)].[LoadBalancerName,State.Code,DNSName]' \
		--output table || echo "No load balancers found"
	@echo ""
	@echo "$(GREEN)S3 Buckets:$(RESET)"
	@aws s3 ls | grep docverifier || echo "No S3 buckets found"

outputs: ## Show infrastructure outputs
	@echo "$(BLUE)Infrastructure Outputs:$(RESET)"
	@echo ""
	terraform output
	@echo ""
	@echo "$(BLUE)To get specific output:$(RESET)"
	@echo "  terraform output alb_dns_name"
	@echo "  terraform output rds_cluster_endpoint"
	@echo "  terraform output backend_private_ip"

list-resources: ## List all Terraform-managed resources
	@echo "$(BLUE)Terraform-Managed Resources:$(RESET)"
	terraform state list | sort
	@echo ""
	@echo "Total resources: $$(terraform state list | wc -l)"

cost: ## Show estimated monthly costs
	@echo "$(BLUE)Estimated Monthly Costs:$(RESET)"
	@echo ""
	@echo "Compute:"
	@echo "  • 3 × Orderers (t3.medium):    $$91"
	@echo "  • 3 × Peers (t3.large):        $$183"
	@echo "  • 3 × CAs (t3.small):          $$46"
	@echo "  • 1 × Backend (t3.medium):     $$30"
	@echo "  • 1 × Monitoring (t3.medium):  $$30"
	@echo "  Subtotal: $$380"
	@echo ""
	@echo "Database:"
	@echo "  • RDS Aurora (db.r5.large):    $$821"
	@echo "  • ElastiCache (cache.t3.micro): $$12"
	@echo "  Subtotal: $$833"
	@echo ""
	@echo "Storage & Network:"
	@echo "  • S3 Storage:                  $$2"
	@echo "  • Data Transfer:               $$90"
	@echo "  • ALB:                         $$16"
	@echo "  • CloudWatch:                  $$30"
	@echo "  Subtotal: $$138"
	@echo ""
	@echo "$(GREEN)TOTAL ESTIMATED: $$1,351/month$(RESET)"
	@echo ""
	@echo "$(YELLOW)Note: Prices may vary by region. Use AWS Pricing Calculator for accuracy.$(RESET)"

clean: ## Clean local Terraform files
	@echo "$(YELLOW)Cleaning Terraform files...$(RESET)"
	rm -rf .terraform/
	rm -f .terraform.lock.hcl
	rm -f tfplan
	@echo "$(GREEN)✓ Clean complete$(RESET)"

ssh-backend: ## SSH to backend instance
	@echo "$(BLUE)Connecting to backend instance...$(RESET)"
	@BACKEND_IP=$$(terraform output -raw backend_private_ip); \
	echo "Backend IP: $$BACKEND_IP"; \
	echo "$(YELLOW)Note: You may need a VPN or bastion host to access private subnets$(RESET)"; \
	echo "Command: ssh -i <key.pem> ubuntu@$$BACKEND_IP"

ssh-orderer: ## SSH to first orderer instance
	@echo "$(BLUE)Connecting to orderer instance...$(RESET)"
	@ORDERER_IP=$$(terraform output -json orderer_private_ips | jq -r '.[0]'); \
	echo "Orderer IP: $$ORDERER_IP"; \
	echo "$(YELLOW)Note: You may need a VPN or bastion host to access private subnets$(RESET)"; \
	echo "Command: ssh -i <key.pem> ubuntu@$$ORDERER_IP"

refresh: ## Refresh Terraform state
	@echo "$(BLUE)Refreshing Terraform state...$(RESET)"
	terraform refresh
	@echo "$(GREEN)✓ State refreshed$(RESET)"

show: ## Show current infrastructure state
	@echo "$(BLUE)Current Infrastructure State:$(RESET)"
	terraform show | head -100
	@echo ""
	@echo "$(YELLOW)Use 'terraform state show <resource>' for details$(RESET)"

graph: ## Generate infrastructure graph (requires Graphviz)
	@echo "$(BLUE)Generating infrastructure graph...$(RESET)"
	terraform graph | dot -Tpng > infrastructure.png && \
	echo "$(GREEN)✓ Graph saved to infrastructure.png$(RESET)" || \
	echo "$(YELLOW)Graphviz not installed. Install with: brew install graphviz$(RESET)"

taint: ## Mark a resource for recreation on next apply
	@echo "$(BLUE)Available resources to taint:$(RESET)"
	@terraform state list | head -20
	@read -p "Enter resource to taint (e.g., aws_instance.backend): " resource && \
	terraform taint "$$resource" && \
	echo "$(GREEN)✓ Resource marked for recreation$(RESET)"

untaint: ## Unmark a resource from recreation
	@echo "$(BLUE)Available resources to untaint:$(RESET)"
	@terraform state list | head -20
	@read -p "Enter resource to untaint: " resource && \
	terraform untaint "$$resource" && \
	echo "$(GREEN)✓ Resource unmarked$(RESET)"

# Default target
.DEFAULT_GOAL := help

# Phony targets don't represent files
.PHONY: help init validate fmt plan apply destroy status outputs list-resources cost clean ssh-backend ssh-orderer refresh show graph taint untaint
