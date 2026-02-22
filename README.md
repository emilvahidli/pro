# proep.az

## Project Structure

```
pro/
 ├── proep.az/            # frontend (React/Vite/TS)
 │    ├── src/
 │    ├── public/
 │    └── vite.config.ts
 │
 ├── admin.proep.az/      # admin panel (React/Vite/TS)
 │    ├── src/
 │    ├── public/
 │    └── vite.config.ts
 │
 ├── scraping/            # backend scraping services
 │    ├── jobs/           # scheduler (cron, bullmq)
 │    ├── parsers/        # parser logic per site
 │    ├── pipelines/      # writing results to DB
 │    ├── logs/           # job_execution_log
 │    ├── shared/         # config, utils, db connections
 │    └── package.json
 │
 ├── docker-compose.yml
 ├── README.md
 └── .env
```

## Getting Started

### Prerequisites

- Node.js 18+
- Docker & Docker Compose

### Development

1. Copy `.env` and configure your environment variables
2. Start all services:

```bash
docker-compose up -d
```

3. Frontend: http://localhost:3000
4. Admin panel: http://localhost:3001
