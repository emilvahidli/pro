# Disk full recovery (no space left on device)

When you see **ENOSPC** or **no space left on device**, follow these steps.

## Quick: paste this first (frees the most, no Docker needed)

```bash
rm -rf ~/.colima ~/.docker
rm -rf admin.proep.az/dist-server admin.proep.az/dist admin.proep.az/node_modules/.vite
rm -rf scraping/dist
npm cache clean --force
```

Then check: `df -h .` — you want at least **2 GB** free. If not, do step 1 below.

Then: `colima start` and after it’s up: `./start.sh`

---

## 1. Free space without using Docker

Run these one at a time. After each, run `df -h .` to see free space. Stop when you have at least **2–3 GB free**.

```bash
# Project build outputs (safe to delete; will be rebuilt)
rm -rf admin.proep.az/dist-server admin.proep.az/dist admin.proep.az/node_modules/.vite
rm -rf scraping/dist scraping/node_modules/.cache
rm -rf proep.az/dist backend/dist core/dist
```

```bash
# npm cache (safe; packages will re-download when needed)
npm cache clean --force
```

```bash
# Colima/Docker data (frees a lot; you will get a fresh Docker after colima start)
rm -rf ~/.colima
```

```bash
# Docker config/cache in home (if Colima is gone, this clears broken state)
rm -rf ~/.docker
```

```bash
# Common large caches (pick what you have)
rm -rf ~/Library/Caches/Cursor
rm -rf ~/Library/Caches/npm
rm -rf ~/Library/Caches/Homebrew
rm -rf ~/.npm
```

```bash
# Optional: node_modules in this project (only if still stuck; then re-run npm install later)
# rm -rf admin.proep.az/node_modules scraping/node_modules
```

## 2. Start Colima and Docker again

After you have at least **2 GB free**:

```bash
colima start
docker info
```

If `colima start` fails, try:

```bash
colima start --cpu 2 --memory 2 --disk 20
```

## 3. Start the project

```bash
cd /Users/emil.vahidli/Desktop/pro
./start.sh
```

## 4. If you still have no space

- Empty Trash (Finder → Empty Trash).
- Delete large files you don’t need (Downloads, old videos, Xcode derived data, iOS backups).
- Check size: `du -sh ~/*` and `du -sh ~/Library/Caches/*` to find big folders.

## 5. Run without Docker (while fixing disk)

To run the app without Docker:

```bash
./start.sh --no-docker
```

Then follow the printed steps (start Postgres and services manually).
