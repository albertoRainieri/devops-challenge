# DevOps Challenge

## 1. Containerization

**File Reference**: [`app/Dockerfile`](app/Dockerfile)

### Dockerfile Architecture

The Dockerfile implements a **multi-stage build** pattern to create efficient, secure, and optimized Docker images for the NestJS application. The build process is divided into three distinct stages: `builder`, `test`, and `production`.

### Base Image Selection

**Choice: `node:alpine3.22`**

The Dockerfile uses Alpine Linux 3.22 as the base image for all stages. This choice is justified by:

- **Lightweight**: Alpine Linux is one of the smallest Linux distributions (~5MB base), resulting in significantly smaller final images
- **Security**: Minimal attack surface with fewer packages and vulnerabilities. At the time of writing, the `alpine3.22` tag does not present any critical or high severity vulnerabilities --> https://hub.docker.com/layers/library/node/alpine3.22/images/sha256-e74405b049be2d68fa6c203ee4c851117948ed8f0d847ad615b9fe604d52df84
- **Performance**: Fast image pulls and reduced resource consumption
- **Node.js Compatibility**: Official Node.js Alpine images are well-maintained and widely used in production environments

### Multi-Stage Build Strategy

The multi-stage build pattern separates the build, testing, and production concerns into isolated stages, allowing each stage to be optimized for its specific purpose while discarding unnecessary artifacts from the final image.

#### Stage 1: Builder (`builder`)
The builder stage serves as the compilation environment where all dependencies (including devDependencies like TypeScript and build tools) are installed and the source code is compiled from TypeScript to JavaScript. This stage produces the compiled artifacts in the `dist/` directory and establishes a complete `node_modules` tree that can be selectively reused by subsequent stages. The `--frozen-lockfile` flag ensures reproducible builds by enforcing exact version matching from the lockfile.

#### Stage 2: Test (`test`)
The test stage creates an isolated environment for running end-to-end tests by copying the complete dependency tree and source files from the builder stage. This approach ensures test consistency with the development environment while avoiding redundant dependency installations. The stage maintains security by running as a non-root user, following the principle of least privilege.

#### Stage 3: Production (`production`)
The production stage is optimized for runtime efficiency by installing only production dependencies, excluding all build tools, test frameworks, and development dependencies that are unnecessary for running the application. The compiled JavaScript from the builder stage is copied into a minimal runtime environment, resulting in a significantly smaller final image. The application executes as a non-root user for enhanced security.

### Security Best Practices

1. **Non-root User**: All stages run as `node` user instead of root, reducing security risk
2. **Minimal Base Image**: Alpine Linux provides minimal attack surface
3. **Frozen Lockfile**: `--frozen-lockfile` ensures reproducible, secure dependency installation
4. **Layer Caching**: Strategic layer ordering (package files → dependencies → source code) maximizes Docker layer caching efficiency

**Note on Further Security Improvement**: The production image could be further improved by using a distroless base image such as `gcr.io/distroless/nodejs22-debian12:nonroot`. Distroless images eliminate shell access and unnecessary tools, providing an even smaller attack surface and enhanced security posture for production deployments. However, this optimization was not implemented due to time constraints and would require additional testing to ensure compatibility with the application's runtime requirements.

## 2. Database Initialization

**File References**: 
- [`docker-compose.yaml`](docker-compose.yaml) - Docker Compose configuration with mongo-init service
- [`app/init_scripts/mongo-init-v2.js`](app/init_scripts/mongo-init-v2.js) - Idempotent initialization script
- [`app/init_scripts/mongo-init.js`](app/init_scripts/mongo-init.js) - Original initialization script

### Approach: Dedicated Init Container

A dedicated `mongo-init` container was created in the Docker Compose configuration to handle database schema initialization automatically. This container runs as a separate service that executes once MongoDB is ready and available for connections.

### Implementation Details

