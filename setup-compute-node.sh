#!/usr/bin/env bash
set -Eeuo pipefail

########################################
# CONFIG VARIABLES (EDIT HERE)
########################################

LOGFILE="/var/log/slurm_compute_setup.log"

# controller hostname (login node)
CONTROLLER_HOST="km01"

# hostname:ip format
NODES=(
"km01:10.87.230.70"
"kc01:10.87.230.71"
"kc02:10.87.230.72"
"kc03:10.87.230.73"
"kc04:10.87.230.74"
"kc05:10.87.230.75"
)

MUNGE_UID=2001
SLURM_UID=2002

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
run dnf install -y munge slurm slurm-slurmd sshpass
}

########################################
# FETCH CONFIG FROM CONTROLLER
########################################
fetch_cluster_config(){

log "Fetching munge.key and slurm.conf from $CONTROLLER_HOST"

TMPDIR="/tmp/slurm_setup"
mkdir -p "$TMPDIR"

sshpass -p "$SSH_PASS" scp -o StrictHostKeyChecking=no \
    $SSH_USER@$CONTROLLER_HOST:$TMPDIR/munge.key "$TMPDIR/"

sshpass -p "$SSH_PASS" scp -o StrictHostKeyChecking=no \
    $SSH_USER@$CONTROLLER_HOST:$TMPDIR/slurm.conf "$TMPDIR/"

########################################
# install munge key
########################################

cp "$TMPDIR/munge.key" /etc/munge/munge.key
chown munge: /etc/munge/munge.key
chmod 400 /etc/munge/munge.key

########################################
# install slurm.conf
########################################

mkdir -p /etc/slurm
cp "$TMPDIR/slurm.conf" /etc/slurm/slurm.conf
chown slurm:slurm /etc/slurm/slurm.conf

}

########################################
# MUNGE SETUP
########################################
setup_munge(){

mkdir -p /run/munge
chown -R munge: /etc/munge /var/log/munge /var/lib/munge /run/munge || true
chmod 0700 /etc/munge /var/log/munge /var/lib/munge /run/munge || true
chmod 711 /run/munge

systemctl enable --now munge
systemctl is-active --quiet munge || fail "munge failed to start"
}

########################################
# START SLURM WORKER
########################################
start_slurmd(){

log "Starting slurmd"

mkdir -p /var/spool/slurmd /var/log/slurm
chown -R slurm:slurm /var/spool/slurmd /var/log/slurm

systemctl enable --now slurmd
sleep 5

systemctl is-active --quiet slurmd || fail "slurmd failed to start"
}

########################################
# VALIDATION
########################################
validate_node(){

log "Validating compute node"

hostname

systemctl status slurmd --no-pager

log "Node ready — verify from controller using: sinfo"
}

########################################
# MAIN
########################################
main(){
log "===== STARTING SLURM COMPUTE NODE SETUP ====="
setup_hosts
disable_firewall
setup_users
setup_repo
install_packages
fetch_cluster_config
setup_munge
start_slurmd
validate_node
log "===== COMPUTE NODE SETUP COMPLETED ====="
}

main
