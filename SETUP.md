# Setup on a new machine

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
