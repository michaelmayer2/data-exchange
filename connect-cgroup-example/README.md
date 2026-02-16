# Cgroupv2 Control of Posit Connect Local Applications

This repository contains a working example of how to place **Posit Connect** under a custom **systemd slice** and manage **job-level CPU and memory limits** using **cgroup v2**.

The components include:

| File | Purpose |
|------|---------|
| `override.conf` | systemd drop-in override enabling slice delegation + ExecStartPost hook |
| `rstudioconnect.slice` | custom cgroup slice with global CPU/memory limits |
| `cgroup.sh` | ExecStartPost script creating delegated subtrees and setting global memory for Connect jobs |
| `supervisor.sh` | wrapper for Connect content processes; creates job-specific cgroups and applies per-job resource limits |
| `stress-test-app.R` | Shiny application for testing cgroup limits by simulating CPU-intensive workloads |

---

## 1. systemd Drop-In Override
**File:** `override.conf`

This override places the Connect service inside `rstudioconnect.slice`, delegates controllers, and runs `cgroup.sh` after startup.

```conf
[Service]
# The ExecStartPost script modifies the permissions of cgroup subgroups under the custom slice
ExecStartPost=/usr/local/bin/cgroup.sh
Slice=rstudioconnect.slice
Delegate=yes
DelegateSubgroup=connect
```

---

## 2. Custom cgroup Slice
**File:** `rstudioconnect.slice`

Defines CPU and memory limits for the **entire Connect service**, before per-job limits are applied.

```conf
[Unit]
Description=Slice for RStudio Connect service processes

[Slice]
# Example limits for the whole Connect process and all it's spawned Content Applications/Jobs (adjust to your needs)
CPUQuota=200%
MemoryMax=8G

[Install]
WantedBy=multi-user.target
```

---

## 3. ExecStartPost cgroup Setup Script
**File:** `cgroup.sh`

This script:

- Creates the transient Connect cgroup directory
- Creates a persistent `jobs/` subtree for Connect applications
- Delegates `cpu` and `memory` controllers
- Ensures permissions allow Connect to manage its own subgroups
- Applies a **global memory cap** for *all* Connect jobs

```bash
#! /bin/bash
# Get the slice of the rstudio-connect service, currently configured to rstudioconnect.slice
CG=/sys/fs/cgroup$(systemctl show rstudio-connect.service -p ControlGroup --value)

# Create the jobs folder for all of the applications to run in, so that we can set separate limits. This must be done each time, because the rstudio-connect.service cgroup under the slice is transient and is deleted/recreated after each restart of the service.
mkdir $CG/jobs

# Make sure that both memory and cpu are being delegated down the subtree via the top-level rstudio-connect.service and then to individual jobs below jobs
echo "+memory" |  tee $CG/cgroup.subtree_control
echo "+memory" |  tee $CG/jobs/cgroup.subtree_control
echo "+cpu"    |  tee $CG/cgroup.subtree_control
echo "+cpu"    |  tee $CG/jobs/cgroup.subtree_control

echo $((4096 * 1024 * 1024)) > $CG/jobs/memory.max # Optionally set maximum memory or other control groups for all content processes together. Limits for specific pieces of content can be set later.

# Correctly chown the necessary files so that rstudio-connect user can modify limits/jobs.
chown rstudio-connect:rstudio-connect $CG/cgroup.procs
chown -R rstudio-connect:rstudio-connect $CG/jobs
```

---

## 4. Job Supervisor Script
**File:** `supervisor.sh`

This wrapper script:

- Allows Connect's supervisor validation calls to bypass cgroup logic
- Creates a job-specific cgroup under `jobs/job-<PID>`
- Applies **per-job** CPU and memory limits
- Moves the job process into this isolated cgroup
- Executes the actual application after assigning limits

