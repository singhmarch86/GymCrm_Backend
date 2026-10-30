# Sourced by the other scripts in this folder. Settings come from the
# environment so the same scripts work against any GCP project:
#
#   GCP_PROJECT   project id (default: gcloud's current project)
#   GCP_ZONE      default us-central1-a
#   VM_NAME       default moka-crm
#
# Secrets live OUTSIDE the repo, on the laptop, in $MOKA_HOME (default
# ~/.moka): the deploy .env (DB password, JWT secret, invite code) and the
# database backups. They are what carries a gym's data from one GCP account
# to the next, so losing that folder is the one thing that cannot be undone.

GCP_ZONE="${GCP_ZONE:-us-central1-a}"
VM_NAME="${VM_NAME:-moka-crm}"
MOKA_HOME="${MOKA_HOME:-$HOME/.moka}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"   # GymCRM/

GCLOUD_PROJECT_FLAG=()
[ -n "${GCP_PROJECT:-}" ] && GCLOUD_PROJECT_FLAG=(--project "$GCP_PROJECT")

log() { printf '%s  %s\n' "$(date '+%H:%M:%S')" "$*"; }
die() { printf 'FAILED: %s\n' "$*" >&2; exit 1; }

gc()      { gcloud "$@" "${GCLOUD_PROJECT_FLAG[@]}"; }
vm_ssh()  { gcloud compute ssh "$VM_NAME" --zone "$GCP_ZONE" "${GCLOUD_PROJECT_FLAG[@]}" --quiet --command "$1"; }
vm_scp()  { gcloud compute scp "$@" --zone "$GCP_ZONE" "${GCLOUD_PROJECT_FLAG[@]}" --quiet; }
vm_ip()   { gc compute instances describe "$VM_NAME" --zone "$GCP_ZONE" \
              --format='get(networkInterfaces[0].accessConfigs[0].natIP)'; }

command -v gcloud >/dev/null || die "gcloud is not installed"
mkdir -p "$MOKA_HOME/backups"; chmod 700 "$MOKA_HOME" "$MOKA_HOME/backups"
