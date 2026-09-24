# Legacy Docker Desktop pilot

The Docker Desktop Jenkins pilot is superseded by the Hyper-V shadow-pilot runbook. This repository version intentionally contains no commands for starting or enrolling its persistent agent.

The existing Docker Desktop checkout, ignored local configuration, DPAPI-protected material, and named volume are preserved separately on the Windows host. Do not delete them while qualifying Hyper-V. If rollback is needed, stop the VM and its loopback forward, then use the preserved pre-VM checkout and its matching instructions. Never run the Hyper-V branch's Docker-socket controller on Docker Desktop, and never use `docker compose down -v` against either installation.
