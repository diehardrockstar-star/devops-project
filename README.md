DevSecOps Application Infrastructure

This Terraform project provisions an AWS VPC with two public subnets, an internet-facing Application Load Balancer, and an Auto Scaling Group that runs a Dockerized application with a MySQL database on Ubuntu EC2 instances. The Auto Scaling Group starts with one instance and can scale to two.

Prerequisites

Terraform 1.5.0 or later.
AWS credentials available to the Terraform AWS provider, with permissions to create the resources in main.tf in the selected region.
A Docker image published to Docker Hub. The image must listen on port 8080 and respond to the target group's health check at /.
A Docker Hub account/repository and the image tag to deploy.

The EC2 instances also need outbound internet access at startup to install Docker, pull the application and MySQL images, and download the database schema.

Configuration

Set these required Terraform variables:

Variable
Description
docker_user
Docker Hub username or organization that owns the image
docker_image_name
Docker Hub repository name for the application image
docker_image_tag
Published image tag, such as a CI build number
database_password
MySQL root password, also passed to the application as its database password

Optional variables and their defaults:

Variable
Default
Description
aws_region
us-east-1
AWS region for the deployment
allowed_ip
198.51.100.1/32
CIDR allowed to SSH to the EC2 instances; replace with your trusted public IP in /32 form if SSH access is needed
database_username
root
Database user supplied to the application

Supply values in a local terraform.tfvars file or pass them with -var options. For example:

docker_user        = "your-dockerhub-user"
docker_image_name  = "your-application"
docker_image_tag   = "your-image-tag"
database_password  = "use-a-unique-strong-password"
aws_region         = "us-east-1"
allowed_ip         = "203.0.113.10/32"

Use real values for your deployment, and do not commit passwords or other secrets to version control. Terraform marks database_password sensitive in its output, but that does not prevent it from being stored in Terraform state.

Deploy

Run these commands from the directory containing main.tf:

terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan

Review the plan before applying it. If you use a variables file, add -var-file="terraform.tfvars" to both the plan and apply commands.

After apply completes, Terraform prints the alb_dns_name output. Retrieve it later with:

terraform output -raw alb_dns_name

Open the application at http://<alb_dns_name> in a browser. The load balancer forwards requests to the application on port 8080.

Security checks with Checkov and Trivy

This project is also a hands-on example of scanning infrastructure and container images for security issues. Install Checkov and Trivy using their official instructions. These checks are local scans; they do not require AWS credentials or deploy resources.

Scan the Terraform configuration with Checkov

From the repository root, run:

checkov -f main.tf -o json > checkov-results.json

Checkov evaluates the Terraform configuration and writes its findings, including rule IDs and affected resources, to checkov-results.json. Review each finding against the resource in main.tf; findings to investigate include the internet-facing HTTP-only ALB and security group rules that allow public HTTP ingress.

Scan infrastructure and the application image with Trivy

Scan Terraform configuration for misconfigurations:

trivy config --format json --output trivy-config-results.json .

Scan the Docker Hub image configured by docker_user, docker_image_name, and docker_image_tag for operating-system and library vulnerabilities. Replace the placeholders with the same image values you use when deploying:

trivy image --format json --output trivy-image-results.json <docker-user>/<image-name>:<image-tag>

The image must be available locally or pullable from Docker Hub. The Terraform and image findings are saved separately in trivy-config-results.json and trivy-image-results.json. Trivy results depend on the scanned contents and vulnerability database at scan time; this repository does not contain the application image or its source.

These commands create local report files in the repository root. Review them after each scan; avoid committing reports if they contain environment-specific details.

Understand and act on findings

The current Terraform configuration intentionally provides issues to discover and discuss, including:

The public ALB listener and target group use HTTP rather than HTTPS.
The ALB security group permits inbound HTTP from 0.0.0.0/0.
The database password is embedded in EC2 user data and can be exposed through instance configuration and Terraform state.
The application database username defaults to the privileged root account.

Use scanner rule IDs and remediation guidance to investigate findings, then decide how to address them for the intended environment. Re-run both scans after changes and compare the results. A clean scan is not proof that an application or infrastructure is secure; review the findings and tool coverage rather than suppressing checks just to get a passing result.

Security and cost considerations

This configuration is intended as a starting point, not as production-ready infrastructure:

The public ALB accepts HTTP only on port 80; traffic to the application is not encrypted with HTTPS.
The database password is interpolated into EC2 user data, which is stored in Terraform state and exposed through instance configuration. Avoid using valuable credentials and move secrets to a dedicated secrets-management solution before production.
The database username defaults to root, a privileged administrative account. Use a dedicated, least-privileged application user before production.
SSH is limited by allowed_ip; replace its example default with a trusted address if SSH access is required.

AWS resources can incur charges while deployed, including the ALB, EC2 instances, storage, and data transfer. Review the plan and current AWS pricing before applying, and destroy resources when they are no longer needed.
