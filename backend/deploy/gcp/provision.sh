#!/usr/bin/env bash
# Create the VM, firewall rule and Docker in the CURRENT gcloud project.
# Safe to re-run: existing pieces are skipped.
#
#   gcloud auth login            # the NEW account
#   gcloud config set project <new-project-id>
#   ./provision.sh
set -euo pipefail
. "$(dirname "$0")/common.sh"

gc services enable compute.googleapis.com >/dev/null

if ! gc compute firewall-rules describe moka-crm-http >/dev/null 2>&1; then
  log "creating firewall rule moka-crm-http (tcp:80)"
  gc compute firewall-rules create moka-crm-http --allow=tcp:80 --target-tags=moka-crm >/dev/null
fi

if ! gc compute instances describe "$VM_NAME" --zone "$GCP_ZONE" >/dev/null 2>&1; then
  log "creating VM $VM_NAME (e2-small, Debian 12, 20 GB)"
  gc compute instances create "$VM_NAME" --zone "$GCP_ZONE" --machine-type=e2-small \
    --image-family=debian-12 --image-project=debian-cloud \
    --boot-disk-size=20GB --boot-disk-type=pd-balanced --tags=moka-crm >/dev/null
  sleep 25   # sshd needs a moment
fi

log "installing Docker (official apt repo) with a log-size cap"
# The cap matters: unbounded container logs filled the Archecommerce VM's disk
# and took it down once already.
vm_ssh 'set -e
if ! command -v docker >/dev/null; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq ca-certificates curl gnupg >/dev/null
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin >/dev/null
fi
sudo mkdir -p /etc/docker
echo "{\"log-driver\":\"json-file\",\"log-opts\":{\"max-size\":\"10m\",\"max-file\":\"3\"}}" | sudo tee /etc/docker/daemon.json >/dev/null
sudo systemctl restart docker
sudo usermod -aG docker "$USER"'

log "VM ready at http://$(vm_ip)"
