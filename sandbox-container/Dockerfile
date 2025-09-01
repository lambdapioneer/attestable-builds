FROM debian:bookworm-slim
WORKDIR /app
ARG RUNNER_VERSION="2.328.0"

# Add the runner user (executes all build tasks and the GitHub runner)
RUN useradd -m runner --uid 1001

# Everything required for our proxying etc
RUN apt-get update -y --fix-missing
RUN apt-get upgrade -y --fix-missing
RUN apt-get install -y iptables iproute2 bash curl
RUN apt-get clean

# <runner-dependencies>
# Everything required for the action runner
# Keep this in sync with `envlave-wet-container/Dockerfile`.
RUN apt-get install -y --fix-missing jq ca-certificates libssl-dev libicu-dev git sudo
RUN apt-get clean
# </runner-dependencies>

# <build-dependencies>
# These are all dependencies required for the builds of our projects. In the long run
# they should match those of the official GitHub Actionn runner.
# Keep this in sync with `envlave-wet-container/Dockerfile`.
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

# Get the dist in
COPY dist .

# The github action is executed by its own user
RUN chown -R runner:runner "/app"

# Prepare entry points
RUN chmod +x /app/entry.sh
RUN chmod +x /app/run.sh
RUN chmod +x /app/setup.sh

# READY 
CMD ["/bin/bash"]
