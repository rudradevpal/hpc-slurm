# ✅ **PRIMARY NODE (login-node) — Run in Order**

---

## 🔹 1. Set hostname

```bash
sudo hostnamectl set-hostname login-node
exec bash
```

---

## 🔹 2. Enable repos

```bash
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --set-enabled powertools || sudo dnf config-manager --set-enabled PowerTools
sudo dnf install -y epel-release
sudo dnf makecache
```

---

## 🔹 3. Create users (fixed UID/GID)

```bash
sudo groupadd -g 2001 munge 2>/dev/null || true
sudo useradd -m -d /var/lib/munge -u 2001 -g munge -s /sbin/nologin munge 2>/dev/null || true

sudo groupadd -g 2002 slurm 2>/dev/null || true
sudo useradd -m -d /var/lib/slurm -u 2002 -g slurm -s /bin/bash slurm 2>/dev/null || true
```

---

## 🔹 4. Install packages

```bash
sudo dnf install -y munge slurm slurm-slurmctld slurm-slurmd slurm-slurmdbd \
mariadb-server nfs-utils openmpi openmpi-devel openssh-clients
```

---

## 🔹 5. Disable firewall

```bash
sudo systemctl disable --now firewalld
```

---

## 🔹 6. Create required directories

```bash
sudo mkdir -p /run/munge /run/slurm /var/spool/slurmctld /var/spool/slurmd /var/log/slurm
```

---

## 🔹 7. Fix permissions

```bash
sudo chown -R munge: /etc/munge /var/log/munge /var/lib/munge /run/munge
sudo chmod 700 /etc/munge /var/log/munge /var/lib/munge /run/munge
sudo chmod 711 /run/munge

sudo chown -R slurm: /etc/slurm /var/log/slurm /var/lib/slurm /run/slurm /var/spool/slurmctld /var/spool/slurmd
```

---

## 🔹 8. Create munge key (only if missing)

```bash
[ -f /etc/munge/munge.key ] || sudo /usr/sbin/create-munge-key
sudo chown munge:munge /etc/munge/munge.key
sudo chmod 400 /etc/munge/munge.key
```

---

## 🔹 9. Start munge

```bash
sudo systemctl enable --now munge
```

---

## 🔹 10. Install & start MariaDB

```bash
sudo systemctl enable --now mariadb
```

---

## 🔹 11. Create Slurm database

```bash
sudo mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS slurm_acct_db;
CREATE USER IF NOT EXISTS 'slurm'@'localhost' IDENTIFIED BY 'slurm@1234';
GRANT ALL ON slurm_acct_db.* TO 'slurm'@'localhost';
FLUSH PRIVILEGES;
EOF
```

---

## 🔹 12. Create Slurm config files (paste your configs)

### slurm.conf

```bash
sudo nano /etc/slurm/slurm.conf
```

Paste your config.

---

### slurmdbd.conf

```bash
sudo nano /etc/slurm/slurmdbd.conf
```

Paste your config.

---

## 🔹 13. Fix config permissions

```bash
sudo chown slurm:slurm /etc/slurm/*
sudo chmod 600 /etc/slurm/slurmdbd.conf
```

---

## 🔹 14. Start Slurm services

```bash
sudo systemctl enable --now slurmdbd
sudo systemctl enable --now slurmctld
sudo systemctl enable --now slurmd
```

---

## 🔹 15. Configure MPI globally

```bash
echo "module load mpi/openmpi-x86_64" | sudo tee /etc/profile.d/openmpi.sh
echo "export OMPI_MCA_mtl=^ofi" | sudo tee -a /etc/profile.d/openmpi.sh
echo "export OMPI_MCA_btl=self,tcp" | sudo tee -a /etc/profile.d/openmpi.sh
```

---

## 🔹 16. Setup passwordless SSH (root → all nodes)

```bash
sudo ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
```

Later copy to compute nodes:

```bash
ssh-copy-id root@compute-node-0
ssh-copy-id root@compute-node-1
```

---

## 🔹 17. Optional NFS mount