The `mongo-init` service uses the same MongoDB image (`mongo:7.0`) and implements a wait mechanism that polls MongoDB until it becomes ready. Once MongoDB is ready, executes the `mongo-init-v2.js` script to set up the database schema and initial data

The initialization script (`mongo-init-v2.js`) was developed as an improved version of the original `mongo-init.js`. The script ensures idempotent behavior by:

- Creating the `visits` collection if it doesn't exist (with error handling for already-existing collections)
- Checking if the collection is empty before inserting sample data
- Only inserting initial documents if the database is at the initialization stage (empty collection)
- Providing detailed logging throughout the initialization process

This approach prevents duplicate data insertion on container restarts while ensuring the database is properly initialized on first run.


### Alternative Approach

The same goal could be achieved by mounting the original initialization script (`mongo-init.js`) directly into MongoDB's `/docker-entrypoint-initdb.d` directory. MongoDB automatically executes any scripts placed in this directory when the database is initialized for the first time.

## 3. Local Orchestration

**File References**: 
- [`docker-compose.yaml`](docker-compose.yaml) - Main Docker Compose configuration
- [`app/src/app.module.ts`](app/src/app.module.ts) - Application module with dynamic MongoDB URI configuration

### Docker Compose Architecture

The Docker Compose setup orchestrates four services working together to provide a complete local development and demonstration environment: MongoDB database, database initialization, production application, and test execution.

### Service Overview

**`mongodb`**: The core database service using MongoDB 7.0. Configured with persistent storage via named volume (`mongodb_data`) to preserve data across container restarts. Exposes MongoDB on the default port 27017 within the isolated network.

**`mongo-init`**: A one-time initialization container that ensures the database schema is properly set up before the application starts. Waits for MongoDB to be ready, then executes the initialization script. Configured with `restart: "no"` to prevent repeated executions.

**`app`**: The production NestJS application service. Builds from the Dockerfile using the `production` target, which leverages the multi-stage build to create an optimized runtime image with only production dependencies.

**`app-test`**: A test execution service that builds from the `test` target of the Dockerfile. Runs a simple test against the production application container, demonstrating the separation between test and production environments.

### Service Dependencies

The orchestration ensures proper startup order through `depends_on` relationships:
- `mongo-init` depends on `mongodb` - Ensures database is running before initialization attempts
- `app` depends on `mongodb` - Application starts only after database is available
- `app-test` depends on `app` - Tests run only after the application is running

### Secrets Management

All sensitive configuration (database credentials, connection strings) is managed through environment variables loaded from a `.env` file. The Docker Compose file references these variables using `${VARIABLE_NAME}` syntax, allowing for consistent configuration across all services.

To support this dynamic configuration, the application code was modified to construct the MongoDB connection URI programmatically. The `app.module.ts` file implements a `buildMongoUri` function that reads environment variables (`MONGO_INITDB_ROOT_USERNAME`, `MONGO_INITDB_ROOT_PASSWORD`, `MONGO_INSTANCE_NAME`, `MONGO_INITDB_DATABASE`) and constructs the connection string at runtime using NestJS's `ConfigService`.

### Network Segmentation

All services are connected to a single bridge network (`app-network`), enabling:
- Service discovery by container name (e.g., `mongodb` hostname resolves to the MongoDB container)
- Isolated communication - services cannot be accessed from outside the Docker network

### Health Checks

A Simple Health check is implemented at the Docker Compose level rather than in the Dockerfile. 
This decision to handle health checks at the orchestration level provides flexibility to configure different health check strategies for different environments without rebuilding images.

## 4. Automation (CI/CD)

**File References**: 
- [`.github/workflows/ci.yml`](.github/workflows/ci.yml) - GitHub Actions CI pipeline definition
- [`flux/apps/devops-challenge-app.yaml`](flux/apps/devops-challenge-app.yaml) - Flux HelmRelease for CD

### Continuous Integration: GitHub Actions

The CI pipeline was implemented using GitHub Actions. This choice was made based on several advantages:

