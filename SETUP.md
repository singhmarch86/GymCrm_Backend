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

Install: **Git for Windows**, **Docker Desktop** (WSL2 backend; keep it running), the **Flutter SDK**
(on PATH), **Chrome**, and add an SSH key to GitHub (`ssh-keygen`, then add `~/.ssh/id_ed25519.pub`).

```powershell
git clone git@github.com:singhmarch86/GymCrm_Backend.git
cd GymCrm_Backend
powershell -ExecutionPolicy Bypass -File .\setup.ps1
cd app; flutter run -d chrome
```

- Clone to a normal folder on `C:` (e.g. `C:\dev`), not OneDrive/Desktop, so Docker file sharing works.
- Run `docker compose` from `backend\`. Stop/resume: `docker compose stop` / `start`. Never `down -v`.
- If a Docker build fails on a download error, just re-run the script.
- Not tested on Windows yet — if a step fails, give the error to Claude and fix it in `setup.ps1`.
