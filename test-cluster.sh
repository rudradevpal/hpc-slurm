#!/usr/bin/env bash
set -Eeuo pipefail

#######################################
# CONFIG
#######################################

SHARED_DIR="/mnt/hpcnfs/slurm_test"
TEST_DIR="/tmp/slurm_cluster_test"
MPI_PROCS=4

log(){ echo "[INFO] $*"; }
fail(){ echo "[ERROR] $*"; exit 1; }

#######################################
# CHECK SLURM
#######################################
check_slurm(){

log "Checking SLURM cluster status"

sinfo || fail "SLURM not responding"

if sinfo | grep -q down; then
    fail "Some nodes are DOWN"
fi

sinfo -Nl
}

#######################################
# CHECK NODE CONNECTIVITY
#######################################
check_nodes(){

log "Checking node connectivity"

NODELIST=$(sinfo -h -o "%N")
HOSTS=$(scontrol show hostnames $NODELIST)

for n in $HOSTS; do
    ping -c1 -W1 "$n" &>/dev/null \
        && log "$n reachable" \
        || fail "$n not reachable"
done
}

#######################################
# CHECK SSH PASSWORDLESS ACCESS
#######################################
check_ssh(){

log "Checking passwordless SSH between nodes"

NODELIST=$(sinfo -h -o "%N")
HOSTS=$(scontrol show hostnames $NODELIST)

for n in $HOSTS; do
    if ssh -o BatchMode=yes -o ConnectTimeout=5 root@$n "echo SSH OK" &>/dev/null; then
        log "SSH to $n working"
    else
        log "WARNING: SSH to $n may require password - MPI might fail"
    fi
done
}

#######################################
# ENSURE MPI ON ALL NODES
#######################################
install_mpi_on_nodes(){

log "Ensuring OpenMPI installed on all nodes"

NODELIST=$(sinfo -h -o "%N")
HOSTS=$(scontrol show hostnames $NODELIST)

for n in $HOSTS; do
    log "Checking OpenMPI on $n"
    ssh root@$n "rpm -q openmpi" &>/dev/null || \
        ssh root@$n "dnf install -y openmpi openmpi-devel"
done
}

#######################################
# PREPARE MPI PROGRAM
#######################################
prepare_mpi(){

log "Preparing MPI test"

mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

cat > hello.c <<EOF
#include <stdio.h>
#include <mpi.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char *argv[])
{
    int rank, size;
    char hostname[256];

    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    gethostname(hostname, 256);

    printf("Hello from rank %d of %d on host %s\n",
           rank, size, hostname);

    MPI_Finalize();
    return 0;
}
EOF

###################################
# Install OpenMPI if missing
###################################
if ! command -v mpicc &>/dev/null; then
    log "Installing OpenMPI"
    dnf install -y openmpi openmpi-devel || fail "OpenMPI install failed"
fi

###################################
# Rocky/RHEL OpenMPI paths
###################################
export PATH=/usr/lib64/openmpi/bin:$PATH
export LD_LIBRARY_PATH=/usr/lib64/openmpi/lib:${LD_LIBRARY_PATH:-}

command -v mpicc >/dev/null || fail "mpicc not found"

mpicc hello.c -o hello || fail "MPI compile failed"
}

#######################################
# RUN MPI JOB THROUGH SLURM
#######################################
run_mpi_test(){

log "Running MPI test via SLURM"

NODE_COUNT=$(sinfo -h -o "%D" | paste -sd+ | bc)
log "Using $NODE_COUNT nodes with $MPI_PROCS total processes"

mkdir -p "$SHARED_DIR"
cp -f "$TEST_DIR/hello" "$SHARED_DIR/hello"

JOBID=$(sbatch <<EOF | awk '{print $4}'
#!/bin/bash
#SBATCH --nodes=2
#SBATCH --ntasks=4
#SBATCH --ntasks-per-node=2
#SBATCH --exclusive
#SBATCH --output=$SHARED_DIR/output.txt

echo "[INFO] Running inside SLURM job"

###################################
# load OpenMPI runtime
###################################
export PATH=/usr/lib64/openmpi/bin:\$PATH
export LD_LIBRARY_PATH=/usr/lib64/openmpi/lib:\$LD_LIBRARY_PATH

###################################
# VM / cloud safe MPI networking
###################################
export OMPI_MCA_btl=self,tcp
export OMPI_MCA_mtl=^ofi

export OMPI_ALLOW_RUN_AS_ROOT=1
export OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1

###################################
# Debug: Show what SLURM allocated
###################################
echo "[DEBUG] SLURM_JOB_NODELIST: \$SLURM_JOB_NODELIST"
echo "[DEBUG] SLURM_NNODES: \$SLURM_NNODES"
echo "[DEBUG] SLURM_NTASKS: \$SLURM_NTASKS"
echo "[DEBUG] SLURM_TASKS_PER_NODE: \$SLURM_TASKS_PER_NODE"

###################################
# Build machinefile with 2 slots per node
###################################
scontrol show hostnames \$SLURM_JOB_NODELIST | awk '{print \$0 " slots=2"}' > $SHARED_DIR/machinefile

echo "[INFO] Machinefile:"
cat $SHARED_DIR/machinefile

###################################
# Test SSH connectivity from job
###################################
echo "[INFO] Testing SSH to nodes:"
for node in \$(scontrol show hostnames \$SLURM_JOB_NODELIST); do
    ssh -o BatchMode=yes -o ConnectTimeout=5 \$node hostname 2>&1 | head -1
done

###################################
# Run MPI using mpirun
###################################
mpirun --allow-run-as-root \
       -np 4 \
       --hostfile $SHARED_DIR/machinefile \
       --mca btl self,tcp \
       --mca mtl ^ofi \
       -x PATH \
       -x LD_LIBRARY_PATH \
       $SHARED_DIR/hello

EOF
)

log "Submitted MPI job $JOBID"

sleep 10
squeue -j "$JOBID" || true

log "MPI output:"
cat $SHARED_DIR/output.txt || true
}

#######################################
# SIMPLE JOB TEST
#######################################
run_slurm_job(){

log "Running basic SLURM job test"

JOBID=$(sbatch <<EOF | awk '{print $4}'
#!/bin/bash
#SBATCH -N1
hostname
sleep 2
EOF
)

log "Submitted job $JOBID"

sleep 5
squeue -j "$JOBID" || true
}

#######################################
# CLEANUP
#######################################
cleanup(){
rm -rf "$TEST_DIR"
}

#######################################
# MAIN
#######################################
main(){

log "===== SLURM CLUSTER TEST START ====="

check_slurm
check_nodes
check_ssh
install_mpi_on_nodes
prepare_mpi
run_mpi_test
run_slurm_job
cleanup

log "===== CLUSTER TEST SUCCESS ====="
}

main