- **Fast project building**: GitHub Actions provides immediate access to pre-configured build environments, eliminating setup time
- **Rich ecosystem**: Extensive library of pre-built actions developed by the community simplifies CI integration without writing custom scripts
- **Ephemeral machines**: Jobs run on temporary virtual machines that are automatically provisioned and destroyed, eliminating the need to maintain dedicated VMs or deployment servers like Jenkins
- **Tight GitHub integration**: Native integration with GitHub repositories, pull requests, and security features

### CI Pipeline Stages

The pipeline is triggered on Git tag pushes and manual workflow dispatches. It executes three parallel jobs initially, followed by a sequential build and deployment phase:

**Job 1: Code Quality (MegaLinter)**
- Performs comprehensive code quality checks using MegaLinter
- Validates JavaScript/TypeScript code standards and formatting
- Can automatically apply fixes via pull requests

**Job 2: Static Application Security Testing (CodeQL)**
- Deep security analysis using GitHub's CodeQL engine
- Scans for security vulnerabilities in JavaScript/TypeScript code
- Automatically uploads findings to GitHub's Security tab for tracking

**Job 3: Test, Build, and Push (Sequential phases)**
After the code quality and security jobs complete successfully:

1. **Test Phase**: Builds the test Docker image using the `test` target, sets up a test MongoDB instance, waits for database readiness, and executes a simple end-to-end test in an isolated container environment

2. **Build Phase**: If tests pass, builds the production Docker image using the `production` target, leveraging build cache from the test phase for efficiency

3. **Security Scanning Phase**: Performs Software Composition Analysis (SCA) on the production image using Trivy scanner, generating reports in both table and SARIF formats and uploading results to GitHub Security

4. **Deployment Phase**: Extracts the Docker image tag from Git tags or branch names, authenticates with Docker Hub, and pushes the successfully tested and scanned image to a public Docker repository

### Tool Selection Rationale

Tools were selected based on three primary criteria: **popularity**, **ease of use**, and **open-source availability**. For example, Trivy was chosen over Docker Scout for container image scanning because:
- **Maturity**: Trivy is a more mature and widely adopted solution in the container security space
- **Open-source**: Trivy is fully open-source, providing transparency and avoiding vendor lock-in
- **Community support**: Larger community and extensive documentation make it easier to integrate and troubleshoot

### Continuous Deployment: Flux

Continuous Deployment was implemented using Flux CD (Flux), which was set up after completing the Kubernetes cluster deployment and application manifest creation (points 6-7 in this challenge). Flux was selected for several key reasons:

- **Git as source of truth**: Flux maintains the cluster state based on what is defined in Git, ensuring declarative infrastructure and enabling version control for all changes
- **Lightweight**: Compared to similar GitOps tools like ArgoCD, Flux has a smaller resource footprint and simpler architecture while providing the same core functionality
- **Native Kubernetes integration**: Built as Kubernetes-native controllers, making it a natural fit for Kubernetes environments

### Flux Implementation

The Flux installation was performed using `flux bootstrap`, which automatically installs the Flux components in the cluster and sets up Git repository synchronization. Once installed, a `HelmRelease` Custom Resource Definition (CRD) was created in the `flux/apps` directory to enable automatic application deployment and upgrades.

The HelmRelease resource is configured to:
- Monitor the Git repository for changes to the Helm chart
- Automatically deploy and upgrade the application when new image versions are detected
- Use Helm charts defined in the repository, allowing for versioned and tested deployment configurations

This GitOps approach ensures that the cluster state always matches the desired state defined in version control, with automatic reconciliation and self-healing capabilities.


## 5. Security Fundamentals

**File References**: 
- [`.gitignore`](.gitignore) - Excludes `.env` files from version control
- [`k8s-manifests/devops-challenge-app/templates/mongodb-secret.yaml`](k8s-manifests/devops-challenge-app/templates/mongodb-secret.yaml) - Kubernetes Secret template
- [`k8s-manifests/devops-challenge-app/templates/app-deployment.yaml`](k8s-manifests/devops-challenge-app/templates/app-deployment.yaml) - Application deployment with security contexts
- [`k8s-manifests/devops-challenge-app/templates/mongodb-deployment.yaml`](k8s-manifests/devops-challenge-app/templates/mongodb-deployment.yaml) - MongoDB deployment with security contexts

