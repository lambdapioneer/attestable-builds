#!/bin/bash
set -e

if [ $# -ne 2 ]; then
  echo "Usage: $0 <GitHub Repo> <GitHub Token>"
  echo "Example: $0 linsm/ab-samples github_pat_1111AAAABBBBB...."
  exit 1
fi

github_repo=$1
github_token=$2

echo "[ ] Preparing the AWS instance for artifact evaluation"

sudo dnf install aws-nitro-enclaves-cli aws-nitro-enclaves-cli-devel -y
sudo dnf install openssl-devel protobuf-compiler protobuf-devel -y
sudo dnf install git tmux htop tree -y
sudo yum groupinstall "Development Tools" -y

sudo usermod -aG ne ec2-user
sudo systemctl enable --now docker
sudo service docker start
sudo usermod -a -G docker ec2-user

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
. "$HOME/.cargo/env"

ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519 -q

cargo build

cp .env.template .env

sed -i "s|^\(GITHUB_REPOSITORY=\).*|\1$github_repo|" .env
sed -i "s|^\(GITHUB_PAT_TOKEN=\).*|\1$github_token|" .env

make setup-add-user-runner
make setup-aws
. "$HOME/.cargo/env"
sudo systemctl enable --now nitro-enclaves-allocator.service

#install go
wget https://go.dev/dl/go1.25.0.linux-amd64.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.25.0.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

make build-third-party
make build-enclave-eif
make build-enclave-wet-eif

sudo docker system prune -a -f

make build-eval
./scripts/prepare-action-runner-for-local.sh
chmod o+rx ~
