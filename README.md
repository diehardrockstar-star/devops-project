# DevSecOps Application Infrastructure

This Terraform project provisions an AWS VPC with two public subnets, an internet-facing Application Load Balancer, and an Auto Scaling Group that runs a Dockerized application with a MySQL database on Ubuntu EC2 instances. The Auto Scaling Group starts with one instance and can scale to two.

## Prerequisites

- Terraform 1.5.0 or later.
- AWS credentials available to the Terraform AWS provider, with permissions to create the resources in `main.tf` in the selected region.
- A Docker image published to Docker Hub. The image must listen on port `8080` and respond to the target group's health check at `/`.
- A Docker Hub account/repository and the image tag to deploy.

The EC2 instances also need outbound internet access at startup to install Docker, pull the application and MySQL images, and download the database schema.

## Configuration

Set these required Terraform variables:

| Variable | Description |
| --- | --- |
| `docker_user` | Docker Hub username or organization that owns the image |
| `docker_image_name` | Docker Hub repository name for the application image |
| `docker_image_tag` | Published image tag, such as a CI build number |
| `database_password` | MySQL root password, also passed to the application as its database password |

Optional variables and their defaults:

| Variable | Default | Description |
| --- | --- | --- |
| `aws_region` | `us-east-1` | AWS region for the deployment |
| `allowed_ip` | `198.51.100.1/32` | CIDR allowed to SSH to the EC2 instances; replace with your trusted public IP in `/32` form if SSH access is needed |
| `database_username` | `root` | Database user supplied to the application |

Supply values in a local `terraform.tfvars` file or pass them with `-var` options. For example:

```hcl
docker_user        = "your-dockerhub-user"
docker_image_name  = "your-application"
docker_image_tag   = "your-image-tag"
database_password  = "use-a-unique-strong-password"
aws_region         = "us-east-1"
allowed_ip         = "203.0.113.10/32"
```

Use real values for your deployment, and do not commit passwords or other secrets to version control. Terraform marks `database_password` sensitive in its output, but that does not prevent it from being stored in Terraform state.

## Build the application image

The root-level `Dockerfile` builds the Java shopping-cart application from a pinned revision of its upstream source and packages it in Tomcat. Build and publish the image to Docker Hub before deploying it with Terraform:

```sh
docker build -t <docker-user>/shoppingcart:<image-tag> .
docker login
docker push <docker-user>/shoppingcart:<image-tag>
```

The container listens on port `8080`. At startup it uses `DB_HOST` (default `mysql-db`), `DB_NAME` (default `shopping-cart`), `DB_USERNAME`, and `DB_PASSWORD` to configure its MySQL connection. Terraform supplies the username and password and starts MySQL on the same Docker network.

## Deploy

Run these commands from the directory containing `main.tf`:

```sh
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Review the plan before applying it. If you use a variables file, add `-var-file="terraform.tfvars"` to both the `plan` and `apply` commands.

After apply completes, Terraform prints the `alb_dns_name` output. Retrieve it later with:

```sh
terraform output -raw alb_dns_name
```

Open the application at `http://<alb_dns_name>` in a browser. The load balancer forwards requests to the application on port `8080`.

## Security checks with Checkov and Trivy

This project is also a hands-on example of scanning infrastructure and container images for security issues. Install [Checkov](https://www.checkov.io/2.Basics/Installing%20Checkov.html) and [Trivy](https://trivy.dev/latest/getting-started/installation/) using their official instructions. These checks are local scans; they do not require AWS credentials or deploy resources.

### Scan the Terraform configuration with Checkov

From the repository root, run:

```sh
checkov -f main.tf -o json > checkov-results.json
```

Checkov evaluates the Terraform configuration and writes its findings, including rule IDs and affected resources, to `checkov-results.json`. Review each finding against the resource in `main.tf`; findings to investigate include the internet-facing HTTP-only ALB and security group rules that allow public HTTP ingress.

### Scan infrastructure and the application image with Trivy

Scan the Terraform configuration for misconfigurations:

```sh
trivy config --format json --output trivy-config-results.json main.tf
```

Scan the Docker Hub image configured by `docker_user`, `docker_image_name`, and `docker_image_tag` for operating-system and library vulnerabilities. Replace the placeholders with the same image values you use when deploying:

```sh
trivy image --format json --output trivy-image-results.json <docker-user>/<image-name>:<image-tag>
```

The image must be available locally or pullable from Docker Hub. The Terraform and image findings are saved separately in `trivy-config-results.json` and `trivy-image-results.json`. Trivy results depend on the scanned contents and vulnerability database at scan time; this repository does not contain the application image or its source.

These commands create local report files in the repository root. Review them after each scan; avoid committing reports if they contain environment-specific details.

### Jenkins pipeline

The root-level `Jenkinsfile` runs Terraform formatting and validation, then scans `main.tf` with Checkov and Trivy. Configure Jenkins agents with Terraform, Checkov, Trivy, Docker, the Jenkins Docker Pipeline plugin, and AWS permissions for Terraform. Add a Jenkins username/password credential with ID `dockerhub-credentials-id` and a secret-text credential with ID `db-admin-password`. Select the Docker Hub username and image repository when starting the job; image tags use the Jenkins build number.

The image build and Trivy image scan run when a root-level `Dockerfile` is present; publishing is limited to the `main` branch. The current Dockerfile builds the shopping-cart app from a pinned upstream revision. Security findings fail the pipeline, and generated JSON reports are archived. Deployment is opt-in with the `DEPLOY` parameter, restricted to the `main` branch in a Jenkins multibranch pipeline, and requires manual confirmation. The deployment uses the Jenkins agent's AWS credentials; it does not deploy on pull requests or by default.

### Understand and act on findings

The current Terraform configuration intentionally provides issues to discover and discuss, including:

- The public ALB listener and target group use HTTP rather than HTTPS.
- The ALB security group permits inbound HTTP from `0.0.0.0/0`.
- The database password is embedded in EC2 user data and can be exposed through instance configuration and Terraform state.
- The application database username defaults to the privileged `root` account.

Use scanner rule IDs and remediation guidance to investigate findings, then decide how to address them for the intended environment. Re-run both scans after changes and compare the results. A clean scan is not proof that an application or infrastructure is secure; review the findings and tool coverage rather than suppressing checks just to get a passing result.

## Security and cost considerations

This configuration is intended as a starting point, not as production-ready infrastructure:

- The public ALB accepts **HTTP only** on port 80; traffic to the application is not encrypted with HTTPS.
- The database password is interpolated into EC2 user data, which is stored in Terraform state and exposed through instance configuration. Avoid using valuable credentials and move secrets to a dedicated secrets-management solution before production.
- The database username defaults to **`root`**, a privileged administrative account. Use a dedicated, least-privileged application user before production.
- SSH is limited by `allowed_ip`; replace its example default with a trusted address if SSH access is required.

AWS resources can incur charges while deployed, including the ALB, EC2 instances, storage, and data transfer. Review the plan and current AWS pricing before applying, and destroy resources when they are no longer needed.

## Clean up

From the same directory and with the same variable values used for deployment, run:

```sh
terraform destroy
```

Review the destroy plan and confirm when prompted. This removes the Terraform-managed infrastructure; it does not delete the Docker image from Docker Hub.
```
```