# Running MOKA CRM on GCP, and moving it to a new account

The VM is disposable; the data is not. Everything that matters lives in two
places on **your laptop**, in `~/.moka/` (override with `MOKA_HOME`):

| File | What it is |
|---|---|
| `env` | DB password, JWT secret, sign-up invite code (copied to the VM on every deploy) |
| `backups/gymcrm-*.sql.gz` | verified database dumps (member names, phones, payments — treat as private) |

Back `~/.moka/` up somewhere that is not this laptop and not GCP.

## First time

```bash
gcloud auth login
gcloud config set project <project-id>
./provision.sh      # firewall + e2-small VM + Docker (with a log-size cap)
./deploy.sh         # builds the web app, uploads, starts it, installs the nightly backup
```

`deploy.sh` prints the URL and the API check (`401` is the healthy answer).
Sign-up is closed; the invite code is the `REGISTRATION_INVITE_CODE` line in
`~/.moka/env`.

## Every update

`./deploy.sh` again. The database volume and backups on the VM are untouched.

## Moving to a new GCP account (do this about a week before the trial ends)

1. **Take a backup now:** `./pull-backup.sh` (old project still selected). Copy
   `~/.moka/` somewhere safe.
2. **Switch account:** `gcloud auth login` (new account), then
   `gcloud config set project <new-project-id>`.
3. **Build the new VM:** `./provision.sh` then `./deploy.sh`. Same `~/.moka/env`,
   so the same JWT secret and invite code carry over.
4. **Load the data:** `./restore.sh` (newest dump, asks you to type YES).
5. **Check it:** open the new URL, log in with an existing account, look at
   Members and Payments.
6. **Cut over:** tell users the new address (see below), then pull one last
   backup from the old VM if anyone used it in the meantime, and
   `./restore.sh` it again before you stop using the old one.
7. Only after that, let the old project lapse.

### The address changes

The VM's public IP is different in every project. With a bare IP, every user
has to learn a new URL each time. Buy one cheap domain and point an `A` record
at the current VM; moving then means changing one DNS record, and nobody
notices. The web app uses relative URLs, so it needs no rebuild when the host
changes. (Without a domain, at least reserve a static IP per project so it
doesn't change on every VM restart.)

### What does not move

- Photos/uploads, if any are ever stored on the VM disk rather than the DB.
  Today everything is in Postgres, so the dump is complete.
- Anything someone typed after your last backup. Back up on cutover day.

## Backups

- The VM takes a verified dump nightly at 02:00 (`deploy/backup.sh`, keeps 14).
- Those live on the same disk as the database, so they protect against a bad
  deploy, not against the account going away. `./pull-backup.sh` is the one that
  gets data off GCP; run it weekly.
