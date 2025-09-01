#
# RUST THINGS
#

build-rust-enclave-client:
	cargo build -p enclave-client

build-rust-host-server:
	cargo build -p host-server

clean-rust:
	cargo clean

clippy-fmt:
	cargo clippy --fix --allow-dirty --allow-staged
	cargo fmt --all

#
# Sandbox
#

clean-sandbox:
	sudo rm -rf sandbox-container/build
	mkdir -p sandbox-container/build

build-sandbox:
	# Copy over content
	mkdir -p sandbox-container/dist
	cp sandbox-container/content/* sandbox-container/dist/

	# Copy over everything related to the GitHub action runner
	mkdir -p sandbox-container/dist/github-runner/hooks
	cp github-runner/hooks/attestation.sh sandbox-container/dist/github-runner/hooks/
	cp github-runner/hooks/log.sh sandbox-container/dist/github-runner/hooks/
	cp github-runner/hooks/pre_hook.sh sandbox-container/dist/github-runner/hooks/
	cp -r github-runner/simulated sandbox-container/dist/github-runner/

    # Build the rootfs image and collect everything in build/
	sudo docker build -t sandbox sandbox-container/
	mkdir -p sandbox-container/build
	sudo ./sandbox-container/create_rootfs.sh sandbox sandbox-container/build/rootfs.tar
	cp sandbox-container/config.base.json sandbox-container/build/config.base.json

	# Extract the rootfs image for local testing
	mkdir -p sandbox-container/build/rootfs
	sudo tar -xf sandbox-container/build/rootfs.tar -C sandbox-container/build/rootfs

	# Patch DNS
	sudo /bin/bash -c "echo 'nameserver 1.1.1.1' > sandbox-container/build/rootfs/etc/resolv.conf"

#
# Enclave (the normal one with the sandox)
#

clean-enclave-container-dist:
	sudo rm -rf enclave-container/dist/*

build-enclave-container-dist: clean-enclave-container-dist build-rust-enclave-client build-sandbox
	# Collect SSH keys
	mkdir -p enclave-container/dist
	cat ~/.ssh/id_ed25519.pub > enclave-container/dist/authorized_keys

	# Copy over scripts and third party tools
	cp -v enclave-container/content/* enclave-container/dist/
	cp target/debug/enclave-client enclave-container/dist/
	cp third-party/ip-to-vsock-transparent enclave-container/dist/
	cp third-party/dnsproxy enclave-container/dist/

	mkdir -p enclave-container/dist/github-runner/output
	
	# Copy over everything for the inner sandbox (note: this matches the relative path in the repo)
	mkdir -p enclave-container/dist/sandbox-container/build/
	mv sandbox-container/build/rootfs.tar enclave-container/dist/sandbox-container/build/
	sudo zstd -6 -T0 enclave-container/dist/sandbox-container/build/rootfs.tar
	sudo rm -f enclave-container/dist/sandbox-container/build/rootfs.tar
	cp sandbox-container/build/config.base.json enclave-container/dist/sandbox-container/build/config.base.json

build-enclave-container: build-enclave-container-dist
	sudo docker build -t enclave enclave-container/

build-enclave-eif: build-enclave-container
	sudo nitro-cli build-enclave --docker-uri enclave:latest --output-file enclave.eif
	du -h enclave.eif

clean-enclave-eif:
	rm -f enclave.eif

listen-enclave:
	sudo nitro-cli console --enclave-name enclave

#
# Enclave wet (the one without the sandbox)
#

clean-enclave-wet-container-dist:
	sudo rm -rf enclave-wet-container/dist/*

build-enclave-wet-container-dist: clean-enclave-wet-container-dist build-rust-enclave-client
	# Collect SSH keys
	mkdir -p enclave-wet-container/dist
	cat ~/.ssh/id_ed25519.pub > enclave-wet-container/dist/authorized_keys

	# Copy over scripts and third party tools
	cp -v enclave-wet-container/content/* enclave-wet-container/dist/
	cp target/debug/enclave-client enclave-wet-container/dist/
	cp third-party/ip-to-vsock-transparent enclave-wet-container/dist/
	cp third-party/dnsproxy enclave-wet-container/dist/

	# Copy over everything related to the GitHub action runner
	mkdir -p enclave-wet-container/dist/github-runner/hooks
	cp github-runner/hooks/attestation.sh enclave-wet-container/dist/github-runner/hooks/
	cp github-runner/hooks/log.sh enclave-wet-container/dist/github-runner/hooks/
	cp github-runner/hooks/pre_hook.sh enclave-wet-container/dist/github-runner/hooks/
	cp -r github-runner/simulated enclave-wet-container/dist/github-runner/
	mkdir -p enclave-wet-container/dist/github-runner/output

build-enclave-wet-container: build-enclave-wet-container-dist
	sudo docker build -t enclave-wet enclave-wet-container/

build-enclave-wet-eif: build-enclave-wet-container
	sudo nitro-cli build-enclave --docker-uri enclave-wet:latest --output-file enclave-wet.eif
	du -h enclave-wet.eif

clean-enclave-wet-eif:
	rm -f enclave-wet.eif

listen-enclave-wet:
	sudo nitro-cli console --enclave-name enclave-wet

#
# Setup helper
#

setup-aws: setup-kmods
	# Reference: sudo yum list installed | awk '{print $1}' | sed 1d | tr '\n' ' ' > scripts/setup-aws-install-packages.list
	sudo ./scripts/setup-aws-install-packages.sh
	sudo ./scripts/setup-aws-net-ns.sh
	sudo ./scripts/setup-aws-nitro-yaml.sh
#	sudo systemctl restart nitro-enclaves-allocator.service
	sudo /sbin/modprobe vsock_loopback
	sudo chmod o+x /home/ec2-user
	sudo ./scripts/setup-runner-rust.sh

setup-kmods:
	# sudo /sbin/modprobe vhost_vsock
	sudo /sbin/modprobe vsock_loopback

setup-add-user-runner:
	sudo useradd -m runner --uid 1001

#
# Development
#

build-third-party:
	./third-party/build_vsock_proxy.sh
	./third-party/build_dns_proxy.sh
	rm -rf third-party/build/

#
# Run
#

# Run local is a test mode where the `enclave-client` is run on the host machine and listens via the vsock loopback
# interface. By default, we simulate a webhook event in order to not having to deal with tunneling the webhook.
run-local: setup-kmods build-rust-host-server build-rust-enclave-client
	cargo build -p enclave-client
	cargo build -p host-server
	./target/debug/host-server local --simulate-webhook-event --simulate-client-use-fake-attestation

run-nitro-sandbox: build-rust-host-server
	echo "WARNING: do not forget to rebuild the .eif image 'make build-enclave-eif' if required!"
	sleep 1
	./target/debug/host-server nitro --runner-start-mode=sandbox --simulate-log-publishing


ssh-into-fresh-enclave:
	sudo nitro-cli run-enclave --eif-path enclave.eif --cpu-count 2 --enclave-cid 42 --memory 12000 --debug-mode
	sleep 10
	ssh -o 'ProxyCommand socat - VSOCK-CONNECT:42:22' root@enclave
	sudo nitro-cli terminate-enclave --all


#
# Evaluation
#

build-eval:
	cd evaluation && ./scripts/setup-env.sh

clean-eval:
	cd evaluation && rm -r env || true

eval-smoketest:
	sudo rm -rf github-runner/2.328.0/_work
	cd evaluation && source env/bin/activate && time python main.py scenario_smoke_test

eval-smoketest-big:
	sudo rm -rf github-runner/2.328.0/_work
	cd evaluation && source env/bin/activate && time python main.py scenario_smoke_test_big

eval-smoketest-new:
	sudo rm -rf github-runner/2.328.0/_work
	cd evaluation && source env/bin/activate && time python main.py scenario_smoke_test_new

eval-full:
	sudo rm -rf github-runner/2.328.0/_work
	cd evaluation && source env/bin/activate && time python main.py scenario_full

eval-full-one-round:
	sudo rm -rf github-runner/2.328.0/_work
	cd evaluation && source env/bin/activate && time python main.py scenario_full_one_round

eval-full-big:
	sudo rm -rf github-runner/2.328.0/_work
	cd evaluation && source env/bin/activate && time python main.py scenario_full_big

eval-full-big-one-round:
	sudo rm -rf github-runner/2.328.0/_work
	cd evaluation && source env/bin/activate && time python main.py scenario_full_big_one_round

eval-full-new:
	sudo rm -rf github-runner/2.328.0/_work
	cd evaluation && source env/bin/activate && time python main.py scenario_full_new


#
# Test helpers
#

test-local-direct: build-rust-enclave-client build-rust-host-server
	# All simulated, using the fake runner as a process
	sudo ./target/debug/host-server local --runner-start-mode=direct --simulate-webhook-event --simulate-client-use-fake-runner=project_tinycc@project_tinycc --simulate-client-use-fake-attestation --simulate-log-publishing

test-local-direct-real: build-rust-enclave-client build-rust-host-server
	# Most real, but simulating the webhook event to avoid tunneling
	sudo ./target/debug/host-server local --runner-start-mode=direct --simulate-webhook-event --simulate-client-use-fake-attestation --simulate-log-publishing

test-local-sandbox: build-rust-enclave-client build-rust-host-server build-sandbox
	# All simulated, running the fake runner in a sandbox
	sudo ./target/debug/host-server local --runner-start-mode=sandbox --simulate-webhook-event --simulate-client-use-fake-runner=project_tinycc@project_tinycc --simulate-client-use-fake-attestation --simulate-log-publishing

test-local-sandbox-real: build-rust-enclave-client build-rust-host-server build-sandbox
	# Most real, but simulating the webhook event to avoid tunneling
	sudo ./target/debug/host-server local --runner-start-mode=sandbox --simulate-webhook-event --simulate-client-use-fake-attestation --simulate-log-publishing

test-nitro-direct: build-rust-enclave-client build-rust-host-server
	# All simulated, using the fake runner as a process
	sudo ./target/debug/host-server nitro --runner-start-mode=direct --simulate-webhook-event --simulate-client-use-fake-runner=project_tinycc@project_tinycc --simulate-client-use-fake-attestation --simulate-log-publishing

test-nitro-direct-real: build-rust-enclave-client build-rust-host-server
	# All simulated, using the fake runner as a process
	sudo ./target/debug/host-server nitro --runner-start-mode=direct --simulate-webhook-event --simulate-client-use-fake-attestation --simulate-log-publishing

test-nitro-sandbox: build-rust-enclave-client build-rust-host-server
	# All simulated, using the fake runner as a process
	sudo ./target/debug/host-server nitro --runner-start-mode=sandbox --simulate-webhook-event --simulate-client-use-fake-runner=project_tinycc@project_tinycc --simulate-client-use-fake-attestation --simulate-log-publishing

test-nitro-sandbox-real: build-rust-enclave-client build-rust-host-server
	# Most real, but simulating the webhook event to avoid tunneling
	sudo ./target/debug/host-server nitro --runner-start-mode=sandbox --simulate-webhook-event --simulate-log-publishing

test-nitro-sandbox-plus: build-rust-enclave-client build-rust-host-server
	# All simulated, using the fake runner as a process
	sudo ./target/debug/host-server nitro --runner-start-mode=sandbox_plus --simulate-webhook-event --simulate-client-use-fake-runner=project_tinycc@project_tinycc --simulate-log-publishing

test-nitro-sandbox-plus-real: build-rust-enclave-client build-rust-host-server
	# All simulated, using the fake runner as a process
	sudo ./target/debug/host-server nitro --runner-start-mode=sandbox_plus --simulate-webhook-event --simulate-log-publishing

#
# Master commands
#

build-all: build-rust-host-server build-enclave-eif build-enclave-wet-eif build-eval

check: clippy-fmt
	cargo test
	cd evaluation && source env/bin/activate && ./scripts/checks.sh

clean: clean-rust clean-sandbox clean-enclave-container-dist clean-enclave-eif clean-enclave-wet-container-dist clean-enclave-wet-eif clean-eval
	docker system prune -a -f