Security was a primary consideration throughout the development of this project. Multiple layers of security measures were implemented across different stages of the development and deployment lifecycle, addressing secrets management, container security, and access control.

### Secrets Management

Secrets management was implemented using different strategies appropriate for each environment, ensuring sensitive credentials are never exposed in version control or configuration files.

#### Local Development (Docker Compose)

For local development environments, secrets are managed through `.env` files that are explicitly excluded from version control via `.gitignore`. This approach:

- **Prevents accidental credential exposure**: By ensuring `.env` files are never committed to Git repositories
- **Simplifies local development**: Developers can easily configure environment-specific credentials without modifying tracked configuration files
- **Enforces best practices**: The `.gitignore` exclusion serves as a reminder to developers about the importance of not committing sensitive data.

#### Continuous Integration (GitHub Actions)

In the CI pipeline implemented with GitHub Actions, secrets are managed through **GitHub Secrets**, which provide a secure, centralized mechanism for storing sensitive information. This choice offers several advantages:

- **Secure storage**: GitHub Secrets are encrypted at rest and are only accessible during workflow execution
- **Access control**: Secrets can be scoped to specific repositories and environments, limiting exposure
- **No exposure in logs**: GitHub automatically redacts secret values from workflow logs

This approach ensures that CI/CD pipelines can securely access credentials needed for building, testing, and pushing Docker images without exposing sensitive data in code or configuration files.

#### Continuous Deployment (Kubernetes)

For the Kubernetes production environment, secrets are managed using **Kubernetes Secrets**. In this implementation:

- **Manual secret creation**: Secrets were created manually using `kubectl` before deploying the Helm chart
- **Helm chart integration**: The Helm chart supports using existing secrets through the `existingSecret` configuration option, avoiding the need to store credentials in `values.yaml`

**Production-Ready Approach**: For a production environment, manual secret creation would be replaced with **External Secrets Operator (ESO)**, which provides automated secret synchronization from external secret management systems. Two primary options were considered:

- **AWS Systems Manager Parameter Store**: Preferred for simple, AWS-native environments. This solution offers:
  - Zero cost for Standard parameters (suitable for credential storage)
  - Native AWS integration with IAM-based access control
  - Automatic encryption via AWS KMS
  - Seamless integration with External Secrets Operator
  - CloudTrail audit logging

- **HashiCorp Vault**: Preferred for complex environments requiring:
  - Multi-cloud deployments
  - Advanced secret rotation policies
  - Complex access control requirements beyond IAM
  - Dynamic secret generation
  - On-premises or hybrid deployments

For this use case, AWS Systems Manager Parameter Store would be the optimal choice due to its simplicity, cost-effectiveness (free Standard parameters), and seamless AWS integration. However, HashiCorp Vault would be considered if the deployment required multi-cloud capabilities or more complex secret management policies.

### Secure Container Configuration

Container security was ensured through multiple mechanisms:

#### Non-Root User Execution

All container stages in the Dockerfile run as a non-root user (`node` user with UID 1000), following the principle of least privilege. This reduces the attack surface by:
- Preventing privilege escalation attacks
- Limiting potential damage if a container is compromised
- Meeting security compliance requirements

#### Least Privilege Principles

The Kubernetes deployment enforces additional security measures:

- **Security Contexts**: Both application and MongoDB containers are configured with security contexts that:
  - Prevent privilege escalation (`allowPrivilegeEscalation: false`)
  - Drop all Linux capabilities (`capabilities.drop: [ALL]`)
  - Enforce non-root execution (`runAsNonRoot: true`)

- **Pod Security Context**: Pod-level security contexts ensure containers cannot access resources beyond their required permissions

