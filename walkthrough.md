# Artifact Evaluation Walkthrough

This document provides a step-by-step guide to walk you through the artifact evaluation. 
The main objective is to reproduce the evaluation results, presented in our paper. 

The experiments provide time estimates in human-time (interactive, can be interrupted), and machine-time (non-interactive, cannot be interrupted).
The full evaluations run for a long time. So, you might want to schedule them early in your workday or over-night.

See the provided Artifact Appendix for hardware and software requirements.
The diagram below illustrates the overall architecture and data flow.

| <img src="artifact_evaluation_diagram.png"> |
|--| 
|Overview of the evaluation setup with indication of the used programming language for the respective components. The main repository `attestable-builds` is used to provision a large EC2 instance. The `ab-samples` repository is then initialized to contain one branch per target. The evaluation scripts read the respective `scenario.csv` to learn about the intended list of targets and configurations. It then trigger workflows one-by-one inside the `ab-samples` repository and starting `HostManager` with the respective configuration (e.g. HS, ES+, ...) which then starts the `EnclaveClient`. This figure shows an example that is reflective of ES/ES+, i.e. an enclave with an inner sandbox. However, in non-enclave configurations, that are included as a baseline, the `EnclaveClient` might run directly on the host. In all configurations, the enclave client starts a GitHub runner that will checkout the workflow and run the required steps of the build. Since these interact with the GitHub actions normally, they can be observed via the regular web UI. When all workflows have finished, the `pre_process` script converts the gathered log outputs into a `.csv` file. This can then processed with the provided a Jupyter notebook.|

## Prepare the `ab-samples` repository (5min human-time)

The first step is to prepare the Git repository including the sample projects used in our evaluation.
The following list provides a step-by-step overview of the necessary preparation steps:

