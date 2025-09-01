# Attestable Builds

> [!NOTE]
> If you are here for the artifact evaluation, please check out the [walkthrough.md](https://github.com/lambdapioneer/attestable-builds/blob/artifact-eval/walkthrough.md) guide in the dedicated `artifact-eval` branch.

> [!WARNING]  
> This is a snapshot of a research prototype and is not intended for production use.

This is a prototype implementation for the ``Attestable Builds`` paper.
It allows executing GitHub Actions in a sandboxed environment inside an AWS Nitro Enclave.
For the sake of the academic prototype, we assume that the AWS Nitro Enclave security properties hold as advertised.

The outer AWS Nitro Enclave called [`enclave-container`](enclave-container/) ensures that our image is actually executed and cannot be compromised by the host.
The inner container called [`sandbox-container`](sandbox-container/) ensures that the "untrusted" code from the GitHub Actions is executed in a sandboxed environment.

## Development

[![Rust](https://github.com/lambdapioneer/attestable-builds/actions/workflows/rust.yml/badge.svg)](https://github.com/lambdapioneer/attestable-builds/actions/workflows/rust.yml)
[![System](https://github.com/lambdapioneer/attestable-builds/actions/workflows/system.yml/badge.svg)](https://github.com/lambdapioneer/attestable-builds/actions/workflows/system.yml)
[![Python](https://github.com/lambdapioneer/attestable-builds/actions/workflows/python.yml/badge.svg)](https://github.com/lambdapioneer/attestable-builds/actions/workflows/python.yml)

We currently support two deployment modes:

1. Local Development Mode:
- Webhook requests are forwarded from your domain (e.g. yourdomain.com:8000) to your local machine
- The host-server runs containers using Docker directly (no enclave)
- Ideal for development and testing

2. AWS:
- we deploy the host-server on an AWS instance
- the host-server starts Nitro Enclaves which use `runc` to start the sandbox container


In both cases, all configuration should be provided in the `.env` file, which is git-ignored and thus not committed to the repository.
See the included `.env.template` file for the required configurations.
At the very least, you will need to update the following configurations (replaced with your values):

```
GITHUB_REPOSITORY=organization/repository
GITHUB_PAT_TOKEN=github_pat_REPLACEME
```

The `GITHUB_PAT_TOKEN` is a PAT token that should allow for the given `GITHUB_REPOSITORY` at least the following permissions:
- Read access to actions variables, code, commit statuses, environments, metadata, pull requests, repository hooks, and secrets
- Read and Write access to actions, administration, and workflows

You can create them here: https://github.com/settings/tokens?type=beta

## Environment Variables

To configure your environment, start by copying the `.env.template` file to `.env`:
```
cp .env.template .env
```
Then modify the values in `.env` according to your setup. The following environment variables need to be configured:

### GitHub Configuration
- `GITHUB_REPOSITORY`: The organization/repository path (e.g., "organization/repo")
- `GITHUB_PAT_TOKEN`: GitHub Personal Access Token with required permissions

### AWS Configuration (Required for AWS deployment)
- `AWS_IMAGE_ID`: AMI ID of your configured AWS image
- `AWS_KEY_NAME`: Name of your AWS SSH key pair
- `AWS_SG_ID`: Security Group ID for the EC2 instance
- `AWS_EIP_ALLOC_ID`: Allocation ID of your Elastic IP
- `AWS_SSH_KEYS_PATH`: Path to your SSH keys for EC2 access

### Attestation Transparency Log Configuration
- `TRANSPARENCY_LOG_BASE_URL`: Base URL for the attestation transparency log
- `TRANSPARENCY_LOG_USERNAME`: Username for log access
- `TRANSPARENCY_LOG_PASSWORD`: Password for log access
- `TRANSPARENCY_LOG_ID`: Unique identifier for the transparency log

### GitHub Runner Configuration
- `RUNNER_VERSION`: Version of the GitHub Actions runner to use
- `RUNNER_USER`: Username for the runner (default: "runner")
- `RUNNER_UID`: User ID for the runner (default: 1001)
- `RUNNER_GID`: Group ID for the runner (default: 1001)

### Local Development Configuration
- `LOCAL_NETWORK_INTERFACE`: Network interface to use for local development (e.g., "eth0"). This is used by the `scripts/setup-local-net-ns.sh` script for setting up network namespaces. You can find your interface name using `ip link show` or `ifconfig`.

### Local Development CLI Arguments

For easier local development and testing, the host server supports several `--fake` CLI arguments that simulate various components:

- `--simulate-webhook-event`: Instead of waiting for an actual GitHub webhook event, simulates a job with ID 42 being started.
- `--simulate-client-use-fake-runner=<subproject_dir[@commit_hash]>`: Uses a simulated runner instead of the actual GitHub Actions runner. The argument format is `subproject_dir[@commit_hash]` where:
  - `subproject_dir`: The directory containing the project to run
  - `commit_hash`: (Optional) The specific commit hash to use
- `--simulate-client-use-fake-attestation`: Uses a fake attestation document instead of generating a real one
- `--simulate-log-publishing`: Simulates the log publishing service

Example usage:
```bash
# Run with all simulations enabled for a specific project
./target/debug/host-server local --simulate-webhook-event --simulate-client-use-fake-runner=project_c_simple --simulate-client-use-fake-attestation --simulate-log-publishing

# Run with just webhook simulation and fake attestation
./target/debug/host-server local --simulate-webhook-event --simulate-client-use-fake-attestation
```

## Local

### Requirements

- [Docker](https://docs.docker.com/engine/install/)
- [Docker Compose](https://docs.docker.com/compose/install/)
- [Rust](https://www.rust-lang.org/learn/get-started)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
  

#### Rust
One possible way to install Rust on your system is to use a tool called Rustup via the following command:

```
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```
#### AWS CLI

The AWS CLI provides an interface to communicate with AWS services via the command line. 
On Linux you can use the command line installer to install the tool:
```
$ curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws configure
```

### Setup

We point our webhook domain to our remote server (which we later tunnel to our machine).
For convenience in referencing it, we add the following lines to our SSH config (`~/.ssh/config`):

```
Host action-webhook
  HostName <your-remote-server-ip>
  User <your-remote-server-user>
  # any additional configuration (e.g. IdentityFile)
```

We can then add the tunnel using the script: `./scripts/forward-from-server.sh`.
Keep that one running in a terminal.

### Running

For local development:
```bash
# Terminal 1: Set up port forwarding
./scripts/forward-from-server.sh

# Terminal 2: Start the host server
cargo run --bin host-server -- local
```

You should be able to see some outputs in the console when you open the external domain in your browser.
For example, you can open `http://action-webhook:8000` in your browser and see a simple "OK" response.

In your target repository, you can now register the domain as a webhook.
For this navigate to `https://github.com/ORGANIZATION/REPOSITORY/settings/hooks/new` and add the webhook URL.
Select the `application/json` content type and the "Workflow jobs" trigger.
After saving, a first ping should be sent to the server, which should be displayed in the console.

> [!TIP]
> Use the "Recent Deliveries" tab in webhook settings to debug and retry deliveries.

You can now push a new commit to the repository and see the action being executed in the console.
Alternatively, configure your workflow with the `workflow_dispatch` trigger and manually trigger the workflow.

## AWS

### Requirements

- [Create an AWS account](https://docs.aws.amazon.com/accounts/latest/reference/manage-acct-creating.html)
- Learn to [Control Your AWS Costs](https://aws.amazon.com/getting-started/hands-on/control-your-costs-free-tier-budgets/)
- Setup a dedicated [IAM user](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users.html)

#### AWS account

First, you need to [Create an AWS account](https://docs.aws.amazon.com/accounts/latest/reference/manage-acct-creating.html).
This account will be your root user for your AWS environment.
For security reasons, it is highly recommended to enable MFA and to create a dedicated IAM user with least privileges. 
The IAM user needs permission to create, start, stop, and to delete EC2 instances. 

> [!TIP]
> To have a better overview about your current costs, it is advisible to read through the [Control Your AWS Costs](https://aws.amazon.com/getting-started/hands-on/control-your-costs-free-tier-budgets/) article. 

### Setup

Create a new EC2 instance with the following configuration:
- Amazon Linux 2 AMI (HVM)
- SSD with at least 32 GiB (maybe treat yourself to higher throughput)
- m5a.xlarge (4 vCPUs, 16 GiB memory)
- Enable AWS Nitro

It's a good idea to use choose the default region (e.g. `us-east-1`).
Next create a new Elastic IP and associate it with the instance.
Point your domain to the Elastic IP.
Update the security group to allow incoming traffic on port 8000.

On that machine follow the instructions from the [AWS Nitro tutorial](https://docs.aws.amazon.com/enclaves/latest/user/nitro-enclave-cli-install.html) and make sure to install the following packages on the system:

```
sudo dnf install aws-nitro-enclaves-cli aws-nitro-enclaves-cli-devel -y
sudo dnf install openssl-devel protobuf-compiler protobuf-devel -y
sudo dnf install git tmux htop tree -y
sudo yum groupinstall "Development Tools" -y
sudo usermod -aG ne ec2-user
sudo systemctl enable --now nitro-enclaves-allocator.service
sudo systemctl enable --now docker
```

Run the following command to install rust:
```
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
. "$HOME/.cargo/env"
```

Install and configure docker environment:
```
sudo yum update -y
sudo yum install -y docker
sudo service docker start
sudo usermod -a -G docker ec2-user
```

We create a SSH key that you should add to the respective repositories or your user account:

```
ssh-keygen -t ed25519
cat /home/ec2-user/.ssh/id_ed25519.pub
```

Next checkout the repository and build the host-server.

```
cd ~
git clone <INSERT GIT REPOSITORY> && cd action-squares/
cargo build
touch .env
make build-norris-enclave
```

Shutdown the instance and create an AMI image from it.
Then terminate it.

Back on your local machine, install the AWS-CLI, authenticate, and make sure to set your default region to the one where your instance is running.

For the AWS setup, we need to provide the following configuration in the `.env` file:

```
AWS_IMAGE_ID=ami-???
AWS_KEY_NAME=???
AWS_SG_ID=sg-???
AWS_EIP_ALLOC_ID=eipalloc-???
```

### Running

You can now use the script `./scripts/aws-start-server.sh` to start the instance and deploy the EC2 instance from the saved AMI image.

SSH into the instance and build the Nitro image:

```
make build-enclave-container
```

Start the host-server using the following command:

```
cargo run --bin host-server -- nitro
```

Proceed as with the local setup to register the webhook and trigger the action.
Since you are likely using the same domain, you should not need to re-add the webhook.

## License

The code in this repository is available under a [MIT license](LICENSE).
