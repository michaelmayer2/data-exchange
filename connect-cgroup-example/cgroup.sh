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