```bash
sudo dnf install -y nfs-utils
sudo mkdir -p /mnt/hpcnfs
sudo mount <nfs-server>:/hpcnfs /mnt/hpcnfs
```

Persist:

```bash
echo "<nfs-server>:/hpcnfs /mnt/hpcnfs nfs defaults 0 0" | sudo tee -a /etc/fstab
```

---

## 🔹 18. Verify cluster

```bash
scontrol ping
sinfo
systemctl status slurmctld
systemctl status slurmdbd
```
---

# ✅ **COMPUTE NODE — Run in Order**

(Replace hostname accordingly)

---

## 🔹 1. Set hostname

Example for first node:

```bash
sudo hostnamectl set-hostname compute-node-0
exec bash
```

---

## 🔹 2. Enable repos

```bash
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --set-enabled powertools || sudo dnf config-manager --set-enabled PowerTools
sudo dnf install -y epel-release
sudo dnf makecache
```

---

## 🔹 3. Create users (same UID/GID as controller)

```bash
sudo groupadd -g 2001 munge 2>/dev/null || true
sudo useradd -m -d /var/lib/munge -u 2001 -g munge -s /sbin/nologin munge 2>/dev/null || true

sudo groupadd -g 2002 slurm 2>/dev/null || true
sudo useradd -m -d /var/lib/slurm -u 2002 -g slurm -s /bin/bash slurm 2>/dev/null || true
```

---

## 🔹 4. Install packages (compute only)

```bash
sudo dnf install -y munge slurm slurm-slurmd nfs-utils openmpi openmpi-devel openssh-clients
```

---

## 🔹 5. Disable firewall

```bash
sudo systemctl disable --now firewalld
```

---

## 🔹 6. Create required directories

```bash
sudo mkdir -p /run/munge /run/slurm /var/spool/slurmd /var/log/slurm
```

---

## 🔹 7. Fix permissions

```bash
sudo chown -R munge: /etc/munge /var/log/munge /var/lib/munge /run/munge
sudo chmod 700 /etc/munge /var/log/munge /var/lib/munge /run/munge
sudo chmod 711 /run/munge

sudo chown -R slurm: /etc/slurm /var/log/slurm /var/lib/slurm /run/slurm /var/spool/slurmd
```

---

## 🔹 8. Setup passwordless SSH (compute → controller)

Replace `login-node` if different:

```bash
sudo ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
sudo ssh-copy-id root@login-node
```

(Enter password once.)

---

## 🔹 9. Copy munge key from controller

```bash
sudo scp root@login-node:/etc/munge/munge.key /etc/munge/munge.key
sudo chown munge:munge /etc/munge/munge.key
sudo chmod 400 /etc/munge/munge.key
```

---

## 🔹 10. Copy slurm.conf from controller

```bash
sudo scp root@login-node:/etc/slurm/slurm.conf /etc/slurm/slurm.conf
sudo chown slurm:slurm /etc/slurm/slurm.conf
```

---

## 🔹 11. Start munge

```bash
sudo systemctl enable --now munge
```

Verify:

```bash
munge -n | unmunge
```

---

## 🔹 12. Start slurm node daemon

```bash
sudo systemctl enable --now slurmd
```

---

## 🔹 13. Configure MPI globally (all users)

```bash
echo "module load mpi/openmpi-x86_64" | sudo tee /etc/profile.d/openmpi.sh
echo "export OMPI_MCA_mtl=^ofi" | sudo tee -a /etc/profile.d/openmpi.sh
echo "export OMPI_MCA_btl=self,tcp" | sudo tee -a /etc/profile.d/openmpi.sh
```

---

## 🔹 14. Optional NFS mount (if using shared storage)

```bash
sudo mkdir -p /mnt/hpcnfs
sudo mount <nfs-server>:/hpcnfs /mnt/hpcnfs
```

Persist:

```bash
echo "<nfs-server>:/hpcnfs /mnt/hpcnfs nfs defaults 0 0" | sudo tee -a /etc/fstab
```

---

## 🔹 15. Verify node joins cluster

Run on compute node:

```bash
systemctl status slurmd
```

Run on controller:

```bash
sinfo
```

You should see:

```
compute-node-0 idle
```

---
