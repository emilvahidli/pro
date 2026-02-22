# Project setup: files to create and commands to run

## 1. Files to create (or copy)

Create these in the **project root** (the folder that contains `docker-compose.unified.yml`).

| File | Purpose |
|------|--------|
| **`.env`** | Secrets and config (DB password, Telegram, etc.). Not committed to Git. |
| **`.env.example`** | Template for `.env`. Already in repo; copy to `.env` and edit. |

You do **not** need to create `.gitignore` or `.env.example` by hand if you use the repo that includes them.

---

## 2. Commands to set up the project (local or server)

Run from the **project root** (e.g. `~/Desktop/pro` or `/srv/proep`).

### A. Create `.env` from the example

```bash
cp .env.example .env
```

Edit `.env` and set at least:

- `DB_PASSWORD` – strong password for PostgreSQL
- Optionally: `TELEGRAM_TOKEN`, `TELEGRAM_CHAT_ID` for the contact form

```bash
nano .env
# or: code .env
```

### B. Initialize Git in the main project folder (if not already)

Use these only if the **root** of the project (the folder with `docker-compose.unified.yml`) does **not** have Git yet:

```bash
cd /path/to/pro
git init
git branch -M main
git remote add origin git@github.com:emilvahidli/pro.git
```

Add a root `.gitignore` so `.env` and noise are not committed:

```bash
# If .gitignore doesn't exist, create it (see repo for contents)
git add .gitignore .env.example README.md SETUP.md docker-compose*.yml nginx.conf start.sh log.sh db/ scripts/*.md scripts/*.sh scripts/*.sql scripts/*.js
git add admin.proep.az backend core db deploy proep.az scraping scripts
git status
git commit -m "Initial commit: monorepo with subprojects"
git push -u origin main
```

**Note:** The subfolders `admin.proep.az`, `backend`, `core`, `db`, `deploy`, `proep.az`, `scraping`, `scripts` are **separate Git repos**. If you add them in the root repo, Git will record them as “submodule” links (commit pointers). To register them as proper submodules (so `git clone --recursive` gets everything), run this **once** from the project root after `git init`:

```bash
git submodule add git@github.com:emilvahidli/admin.proep.az.git admin.proep.az
git submodule add git@github.com:emilvahidli/backend.git backend
git submodule add git@github.com:emilvahidli/core.git core
git submodule add git@github.com:emilvahidli/db.git db
git submodule add git@github.com:emilvahidli/deploy.git deploy
git submodule add git@github.com:emilvahidli/proep.az.git proep.az
git submodule add git@github.com:emilvahidli/scraping.git scraping
git submodule add git@github.com:emilvahidli/scripts.git scripts
git add .gitmodules admin.proep.az backend core db deploy proep.az scraping scripts
git commit -m "Add submodules"
git push -u origin main
```

Only do the submodule block if the root repo is empty of those folders (e.g. fresh clone). If the root already has those folders as normal directories with their own `.git`, you can keep the current “embedded repo” setup and just run the first `git add` / `commit` / `push` block.

### C. Start the stack (after `.env` is set)

```bash
docker compose -f docker-compose.unified.yml up --build -d
```

---

## 3. One-time server setup (fresh Ubuntu)

See the “Create my server” section in the chat or README: install Docker, create `/srv/proep`, clone, create `.env`, then run the `docker compose` command above.

---

## 4. Summary checklist

- [ ] Copy `.env.example` to `.env` and set `DB_PASSWORD` (and optional Telegram vars).
- [ ] If root has no Git: `git init`, `git remote add origin git@github.com:emilvahidli/pro.git`, add files, commit, push.
- [ ] (Optional) Add the eight subprojects as submodules if you want a single clone with `--recursive`.
- [ ] Run `docker compose -f docker-compose.unified.yml up --build -d` from the project root.