```bash
#!/bin/bash
set -euox pipefail

CMD="$1"
FULL_CMD="$*"

# Supervisor script validation is run as root, and can conflict with the subgroup assignment, so we escape those 2 cases

# ---------------------------------------------------------
# CASE 1: Connect shell validation: /usr/bin/true
# ---------------------------------------------------------
#
if [[ "$CMD" == "/usr/bin/true" ]]; then
    exec "$@"
fi


# ---------------------------------------------------------
# CASE 2: Connect R validation command:
#   /opt/R/<ver>/bin/R --vanilla -s -e 'cat(R.version$major,R.version$minor, sep = ".")'
#
# Match must include:
#   • R binary at /opt/R/<ver>/bin/R
#   • any valid R version directory
#   • the exact cat(R.version$major,R.version$minor, sep = ".") probe
#   • arbitrary quoting around the expression
# ---------------------------------------------------------

# Strict full-command regex:
if [[ "$FULL_CMD" =~ ^/opt/R/[0-9]+(\.[0-9]+)*?/bin/R[[:space:]]+--vanilla[[:space:]]+-s[[:space:]]+-e[[:space:]]+\'?cat\(R\.version\$major,R\.version\$minor,[[:space:]]*sep[[:space:]]*=[[:space:]]*\"\.\"\)\'?$ ]]; then
    exec "$@"
fi


# ---------------------------------------------------------
# REAL JOB EXECUTION AFTER THIS POINT
# ---------------------------------------------------------


# Create a process specific subgroup
mkdir -p /sys/fs/cgroup/rstudioconnect.slice/rstudio-connect.service/jobs/job-$$

# Set this subgroups maximum memory to 50MB, this is where you configure limits for every piece of content
# You can sub-divide this into content specific limits based on content guids
echo $((2048 * 1024 * 1024)) > /sys/fs/cgroup/rstudioconnect.slice/rstudio-connect.service/jobs/job-$$/memory.max

# Limit the subgroup to half a cpu, 50000/100000
echo "50000 100000" > /sys/fs/cgroup/rstudioconnect.slice/rstudio-connect.service/jobs/job-$$/cpu.max

# Put the current PID into this subgroup
echo $$ >> /sys/fs/cgroup/rstudioconnect.slice/rstudio-connect.service/jobs/job-$$/cgroup.procs

# Run the content "normally"
exec "$@"
```

---

## 5. Stress Test Application
**File:** `stress-test-app.R`

This Shiny application allows you to test the cgroup limits by creating CPU-intensive workloads:

- Creates multiple worker processes to stress the CPU
- Configurable stress test duration
- Monitors worker process status and logs
- Useful for verifying CPU limits are properly enforced

```R
# First few lines of stress-test-app.R
library(shiny)
library(parallelly)
library(future)
library(promises)

# Use separate R processes for true parallel CPU burning
plan(multisession, workers = 3)
```

---

## How It Works — High-Level Overview

### 1. Posit Connect runs inside an isolated slice
`rstudio-connect.service` is placed into `rstudioconnect.slice`, and systemd delegates `cpu` and `memory` controllers so subordinate cgroups can be created.

### 2. On startup, the slice is initialized
`cgroup.sh` prepares the persistent `jobs/` subtree, performs delegation setup, and sets global Connect-wide memory limits.

### 3. Each Connect session/app/job gets its own cgroup
`supervisor.sh` is invoked by Connect for each content process. It:

- Identifies the job using `${SYSTEMD_EXEC_PID}`
- Creates a job group:
  `/sys/fs/cgroup/rstudioconnect.slice/rstudio-connect.service/jobs/job-<PID>/`
- Applies CPU/memory limits
- Moves the current job process into that group

### 4. Job limits stack with slice-wide limits

| Layer | Applies To | Example Limit |
|-------|------------|----------------|
| `rstudioconnect.slice` | Entire Connect service | 8 GB, 200% CPU |
| `/jobs` subtree | All jobs collectively | 4 GB |
| `/jobs/job-N` | Individual job | 2 GB, 0.5 CPU |

---

## Example Directory Structure

```
.
├── override.conf
├── rstudioconnect.slice
├── cgroup.sh
├── supervisor.sh
└── stress-test-app.R
```

---