These security configurations, combined with the multi-stage build pattern that minimizes the production image attack surface, provide a robust security foundation for containerized applications.

### Network Security

Network security was addressed through multiple layers:

- **Kubernetes**: Services use ClusterIP type, ensuring they are only accessible within the cluster and not exposed externally. In environments with multiple applications across multiple namespaces, Kubernetes Network Policies could be introduced to implement micro-segmentation, allowing fine-grained control over pod-to-pod communication and enforcing the principle of least privilege at the network level
- **AWS Infrastructure**: Security groups and network ACLs enforce strict firewall rules (documented in section 6)


## 6. Infrastructure as Code (IaC)

**File References**: 
- [`terraform/k8s-cluster/`](terraform/k8s-cluster/) - Main Terraform configuration directory
  - [`terraform/k8s-cluster/main.tf`](terraform/k8s-cluster/main.tf) - Main Terraform configuration
  - [`terraform/k8s-cluster/vpc.tf`](terraform/k8s-cluster/vpc.tf) - VPC and networking configuration
  - [`terraform/k8s-cluster/ec2.tf`](terraform/k8s-cluster/ec2.tf) - EC2 instances and IAM roles
  - [`terraform/k8s-cluster/security-groups.tf`](terraform/k8s-cluster/security-groups.tf) - Security group rules
  - [`terraform/k8s-cluster/k8s-setup.tf`](terraform/k8s-cluster/k8s-setup.tf) - Kubernetes installation user data scripts
  - [`terraform/k8s-cluster/haproxy.tf`](terraform/k8s-cluster/haproxy.tf) - HAProxy configuration
  - [`terraform/k8s-cluster/templates/haproxy.cfg.tpl`](terraform/k8s-cluster/templates/haproxy.cfg.tpl) - HAProxy template

### Terraform Configuration

A comprehensive Terraform configuration was created in the `terraform/k8s-cluster` directory to provision all necessary AWS cloud infrastructure for deploying a Kubernetes cluster. The infrastructure was designed with cost optimization and security as primary considerations.

### Infrastructure Overview

The Terraform configuration provisions **4 EC2 instances** organized in a secure network topology:

**1 Control Plane Node** (1x master):
- Located in the private subnet for security
- Instance type: `t3.small` (selected to balance minimal required Kubernetes control plane resources with cost efficiency)
- Automatically installs and configures Kubernetes control plane components using kubeadm on first boot via user data scripts

**2 Worker Nodes**:
- Located in the private subnet
- Instance type: `t3.small` (chosen to provide sufficient resources for running containerized workloads while minimizing AWS costs)
- Automatically join the Kubernetes cluster on first boot using kubeadm join command

**1 Bastion Host**:
- Located in the public subnet with internet gateway access
- Instance type: `t3.micro` (smallest viable instance type to minimize costs while providing necessary functionality)
- Serves as the entry point for SSH access and HTTP traffic forwarding to the Kubernetes cluster
- Configured with HAProxy to act as a reverse proxy and load balancer

### Network Architecture

The infrastructure implements a secure network design with:

- **VPC**: Custom Virtual Private Cloud with CIDR `10.0.0.0/16`
- **Public Subnet**: Contains the bastion host with direct internet access via Internet Gateway
- **Private Subnet**: Contains all Kubernetes nodes (control plane and workers) with outbound internet access via NAT Gateway
- **Security Groups**: Strict firewall rules limiting access between components (e.g., bastion can SSH to k8s nodes, but nodes cannot be accessed directly from internet)

### Kubernetes Installation

Kubernetes cluster installation is fully automated through user data scripts executed on first boot. The control plane node automatically:
- Configures system prerequisites (disables swap, loads kernel modules, configures networking)
- Installs containerd, kubeadm, kubelet, and kubectl
- Initializes the Kubernetes cluster using kubeadm
- Sets up networking and stores cluster join tokens in AWS Systems Manager Parameter Store

Worker nodes automatically retrieve join tokens from Parameter Store and join the cluster during boot.

