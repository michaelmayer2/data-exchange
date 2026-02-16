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