#!/bin/bash
set -e;
. .env;

# Read the tag as the first argument from the CLI
if [ -z "$1" ]; then
    echo "Usage: $0 <tag>";
    exit 1;
fi
TAG="$1";
echo "[ ] Tag: $TAG";

HOSTNAME="stamp";
INSTANCE_TYPE="m5a.2xlarge";

# If the TAG contains "big" then we use the big image
if [[ "$TAG" == *"big"* ]]; then
    echo "[ ] Using the BIG configuration";
    INSTANCE_TYPE="m5a.8xlarge";
    AWS_IMAGE_ID="$AWS_BIG_IMAGE_ID";
    AWS_KEY_NAME="$AWS_BIG_KEY_NAME";
    AWS_SG_ID="$AWS_BIG_SG_ID";
    AWS_EIP_ALLOC_ID="$AWS_BIG_EIP_ALLOC_ID";
    AWS_SSH_KEYS_PATH="$AWS_BIG_SSH_KEYS_PATH";
    HOSTNAME="stamp-big";
fi

echo "$AWS_EIP_ALLOC_ID"

# Check if there is already an instance with tag "$TAG"; in that case exit
# shellcheck disable=SC2046
if [ $(aws ec2 describe-instances --filters "Name=tag:LSID,Values=$TAG" --query 'Reservations[*].Instances[*].[InstanceId]' --output text | wc -l) -gt 0 ]; then
    echo "[ ] An instance with tag '$TAG' already exists. Exiting."
    exit 0
fi

# Otherwise create a new instance from our image and tag it
echo "[ ] Creating new instance from image and tagging it as '$TAG'";
sleep 1;
aws ec2 --no-cli-pager run-instances --image-id "$AWS_IMAGE_ID" \
  --key-name "$AWS_KEY_NAME" \
  --enclave-options 'Enabled=true' \
  --security-group-ids "$AWS_SG_ID" \
  --instance-type $INSTANCE_TYPE \
  --tag-specifications "ResourceType=instance,Tags=[{Key=LSID,Value=$TAG},{Key=Name,Value=$TAG}]";
echo "[+] Instance created and tagged as '$TAG'";

# Discover the instance ID
INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:LSID,Values=$TAG" --query 'Reservations[*].Instances[*].[InstanceId]' --output text);
echo "[ ] Instance ID: $INSTANCE_ID";

# Wait until new instance is running
echo "[ ] Waiting for instance to be running";
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --no-paginate;
echo "[+] Instance is running";

# Assign our elastic IP to it
echo "[ ] Assigning elastic IP to new instance";
aws ec2 associate-address --instance-id "$INSTANCE_ID" --allocation-id "$AWS_EIP_ALLOC_ID" --no-paginate;
echo "[+] Elastic IP assigned to new instance";

# Get the elastic IP
echo "[ ] Getting the elastic IP";
AWS_EIP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[*].Instances[*].[PublicIpAddress]' --output text);
echo "[+] Elastic IP: $AWS_EIP";

# Remove the old host key from known_hosts
echo "[ ] Removing old host key from known_hosts";
ssh-keygen -R "$AWS_EIP";

# If the AWS_SSH_KEYS_PATH is set, copy over the SSH key
if [ -n "$AWS_SSH_KEYS_PATH" ]; then
  # Wait until AWS_EIP is reachable via SSH
  echo "[ ] Waiting for instance to be reachable via SSH";
  while ! ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no "$HOSTNAME" echo "[+] Connected]"; do
    echo "trying again...";
    sleep 5;
  done

  echo "[ ] Copying over the SSH key";
  scp "$AWS_SSH_KEYS_PATH/id_ed25519" "$HOSTNAME:~/.ssh/id_ed25519";
  scp "$AWS_SSH_KEYS_PATH/id_ed25519.pub" "$HOSTNAME:~/.ssh/id_ed25519.pub";
fi

# Copy over the .env file
echo "[ ] Copying over the .env file";
scp ".env" "$HOSTNAME:~/attestable-builds/";

echo "[+] ALL DONE";
