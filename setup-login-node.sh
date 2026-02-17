#!/usr/bin/env bash
set -Eeuo pipefail

########################################
# CONFIG VARIABLES (EDIT HERE)
########################################

LOGFILE="/var/log/slurm_login_setup.log"

# hostname:ip format
NODES=(
"km01:10.87.230.70"
"kc01:10.87.230.71"
"kc02:10.87.230.72"
"kc03:10.87.230.73"
"kc04:10.87.230.74"
"kc05:10.87.230.75"
)

CLUSTER_NAME="kaimrc-hpc-cluster"
PARTITION_NAME="compute"
CPUS=96
REAL_MEMORY=500000

MUNGE_UID=2001
SLURM_UID=2002

DB_USER="slurm"
DB_PASS="slurm@1234"

SSH_USER="root"
SSH_PASS="P@ssw0rd@123"

########################################
# LOGGING + ERROR HANDLING
########################################

log(){ echo "$(date '+%F %T') [INFO] $*" | tee -a "$LOGFILE"; }
fail(){ echo "$(date '+%F %T') [ERROR] $*" | tee -a "$LOGFILE"; exit 1; }
trap 'fail "Failed at line $LINENO: $BASH_COMMAND"' ERR

run(){ log "Running: $*"; "$@"; }

[[ $EUID -eq 0 ]] || fail "Run as root"

########################################
# OS CHECK
########################################
source /etc/os-release
OS="$ID"

########################################
# HOSTNAME
########################################
CTL_HOST=$(hostname)

