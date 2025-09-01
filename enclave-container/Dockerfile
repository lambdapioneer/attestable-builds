FROM ubuntu:24.04
WORKDIR /app
ARG RUNNER_VERSION="2.328.0"

# Add the runner user (executes all build tasks and the GitHub runner)
RUN useradd -m runner --uid 1001

# Everything required for VSOCK proxying of HTTPS and SSH
RUN apt-get update -y --fix-missing
RUN apt-get upgrade -y --fix-missing
RUN apt-get install -y net-tools iptables iproute2 bash curl socat openssh-server
RUN apt-get clean

RUN apt-get install -y --fix-missing sudo gpg
RUN apt-get clean

# Install containerd and gvisor
RUN install -m 0755 -d /etc/apt/keyrings
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
RUN chmod a+r /etc/apt/keyrings/docker.asc
RUN echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

RUN curl -fsSL https://gvisor.dev/archive.key | sudo gpg --dearmor -o /usr/share/keyrings/gvisor-archive-keyring.gpg
RUN echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/gvisor-archive-keyring.gpg] https://storage.googleapis.com/gvisor/releases release main" | sudo tee /etc/apt/sources.list.d/gvisor.list > /dev/null

RUN apt-get update
RUN apt-get install containerd.io zstd runsc -y --fix-missing

# configure containerd to use gvisor
RUN cat <<EOF | sudo tee /etc/containerd/config.toml
version = 2
[plugins."io.containerd.runtime.v1.linux"]
  shim_debug = true
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  runtime_type = "io.containerd.runc.v2"
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
  runtime_type = "io.containerd.runsc.v1"
EOF

RUN mkdir -p "github-runner/output"
RUN mkdir -p "github-runner/hooks"

# Copy over everything
COPY dist .

# The github action is executed by its own user
RUN chown -R runner:runner "github-runner/"

# Prepare entry points
RUN chmod +x /app/entry.sh
RUN chmod +x /app/run.sh
RUN chmod +x /app/setup.sh

# Prepare tunneling helpers
RUN chmod +x /app/dnsproxy
RUN chmod +x /app/ip-to-vsock-transparent

# The enclave client is run by the runner user as well
RUN chown runner:runner /app/enclave-client
RUN chmod +x /app/enclave-client

# Setup SSH
RUN mkdir -p /root/.ssh && chmod 0700 /root/.ssh/
RUN mv authorized_keys /root/.ssh/
RUN chmod 0600 /root/.ssh/authorized_keys

# READY
ENTRYPOINT ["/app/entry.sh"]
