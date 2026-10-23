DevSecOps Application Infrastructure

This Terraform project provisions an AWS VPC with two public subnets, an internet-facing Application Load Balancer, and an Auto Scaling Group that runs a Dockerized application with a MySQL database on Ubuntu EC2 instances. The Auto Scaling Group starts with one instance and can scale to two.

Security checks with Checkov and Trivy

This project is also a hands-on example of scanning infrastructure and container images for security issues. Install Checkov and Trivy using their official instructions. These checks are local scans; they do not require AWS credentials or deploy resources.

Scan the Terraform configuration with Checkov

From the repository root, run:

checkov -f main.tf -o json > checkov-results.json

Checkov evaluates the Terraform configuration and writes its findings, including rule IDs and affected resources, to checkov-results.json. Review each finding against the resource in main.tf; findings to investigate include the internet-facing HTTP-only ALB and security group rules that allow public HTTP ingress.

Scan infrastructure and the application image with Trivy

Scan the Terraform configuration for misconfigurations:

trivy config --format json --output trivy-config-results.json main.tf

Scan the Docker Hub image configured by docker_user, docker_image_name, and docker_image_tag for operating-system and library vulnerabilities. Replace the placeholders with the same image values you use when deploying:

trivy image --format json --output trivy-image-results.json /:

The image must be available locally or pullable from Docker Hub. The Terraform and image findings are saved separately in trivy-config-results.json and trivy-image-results.json. Trivy results depend on the scanned contents and vulnerability database at scan time; this repository does not contain the application image or its source.

These commands create local report files in the repository root. Review them after each scan; avoid committing reports if they contain environment-specific details.

GitHub Actions workflow

The Terraform security checks workflow runs on pull requests and pushes to main when Terraform files or the workflow change, and can also be started manually from the Actions tab. It checks formatting and Terraform validity, then runs Checkov and Trivy against main.tf. The separate JSON reports are uploaded as the terraform-security-reports artifact, including when a scan reports issues; findings or scanner failures make the workflow fail. This workflow only validates and scans configuration—it does not access AWS or deploy resources.

Understand and act on findings

The current Terraform configuration intentionally provides issues to discover and discuss, including:

The public ALB listener and target group use HTTP rather than HTTPS. The ALB security group permits inbound HTTP from 0.0.0.0/0. The database password is embedded in EC2 user data and can be exposed through instance configuration and Terraform state. The application database username defaults to the privileged root account.

Use scanner rule IDs and remediation guidance to investigate findings, then decide how to address them for the intended environment. Re-run both scans after changes and compare the results. A clean scan is not proof that an application or infrastructure is secure; review the findings and tool coverage rather than suppressing checks just to get a passing result.

Security and cost considerations

This configuration is intended as a starting point, not as production-ready infrastructure:

The public ALB accepts HTTP only on port 80; traffic to the application is not encrypted with HTTPS. The database password is interpolated into EC2 user data, which is stored in Terraform state and exposed through instance configuration. Avoid using valuable credentials and move secrets to a dedicated secrets-management solution before production. The database username defaults to root, a privileged administrative account. Use a dedicated, least-privileged application user before production. SSH is limited by allowed_ip; replace its example default with a trusted address if SSH access is required.

AWS resources can incur charges while deployed, including the ALB, EC2 instances, storage, and data transfer. Review the plan and current AWS pricing before applying, and destroy resources when they are no longer needed.