########################################
# /etc/hosts setup
########################################
setup_hosts(){
log "Updating /etc/hosts"

for entry in "${NODES[@]}"; do
    host=${entry%%:*}
    ip=${entry##*:}
    grep -q "$host" /etc/hosts || echo "$ip $host" >> /etc/hosts
done
}

########################################
# FIREWALL
########################################
disable_firewall(){
log "Disabling firewall"
systemctl stop firewalld || true
systemctl disable firewalld || true
}

########################################
# USERS
########################################
setup_users(){

getent group munge || groupadd -g $MUNGE_UID munge
id munge &>/dev/null || useradd -m -c "MUNGE" -d /var/lib/munge -u $MUNGE_UID -g munge -s /sbin/nologin munge

getent group slurm || groupadd -g $SLURM_UID slurm
id slurm &>/dev/null || useradd -m -c "SLURM" -d /var/lib/slurm -u $SLURM_UID -g slurm -s /bin/bash slurm
}

########################################
# ROCKY REPO
########################################
setup_repo(){
if [[ "$OS" == "rocky" ]]; then
    log "Configuring Rocky repos"
    dnf -y install dnf-plugins-core
    dnf config-manager --set-enabled powertools || true
    dnf install -y epel-release
    dnf makecache
fi
}

########################################
# PACKAGES
########################################
install_packages(){
run dnf install -y munge slurm slurm-slurmctld slurm-slurmd slurm-slurmdbd mariadb-server sshpass
}

########################################
# MUNGE SETUP
########################################
setup_munge(){

mkdir -p /run/munge /run/slurm
chown -R munge: /etc/munge /var/log/munge /var/lib/munge /run/munge || true
chmod 0700 /etc/munge /var/log/munge /var/lib/munge /run/munge || true

[ -f /etc/munge/munge.key ] || /usr/sbin/create-munge-key
chown munge: /etc/munge/munge.key
chmod 711 /run/munge

systemctl enable --now munge
}

########################################
# DATABASE
########################################
setup_db(){

systemctl enable --now mariadb

mysql -u root -e "
CREATE DATABASE IF NOT EXISTS slurm_acct_db;
GRANT ALL ON slurm_acct_db.* TO '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS' WITH GRANT OPTION;
FLUSH PRIVILEGES;"
}

########################################
# GENERATE SLURM.CONF
########################################
generate_slurm_conf(){

CONF="/etc/slurm/slurm.conf"
cp "$CONF" "$CONF.bkp.$(date +%s)" 2>/dev/null || true

cat > $CONF <<EOF
#
# See the slurm.conf man page for more information.
#
#ControlMachine=localhost
#ControlAddr=127.0.0.1
#BackupController=
#BackupAddr=
#
AuthType=auth/munge
#CheckpointType=checkpoint/none
CryptoType=crypto/munge
#DisableRootJobs=NO
#EnforcePartLimits=NO
#Epilog=
#EpilogSlurmctld=
#FirstJobId=1
#MaxJobId=999999
#GresTypes=
#GroupUpdateForce=0
#GroupUpdateTime=600
#JobCheckpointDir=/var/slurm/checkpoint
#JobCredentialPrivateKey=
#JobCredentialPublicCertificate=
#JobFileAppend=0
#JobRequeue=1
#JobSubmitPlugins=
#KillOnBadExit=0
#LaunchType=launch/slurm
#Licenses=foo*4,bar
#MailProg=/bin/true
#MaxJobCount=5000
#MaxStepCount=40000
#MaxTasksPerNode=128
MpiDefault=pmix
#MpiParams=ports=#-#
#PluginDir=
#PlugStackConfig=
#PrivateData=jobs
ProctrackType=proctrack/cgroup
#Prolog=
#PrologFlags=
#PrologSlurmctld=
#PropagatePrioProcess=0
#PropagateResourceLimits=
#PropagateResourceLimitsExcept=
#RebootProgram=
ReturnToService=1
#SallocDefaultCommand=
# SlurmctldPidFile=/var/run/slurm/slurmctld.pid
SlurmctldPort=6817
# SlurmdPidFile=/var/run/slurm/slurmd.pid
SlurmdPort=6818
SlurmdSpoolDir=/var/spool/slurmd
SlurmUser=slurm
#SlurmdUser=root
#SrunEpilog=
#SrunProlog=
StateSaveLocation=/var/spool/slurm/ctld
SwitchType=switch/none
#TaskEpilog=
TaskPlugin=task/none
#TaskPluginParam=
#TaskProlog=
#TopologyPlugin=topology/tree
#TmpFS=/tmp
#TrackWCKey=no
#TreeWidth=
#UnkillableStepProgram=
#UsePAM=0
#
#
# TIMERS
#BatchStartTimeout=10
#CompleteWait=0
#EpilogMsgTime=2000
#GetEnvTimeout=2
#HealthCheckInterval=0
#HealthCheckProgram=
InactiveLimit=0
KillWait=30
#MessageTimeout=10
#ResvOverRun=0
MinJobAge=300
#OverTimeLimit=0
SlurmctldTimeout=120
SlurmdTimeout=300
#UnkillableStepTimeout=60
#VSizeFactor=0
Waittime=0
#
#
# SCHEDULING
#DefMemPerCPU=0
#FastSchedule=1
#MaxMemPerCPU=0
#SchedulerTimeSlice=30
SchedulerType=sched/backfill
SelectType=select/linear
#SelectTypeParameters=
#
#
# JOB PRIORITY
#PriorityFlags=
#PriorityType=priority/basic
#PriorityDecayHalfLife=
#PriorityCalcPeriod=
#PriorityFavorSmall=
#PriorityMaxAge=
#PriorityUsageResetPeriod=
#PriorityWeightAge=
#PriorityWeightFairshare=
#PriorityWeightJobSize=
#PriorityWeightPartition=
#PriorityWeightQOS=
#
#
# LOGGING AND ACCOUNTING
#AccountingStorageEnforce=0
#AccountingStorageHost=
#AccountingStorageLoc=
#AccountingStoragePass=
#AccountingStoragePort=
# AccountingStorageType=accounting_storage/none
AccountingStorageType=accounting_storage/slurmdbd
#AccountingStorageUser=
AccountingStoreJobComment=YES
ClusterName=$CLUSTER_NAME
SlurmctldHost=$CTL_HOST
#DebugFlags=
#JobCompHost=
#JobCompLoc=
#JobCompPass=
#JobCompPort=
JobCompType=jobcomp/none
#JobCompUser=
#JobContainerType=job_container/none
JobAcctGatherFrequency=30
JobAcctGatherType=jobacct_gather/none
# SlurmctldDebug=3
SlurmctldDebug=5
#SlurmctldLogFile=
#SlurmdDebug=3
SlurmdDebug=5
#SlurmdLogFile=
#SlurmSchedLogFile=
#SlurmSchedLogLevel=
#
#
# POWER SAVE SUPPORT FOR IDLE NODES (optional)
#SuspendProgram=
#ResumeProgram=
#SuspendTimeout=
#ResumeTimeout=
#ResumeRate=
#SuspendExcNodes=
#SuspendExcParts=
#SuspendRate=
#SuspendTime=
#
#
# COMPUTE NODES
EOF

echo "NodeName=$CTL_HOST CPUs=$CPUS RealMemory=$REAL_MEMORY State=UNKNOWN" >> $CONF

for entry in "${NODES[@]}"; do
    host=${entry%%:*}
    [[ "$host" == "$CTL_HOST" ]] && continue
    echo "NodeName=$host CPUs=$CPUS RealMemory=$REAL_MEMORY State=UNKNOWN" >> $CONF
done

echo "PartitionName=$PARTITION_NAME Nodes=ALL Default=YES MaxTime=INFINITE State=UP" >> $CONF
}

########################################
# GENERATE SLURMDBD.CONF
########################################
generate_slurmdbd_conf(){

CONF="/etc/slurm/slurmdbd.conf"
cp "$CONF" "$CONF.bkp.$(date +%s)" 2>/dev/null || true

cat > $CONF <<EOF
#
# See the slurmdbd.conf man page for more information.
#
# Archive info
#ArchiveJobs=yes
#ArchiveDir="/tmp"
#ArchiveSteps=yes
#ArchiveScript=
#JobPurge=12
#StepPurge=1
#
# Authentication info
AuthType=auth/munge
#AuthInfo=/var/run/munge/munge.socket.2
#
# slurmdbd info
DebugLevel=4
#DefaultQOS=normal,standby
DbdAddr=$CTL_HOST
DbdHost=$CTL_HOST
#DbdPort=6819
LogFile=/var/log/slurm/slurmdbd.log
#MessageTimeout=300
#PidFile=/var/run/slurm/slurmdbd.pid
#PluginDir=
#PrivateData=accounts,users,usage,jobs
PurgeEventAfter=1month
PurgeJobAfter=1month
PurgeResvAfter=1month
PurgeStepAfter=1month
PurgeSuspendAfter=1month
PurgeTXNAfter=1month
PurgeUsageAfter=1month
SlurmUser=slurm
#TrackWCKey=yes
#
# Database info
StorageType=accounting_storage/mysql
#StorageHost=localhost
#StoragePort=1234
StoragePass=$DB_PASS
StorageUser=$DB_USER
#StorageLoc=slurm_acct_db
EOF

chmod 600 $CONF
chown slurm:slurm $CONF
}

########################################
# START SERVICES
########################################
start_services(){

log "Starting services"

mkdir -p /var/spool/slurm/ctld
mkdir -p /var/spool/slurmd
mkdir -p /var/log/slurm
mkdir -p /run/slurm

chown -R slurm:slurm /var/spool/slurm
chown -R slurm:slurm /var/spool/slurmd
chown -R slurm:slurm /var/log/slurm
chown -R slurm:slurm /run/slurm

chmod 755 /var/spool/slurm
chmod 700 /var/spool/slurm/ctld

systemctl restart munge
systemctl restart mariadb
systemctl restart slurmdbd
sleep 5
systemctl restart slurmctld
systemctl restart slurmd

sleep 5

systemctl is-active --quiet slurmctld || fail "slurmctld failed to start"
systemctl is-active --quiet slurmdbd || fail "slurmdbd failed to start"
}

########################################
# PASSWORDLESS SSH
########################################
setup_ssh(){

log "Setting up passwordless SSH"

USER_HOME=$(eval echo "~$SSH_USER")

mkdir -p "$USER_HOME/.ssh"
chmod 700 "$USER_HOME/.ssh"

if [[ ! -f "$USER_HOME/.ssh/id_rsa" ]]; then
    sudo -u $SSH_USER ssh-keygen -t rsa -N "" -f "$USER_HOME/.ssh/id_rsa"
fi

for entry in "${NODES[@]}"; do
    host=${entry%%:*}
    sshpass -p "$SSH_PASS" ssh-copy-id -o StrictHostKeyChecking=no $SSH_USER@$host || true
done
}

########################################
# VALIDATION
########################################
validate_cluster(){

log "Validating cluster"

if ! sinfo &>/dev/null; then
    fail "SLURM cluster not responding"
fi

sinfo
sinfo -Nl
sacct || true
}

########################################
# COPY CONFIGS
########################################
copy_configs(){
mkdir -p /tmp/slurm_setup
cp /etc/munge/munge.key /tmp/slurm_setup
cp /etc/slurm/slurm.conf /tmp/slurm_setup
}

########################################
# MAIN
########################################
main(){
log "===== STARTING SLURM LOGIN NODE SETUP ====="
setup_hosts
disable_firewall
setup_users
setup_repo
install_packages
setup_munge
setup_db
generate_slurm_conf
generate_slurmdbd_conf
start_services
setup_ssh
validate_cluster
copy_configs
log "===== SETUP COMPLETED SUCCESSFULLY ====="
}

main