1. Create a GitHub account where you can host the `ab-samples` repository
2. Fork our [sample repository](https://github.com/lambdapioneer/ab-samples/tree/artifact-eval) to your own GitHub account. Make sure to copy all branches, i.e. remove the checkbox from `Copy the main branch only`
3. (Optional): Verify that your fork has multiple branches (e.g., project_verifier_client_j3, project_tinycc,...). If the project-specific branches are not available, clone the repository and run the `./scripts/recreate_branches.sh` script to create them.   
4. On GitHub, navigate to the [Developer Settings](https://github.com/settings/apps) of your GitHub account.
5. Navigate to `Personal access tokens -> Fine-grained tokens` and click `Generate new token`.
6. Give it a name and select `Only select repositories` and select the new repository (ab-samples).
7. Click on `Add permissions` and select the following permissions:
	- Actions with Read and write.
	- Administration with Read and write.
	- Commit statuses with Read-only.
	- Contents with Read-only.
	- Environments with Read-only.
8. Generate the token and save it. This will be used later to configure the environment variable on the AWS instance.

## Prepare the AWS environment (10min human-time + 5min machine-time)

> [!WARNING]
> Provisioning resources on AWS may incur charges.
> Be aware that you may still be billed for resources that are stopped.
> Make sure to make yourself familiar with the AWS pricing system (e.g., https://aws.amazon.com/de/getting-started/hands-on/control-your-costs-free-tier-budgets/)

The next step is to prepare the AWS environment, including the security group and the EC2 instance. 

### Create the security group 

1. Navigate to EC2 area / Networks & Security / Security Groups
2. Create a new security group with the following settings:
    - Give it a name (e.g., artifact-eval)
    - Add a description (e.g., Allow SSH and GitHub hooks)
    - Add a new Inbound rules (Custom TCP; Port range: 22; Source: "My IP"); note: if you have a dynamic IP then you have to change the security group everytime your ISP updates your IP... 
    - Add another Inbound rule (Custom TCP; Port range: 8000; Source: Anywhere-IPv4)

### Create the Amazon EC2 instance 

This will be the machine where the experiments are executed. To set up the instance follow the steps below:

1. We recommend selecting the region `us-east-1`, available in the upper-right corner after logging in. 
2. Navigate to `EC2 area -> Instances` and click on `Launch instances`
3. Give it a name (e.g., artifact-eval)
4. Select `Amazon Linux 2023 kernel-6.1 AMI` 
5. Select Instance type: `m5a.8xlarge`
6. Create a key pair for SSH access (select RSA or ED25519)
7. Download your private ssh key and store it securely; adapt permissions (e.g., `chmod 600 <path-to-ssh-key>`)
8. Select the previously created security group in the Network settings area
9. Configure 64GiB gp3 Storage
10. Go To Advanced details and enable `Nitro Enclave`
11. Finally, launch the instance

### Prepare the Amazon EC2 instance 

Now the EC2 machine can be prepared for running the experiments.

1. Upload the artifact ZIP file to the server (the public IPv4 address is shown in AWS Portal -> Instances): 

   ```bash
   scp -i <path-to-ssh-key.pem> artifact-evaluation.zip ec2-user@<public-ip-ec2-instance>:/home/ec2-user/artifact-evaluation.zip
   ```

2. Connect to your instance via SSH, unzip the files and switch directory

   ```bash   
   ssh -i <path-to-ssh-key.pem> ec2-user@<public-ip-ec2-instance>
   unzip artifact-evaluation.zip && cd attestable-builds
   ```

3. Install git:

   ```bash
   sudo dnf install git -y
   ```

4. Run the preparation script to install necessary dependencies and configuring the system: 

   ```bash
   ./scripts/artifact-eval-setup.sh <GitHubAccount>/ab-samples/tree/artifact-eval <INSERT TOKEN>
   # e.g. ./scripts/artifact-eval-setup.sh linsm/ab-samples/tree/artifact-eval github_pat....
   ```

   The repository name refers to the fork created in the [Prepare the sample repository](#prepare-the-sample-repository-5-human-minutes).
   This section also contains the creation of the token.

5. Reboot the machine and reconnect once it is back online. 

## Build the components (5min human-time + 25min machine-time)

After rebooting the machine, it is possible to start building the relevant components used for setting up the build environment.

1. Switch again to the cloned GitHub repository and run the setup for the AWS instance:
   ```bash
   cd attestable-builds && make setup-aws
   ```

2. Install GO:

   ```bash
   wget https://go.dev/dl/go1.25.0.linux-amd64.tar.gz
   sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.25.0.linux-amd64.tar.gz
   export PATH=$PATH:/usr/local/go/bin
   ```

3. Build the third-party libraries: 

   ```bash
   make build-third-party
   ```

4. Build the EIF file for the enclave: 
   ```bash
   make build-enclave-eif
   ```

5. Build the EIF file for the enclave without the inner sandbox: 

   ```bash
   make build-enclave-wet-eif
   ```

6. Cleanup, build the evaluation setup and prepare the runner:

    ``` bash
    sudo docker system prune -a -f
    make build-eval
    ./scripts/prepare-action-runner-for-local.sh
    chmod o+rx ~
    ```

## Setup the webhook (5min human-time)

The next step is to create a GitHub webhook on the forked sample repository. 

Navigate to `https://github.com/ORGANIZATION/REPOSITORY/settings/hooks/new` and replace the ORGANIZATION and the REPOSITORY accordingly.
The webhook can be created with the following configuration:

```
Payload URL: `http://<PUBLIC-IP-AWS-INSTANCE>:8000
Content type: `application/json`
SSL verification: Disable
Active: Ticked
```    

## Run the test suites (2h machine-time)

The repository contains two test suites to verify the configuration before running the final evaluation.
The first test suite contains test cases where parts of the infrastructure is simulated (e.g., using a fake GitHub runner or webhook).

To perform the initial verification tests. The test is successful if the following line is printed: 

```bash
INFO host_server::log_publishing_service: [simulated] Received entry :)
```
As soon as this line is printed, the test can be aborted with CTRL+C.

```bash
make test-local-direct 
# CTRL+C when the line above is printed.
make test-nitro-direct 
#CTRL+C when the line above is printed.
make test-nitro-sandbox 
#CTRL+C when the line above is printed.
make test-nitro-sandbox-plus 
#CTRL+C when the line above is printed.
```

Next, it is also possible to execute smoke tests of the final evaluation run:

```bash
make eval-smoketest 
make eval-smoketest-big 
```

## Run the evaluation (18h machine-time)

The evaluation of the sample projects is separated into two scenarios - `eval-full-one-round` and `eval-full-big-one-round`. The following list provides an overview of the scenarios including the associated projects:  

- `eval-full-one-round`: GProlog, Hello, Neovim, Scheme48, Libsodium, TinyCC, Verifier Client, XZ
- `eval-full-big-one-round`: Clang, Linux Kernel and Linux Kernel-LLVM

To perform the first evaluation, run:

```bash
make eval-full-one-round 
```

To perform the second evaluation (big), run:

```bash
make eval-full-big-one-round 
```

## Generate the plots (10min human-time + 5min machine-time)

At this point the evaluation is finished and the respective log outputs of the project builds is stored in the evaluation directory. The next step is to prepare the pre-processing of the log files by adapting the corresponding script. 

First, copy the name of the latest output folder of both scenarios (e.g., `output_2025-08-27_15-37-19`):

```bash
ls -lha evaluation/scenario_full_one_round/
ls -lha evaluation/scenario_full_big_one_round/
```

Open the file `evaluation/preprocess_data.py` in an editor (e.g., `vim`) and adapt the `"folder"` value of all three `INPUTS` entries accordingly:

```python
INPUTS = {
    "big": {
        "scenario": "scenario_full_big_one_round",
        "folder": "<INSERT THE LATEST OUTPUT FOLDER OF THE BIG SCENARIO>",
        "targets": [
            'project_clang',
            'project_kernel',
            'project_kernel_llvm',
        ],
    },
    "full": {
        "scenario": "scenario_full_one_round",
        "folder": "<INSERT THE LATEST OUTPUT FOLDER OF THE FULL SCENARIO>",
        "targets": [
            "project_gprolog",
            "project_hello",
            "project_ipxe",
            "project_neovim",
            "project_scheme48",
            'project_libsodium',
            'project_tinycc',
            'project_verifier_client',
            'project_xz_tar',
        ],
    },
    "scalar": {
        "scenario": "scenario_full_one_round",
        "folder": "<INSERT THE LATEST OUTPUT FOLDER OF THE FULL SCENARIO>",
        "targets": [
            f"{project}_j{i}"
            for project in ['project_verifier_client', 'project_xz_tar']
            for i in range(1, 8 + 1)
        ],
    },
}
```

Enter the python environment:

```bash
source ./env/bin/activate
```

Run the pre-process data script:
```bash
python3 ./preprocess_data.py
```

Run the jupyter notebook:
```bash
jupyter notebook
```

Setup an SSH reverse tunnel to access the results via the browser:

```bash
ssh -NL 8888:localhost:8888 -i <path-to-ssh-key.pem> ec2-user@<public-ip-ec2-instance>
```

Perform the following steps to generate the plots: 

1. Click on the link provided by the jupyter notebook command (e.g., `http://localhost:8888/tree`).
2. Open the `analysis_v2.ipynb`.
3. Open the `Kernel` menu and click on `Restart Kernel and Run All Cells...`.
4. Scroll down and wait until the generation process of the plots is finished.

## Formal Verification (10min human-time + 5min machine-time)

First, you have to make sure that [Tamarin is installed](https://tamarin-prover.com/manual/master/book/002_installation.html).

```bash
cd formal-verification/
tamarin-prover interactive attestablebuilds.spthy
```

Now the theory should be available on http://127.0.0.1:3001.

You can execute the individual proof scripts by clicking the "sorry" link of the specific lemma followed by "autoprove" of the specific proof method. 
