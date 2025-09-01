import pandas as pd

# We define individual datasets based on their scenario, folder, and targets
INPUTS = {
    "big": {
        "scenario": "scenario_full_big_one_round",
        "folder": "output_2025-08-27_15-37-19",
        "targets": [
            'project_clang',
            'project_kernel',
            'project_kernel_llvm',
        ],
    },
    "full": {
        "scenario": "scenario_full_one_round",
        "folder": "output_2025-08-27_15-37-19",
        "targets": [
            "project_gprolog",
            "project_hello",
#            "project_ipxe",
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
        "folder": "output_2025-08-27_15-37-19",
        "targets": [
            f"{project}_j{i}"
            for project in ['project_verifier_client', 'project_xz_tar']
            for i in range(1, 8 + 1)
        ],
    },
}

RUNNER_START_MODE_TO_LABEL = {
    'local_direct': 'H',
    'local_sandbox': 'HS',
    'enclave_direct': 'E',
    'enclave_sandbox': 'ES',
    'enclave_sandbox_plus': 'ES+',
}

TARGET_TO_LABEL = {
    'project_libsodium': 'LibSodium (1.0.20)',
    'project_tinycc': 'TinyCC (0.9.28)',
    'project_verifier_client': 'Verifier Client',
    'project_xz_tar': 'XZ Utils (5.6.3)',
    'project_clang': 'Clang (18.1.3)',
    'project_kernel': 'Kernel (6.8.0, gcc)',
    'project_kernel_llvm': 'Kernel (6.8.0, clang)',
    "project_gprolog": "GProlog (1.6.0)",
    "project_hello": "Hello (2.10)",
    "project_ipxe": "IPXE (1.21.1)",
    "project_neovim": "NeoVIM (0.11.0)",
    "project_scheme48": "Scheme48 (1.9.3)",
}


def get_target_label(target):
    if "_j" in target:
        cnt = target.split("_j")[1]
        return TARGET_TO_LABEL[target.split("_j")[0]] + f" (j{cnt})"
    else:
        return TARGET_TO_LABEL[target]


def read_folder(name, path, targets):
    print(f"[ ] Reading: {name=} {path=} {len(targets)=}")
    scenario_path = f"{path}/scenario.csv"
    df_scenario = pd.read_csv(scenario_path)

    df_scenario["path"] = path
    df_scenario['target'] = df_scenario['target'].str.split('@').str[0]
    df_scenario = df_scenario[df_scenario['target'].isin(targets)]

    print(f"[+] Found {len(df_scenario)} rows in {scenario_path}")

    df_scenario["input_set"] = pd.Categorical(
        [name, ] * len(df_scenario),
        categories=INPUTS.keys(),
        ordered=True
    )
    df_scenario['target_label'] = df_scenario['target'].map(get_target_label)
    df_scenario['runner_start_mode'] = pd.Categorical(
        df_scenario['runner_start_mode'],
        categories=RUNNER_START_MODE_TO_LABEL.keys(),
        ordered=True
    )
    df_scenario["runner_start_mode_label"] = df_scenario['runner_start_mode'].map(RUNNER_START_MODE_TO_LABEL)
    return df_scenario


df = pd.concat([read_folder(k, f"{v['scenario']}/{v['folder']}", v['targets']) for k, v in INPUTS.items()])


def log_to_columns(log_content):
    # find all lines with TIMESTAMP
    lines = log_content.split('\n')
    lines = [line for line in lines if 'TIMESTAMP' in line]

    # Those lines end in the format "... TIMESTAMP KEY ISODATE"
    key_to_timestamp = {}
    for line in lines:
        parts = line.split()
        key = parts[-2]
        timestamp_str = parts[-1]
        timestamp = pd.to_datetime(timestamp_str)
        key_to_timestamp[key] = timestamp

    # Get the webhook key as a base reference
    webhook_timestamp = key_to_timestamp['WEBHOOK']

    # Calculate the others as offsets in seconds
    key_to_offset = {}
    for key, timestamp in key_to_timestamp.items():
        offset = (timestamp - webhook_timestamp).total_seconds()
        key_to_offset[key] = offset

    # Prepend each with timestamp_ and make them lower case (we are not barbarians)
    key_to_offset = {f"timestamp_{key.lower()}": value for key, value in key_to_offset.items()}

    return key_to_offset


def get_df_duration(df_scenario):
    logs_stdout = {}

    for index, row in df_scenario.iterrows():
        path, run_name = row['path'], row['name']
        log_path = f"{path}/{run_name}.log"
        try:
            with open(log_path, 'r') as f:
                text = f.read()
                logs_stdout[run_name] = text
        except FileNotFoundError:
            print(f"FileNotFound! This is okay for snapshots but not for the full evaluation: {log_path}")

    # Create new DataFrame using concat with a row for each run
    d = pd.DataFrame([log_to_columns(log) for log in logs_stdout.values()], index=list(logs_stdout.keys()))

    # Add a new column named ARTIFACT_READY which is POST_MAKE if it exists, otherwise BUILD_END
    d['timestamp_artifact_ready'] = d['timestamp_post_make']
    d['timestamp_artifact_ready'] = d['timestamp_artifact_ready'].fillna(d['timestamp_build_end'])

    # Compute build duration as the difference between BUILD_START and ARTIFACT_READY
    d['build_duration'] = d['timestamp_artifact_ready'] - d['timestamp_build_start']

    # And its sub durations: configure, make, make check
    d['configure_duration'] = d['timestamp_post_configure'] - d['timestamp_build_start']
    d['make_duration'] = d['timestamp_post_make'] - d['timestamp_post_configure']
    d['make_check_duration'] = d['timestamp_post_make_check'] - d['timestamp_post_make']

    # Compute the e2e duration as the difference between WEBHOOK and ARTIFACT_READY
    d['e2e_duration'] = d['timestamp_artifact_ready'] - d['timestamp_webhook']

    # Compute the checkout duration as the difference between POST_CHECKOUT and PRE_CHECKOUT
    d['checkout_duration'] = d['timestamp_post_checkout'] - d['timestamp_pre_checkout']

    # Compute the memory allocation duration, enclave boot duration, and configure duration
    d['memory_allocation_duration'] = d['timestamp_enclave_started'] - d['timestamp_webhook']
    d['enclave_boot_duration'] = d['timestamp_enclave_connected'] - d['timestamp_enclave_started']
    d['runner_config_duration'] = d['timestamp_config_done'] - d['timestamp_enclave_connected']

    # Compute the runner readiness duration as the sum of the three above
    d['runner_readiness_duration'] = (d['memory_allocation_duration']
                                      + d['enclave_boot_duration']
                                      + d['runner_config_duration'])

    # Call the index 'name'
    d.index.name = 'name'
    return d


# Parse the log files, get the durations, and merge those in
df_durations = get_df_duration(df)
df_merged = pd.merge(df, df_durations, left_on='name', right_index=True)
print(f"[ ] Total dateset has {len(df_merged)} rows")

output_path = "latest.csv"
df_merged.to_csv(output_path, index=False)
print(f"[+] Saved: {output_path}")