### HAProxy on Bastion Host

To reduce infrastructure costs, HAProxy was installed and configured on the bastion host instead of using AWS managed load balancers (Application Load Balancer or Network Load Balancer). HAProxy:
- Forwards SSH traffic (port 22) to Kubernetes nodes for secure access
- Acts as reverse proxy for HTTP/HTTPS traffic (ports 80/443) to forward application traffic to the Kubernetes cluster
- Exposes Kubernetes API server on port 6443 for cluster administration
- Automatically configures backend servers based on control plane and worker node IPs discovered via Terraform
- Provides a cost-effective alternative to AWS ELB/ALB while maintaining functionality

The HAProxy configuration is dynamically generated by Terraform templates and automatically deployed to the bastion host whenever node IPs change.

### Cost Optimization

Instance types and sizes were carefully selected to provide the minimal required resources while minimizing AWS costs:
- **t3.small** for Kubernetes nodes: Provides 2 vCPUs and 2GB RAM, sufficient for running a development/test Kubernetes cluster
- **t3.micro** for bastion: Minimal instance size (1 vCPU, 1GB RAM) since it only handles proxy traffic
- All instances use encrypted GP3 EBS volumes sized at 20GB (minimal viable size)
- NAT Gateway is the primary cost component but necessary for private subnet outbound internet access

This configuration provides a functional Kubernetes cluster suitable for development and testing while keeping AWS infrastructure costs to a minimum.

## 7. Kubernetes Manifests

**File References**: 
- [`k8s-manifests/devops-challenge-app/`](k8s-manifests/devops-challenge-app/) - Helm chart directory
  - [`k8s-manifests/devops-challenge-app/Chart.yaml`](k8s-manifests/devops-challenge-app/Chart.yaml) - Chart metadata
  - [`k8s-manifests/devops-challenge-app/values.yaml`](k8s-manifests/devops-challenge-app/values.yaml) - Default configuration values
  - [`k8s-manifests/devops-challenge-app/templates/`](k8s-manifests/devops-challenge-app/templates/) - Kubernetes manifest templates
    - [`k8s-manifests/devops-challenge-app/templates/_helpers.tpl`](k8s-manifests/devops-challenge-app/templates/_helpers.tpl) - Template helpers
    - [`k8s-manifests/devops-challenge-app/templates/app-deployment.yaml`](k8s-manifests/devops-challenge-app/templates/app-deployment.yaml) - Application deployment
    - [`k8s-manifests/devops-challenge-app/templates/app-service.yaml`](k8s-manifests/devops-challenge-app/templates/app-service.yaml) - Application service
    - [`k8s-manifests/devops-challenge-app/templates/mongodb-deployment.yaml`](k8s-manifests/devops-challenge-app/templates/mongodb-deployment.yaml) - MongoDB deployment
    - [`k8s-manifests/devops-challenge-app/templates/mongodb-service.yaml`](k8s-manifests/devops-challenge-app/templates/mongodb-service.yaml) - MongoDB service
    - [`k8s-manifests/devops-challenge-app/templates/mongodb-secret.yaml`](k8s-manifests/devops-challenge-app/templates/mongodb-secret.yaml) - MongoDB secret template
    - [`k8s-manifests/devops-challenge-app/templates/ingress.yaml`](k8s-manifests/devops-challenge-app/templates/ingress.yaml) - Ingress resource
- [`k8s-manifests/ingress-nginx/install-nginx-ingress.sh`](k8s-manifests/ingress-nginx/install-nginx-ingress.sh) - Nginx Ingress installation script

### Helm Chart Implementation

A comprehensive Helm chart was created in the `k8s-manifests/devops-challenge-app` directory to manage the application and its database deployment on Kubernetes. Helm was chosen for its templating capabilities, version management, and ease of deployment across different environments.

### Chart Structure

The Helm chart follows Kubernetes best practices with a modular structure:

