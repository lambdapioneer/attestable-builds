FROM ubuntu:24.04
WORKDIR /app
ARG RUNNER_VERSION="2.328.0"

# Add the runner user (executes all build tasks and the GitHub runner)
RUN useradd -m runner --uid 1001

# Everything required for VSOCK proxying of HTTPS and SSH
RUN apt-get update -y --fix-missing
RUN apt-get upgrade -y --fix-missing
RUN apt-get install -y net-tools iptables iproute2 bash curl socat openssh-server zstd
RUN apt-get clean

# <runner-dependencies>
# Everything required for the action runner
# Keep this in sync with `sandbox-container/Dockerfile`.
RUN apt-get install -y --fix-missing jq ca-certificates libssl-dev libicu-dev git sudo
RUN apt-get clean
# </runner-dependencies>

# <build-dependencies>
# These are all dependencies required for the builds of our projects. In the long run
# they should match those of the official GitHub Actionn runner.
# Keep this in sync with `sandbox-container/Dockerfile`.
RUN apt-get install -y --fix-missing build-essential pkg-config autopoint po4a libtool automake autoconf intltool libffi-dev git
# For LLVM
RUN apt-get install -y --fix-missing cmake python3-yaml zlib1g-dev
# For the kernel: https://canonical-kteam-docs.readthedocs-hosted.com/en/public/how-to/build-kernel.html
RUN apt-get install -y --fix-missing build-essential libncurses-dev bison flex libssl-dev libelf-dev fakeroot dwarves bc llvm lld clang
# For other projects
RUN apt-get install -y --fix-missing mkisofs isolinux liblzma-dev help2man texinfo gperf wget debiandoc-sgml
RUN apt-get clean

# Install Rust
RUN su runner -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --profile minimal -y';
# </build-dependencies>

# Donwload the action runner and assign it to the runner user
RUN mkdir -p "github-runner/$RUNNER_VERSION"
RUN cd "github-runner/$RUNNER_VERSION" && curl -O -L https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
  && tar xzf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz \
  && rm ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
RUN mkdir -p "github-runner/output"
RUN mkdir -p "github-runner/hooks"

# Copy over everything
COPY dist .

# The github action is executed by its own user
RUN chown -R runner:runner "github-runner/"

# Compress the runner folder using zstd
RUN tar -c "/app/github-runner/" | zstd -6 -z -T0 - > "/app/github-runner.tar.zst"
RUN rm -r "/app/github-runner/"

# Compress the runner home folder using zstd (that's mostly Rust & cargo)
RUN tar -c "/home/runner/" | zstd -6 -z -T0 - > "/home/runner.tar.zst"
RUN rm -r "/home/runner/"

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
