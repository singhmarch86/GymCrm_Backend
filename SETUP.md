# Setup on a new machine

macOS/Linux: `./setup.sh`. Windows: see the Windows section below.

Prerequisites: git (with an SSH key on GitHub), Docker (Docker Desktop or OrbStack),
Flutter SDK, Chrome.

```bash
git clone git@github.com:singhmarch86/GymCrm_Backend.git
cd GymCrm_Backend
./setup.sh
cd app && flutter run -d chrome
```

Login: `9876543210` / `secure123`. API on http://localhost:8089 (`/swagger/` for docs).

- Use Chrome. The macOS desktop build crashes (Flutter framework bug) — don't debug it.
- Demo data is seeded on first boot only; it is not copied from another machine.
- Stop/resume: `cd backend && docker compose stop` / `start`. **Never `down -v`.**
- After `git pull` with new migrations, apply them by hand:
  `docker compose exec -T postgres psql -U gymcrm -d gymcrm -v ON_ERROR_STOP=1 < migrations/0NN_name.sql`,
  then `docker compose up -d --build app`.
- Physical phone on the same Wi-Fi: `flutter run --dart-define=API_BASE_URL=http://<laptop-ip>:8089`.

## Windows

Fresh laptop — nothing needs to be installed by hand except Claude Code itself:

```powershell
# 1. In an ADMINISTRATOR PowerShell. Installs Git, Go, Chrome, Docker Desktop, Flutter 3.44.8, Developer Mode.
#    (If you don't have the repo yet: winget install -e --id Git.Git, open a new terminal, then clone.)
git clone git@github.com:singhmarch86/GymCrm_Backend.git C:\dev\GymCrm
cd C:\dev\GymCrm
powershell -ExecutionPolicy Bypass -File .\install-prereqs.ps1

# 2. Restart Windows if Docker Desktop was just installed. Start Docker Desktop, wait until it is running.
# 3. In a NEW normal PowerShell:
cd C:\dev\GymCrm
powershell -ExecutionPolicy Bypass -File .\setup.ps1
cd app; flutter run -d chrome
```

Cloning needs an SSH key on GitHub (`ssh-keygen -t ed25519`, add `~\.ssh\id_ed25519.pub` at
github.com/settings/keys). Without one, use HTTPS: `git clone https://github.com/singhmarch86/GymCrm_Backend.git`
(it will prompt you to sign in).

- Keep the repo in a plain folder on `C:` (not OneDrive/Desktop) so Docker file sharing works.
- Run `docker compose` from `backend\`. Stop/resume: `docker compose stop` / `start`. Never `down -v`.
- If a Docker build fails on a download error, just re-run `setup.ps1`.
- Not tested on a real Windows machine yet — if a step fails, give the error to Claude and fix the script.