- **Chart.yaml**: Defines chart metadata, version, and dependencies
- **values.yaml**: Centralized configuration file containing all customizable parameters with sensible defaults
- **templates/**: Contains Kubernetes manifest templates that are rendered using Helm templating engine
- **_helpers.tpl**: Shared template helpers for consistent naming and labeling across all resources

### Kubernetes Resources

The chart provisions the following Kubernetes resources:

**Application Resources:**
- **Deployment**: Manages the NestJS application pods with configurable replica count (default: 2)
- **Service**: ClusterIP service exposing the application internally within the cluster
- **ConfigMap**: Stores non-sensitive application configuration (environment variables like NODE_ENV, PORT)
- **Ingress**: Routes external HTTP/HTTPS traffic to the application service

**MongoDB Resources:**
- **Deployment**: Manages MongoDB pod with persistent storage
- **Service**: ClusterIP service exposing MongoDB on port 27017
- **Secret**: #TODO: FIX secrets
- **PersistentVolume (PV)**: Static volume provisioning for database data persistence
- **PersistentVolumeClaim (PVC)**: Requests storage from the PersistentVolume

**Common Resources:**
- **Namespace**: Isolates the application and its resources in a dedicated namespace (default: production)

### Kubernetes Best Practices

The Helm chart implements several Kubernetes best practices:

**Resource Limits and Requests:**
- Application containers define resource requests (256Mi memory, 100m CPU) and limits (512Mi memory, 500m CPU) to ensure fair resource allocation and prevent resource exhaustion
- MongoDB containers define resource requests (512Mi memory, 250m CPU) and limits (1Gi memory, 500m CPU) based on database workload requirements

**Health Checks:**
- **Liveness Probes**: Application uses HTTP GET on path `/` with 40-second initial delay to determine if the container needs to be restarted
- **Readiness Probes**: Application uses HTTP GET with 30-second initial delay to determine when the container is ready to receive traffic
- **MongoDB Probes**: Uses `mongosh` exec commands to ping the database, ensuring the database is alive and ready to accept connections

**Security:**
- **Pod Security Context**: Application runs as non-root user (UID 1000) with restricted capabilities (all capabilities dropped)
- **Container Security Context**: Both application and MongoDB containers enforce non-root execution, prevent privilege escalation, and follow least privilege principles
- **Secrets Management**: Sensitive data stored in Kubernetes Secrets

**High Availability:**
- Application deployment supports horizontal scaling with configurable replica count
- Health probes ensure only healthy pods receive traffic during deployments and failures

**Storage:**
- MongoDB uses PersistentVolume (PV) and PersistentVolumeClaim (PVC) for data persistence, chosen for ease of implementation
- Static PV provisioning with hostPath backend was used, though a dynamic volume provisioner (StorageClass) would be the preferred approach in production environments
- Due to the hostPath volume limitation (volumes are node-specific), MongoDB deployment is forced to run on a specific worker node using a nodeSelector based on hostname
- InitContainer ensures proper file permissions on persistent volumes before MongoDB starts
- PersistentVolume configured with Retain reclaim policy to preserve data across pod deletions

**Note on Storage Improvement**: There is margin for improvement in the storage configuration. Using a dynamic StorageClass would eliminate the need for node pinning, allowing MongoDB to run on any node while maintaining data persistence. This would improve high availability and make the deployment more resilient to node failures.

### Ingress Controller Installation

The Nginx Ingress Controller was manually installed by executing the commands defined in `install-nginx-ingress.sh`. The installation script:

- Adds the official Nginx Ingress Helm repository
- Installs the ingress controller using Helm with NodePort service type
- Configures NodePorts 30080 (HTTP) and 30443 (HTTPS) to align with HAProxy configuration on the bastion host

This NodePort configuration allows HAProxy on the bastion host to forward HTTP/HTTPS traffic to the ingress controller, which then routes requests to the appropriate application services based on Ingress rules. The manual installation approach provides full control over the ingress controller configuration and eliminates the need for additional AWS load balancers.


