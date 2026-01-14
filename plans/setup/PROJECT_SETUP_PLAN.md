# Project Setup Plan: Relationship Tracking System

## Document Purpose

This plan outlines the step-by-step process to set up the local development environment for the relationship tracking system. The goal is to get a working PostgreSQL database and n8n workflow automation platform running in Docker, with the ability to import client companies and eventually find connections to prospects.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     Docker Desktop                          │
│  ┌───────────────────┐       ┌───────────────────────────┐  │
│  │                   │       │                           │  │
│  │   PostgreSQL 16   │◄─────►│         n8n               │  │
│  │                   │       │   (workflow automation)   │  │
│  │   Port: 5432      │       │   Port: 5678              │  │
│  │                   │       │                           │  │
│  └───────────────────┘       └───────────────────────────┘  │
│           ▲                              ▲                  │
└───────────┼──────────────────────────────┼──────────────────┘
            │                              │
            ▼                              ▼
    ┌───────────────┐              ┌───────────────┐
    │   DBeaver     │              │   Browser     │
    │   (DB GUI)    │              │ localhost:5678│
    └───────────────┘              └───────────────┘
```

---

## Configuration Decisions

| Setting | Value | Notes |
|---------|-------|-------|
| PostgreSQL Version | 16 | Latest stable, good performance |
| PostgreSQL Password | `reltracker2024` | Local dev only |
| PostgreSQL Port | 5432 | Standard port |
| n8n Port | 5678 | Standard n8n port |
| n8n Timezone | America/New_York | For scheduled workflows |
| Database GUI | DBeaver Community | Free, beginner-friendly |
| Initial Data | ~100 companies (CSV) | Import one at a time initially |

---

## Project Folder Structure

After setup, the project will look like this:

```
top_opp_agent/
├── docker-compose.yml           # Defines PostgreSQL + n8n services
├── .env                         # Environment variables (passwords, config)
├── .env.example                 # Template for .env (safe to commit)
├── .gitignore                   # Excludes .env, data volumes, etc.
│
├── postgres/
│   └── init/                    # Scripts run on first DB startup
│       ├── 01_extensions.sql    # Enable pg_trgm, uuid-ossp
│       ├── 02_schema.sql        # Main schema (from relationship_schema)
│       └── 03_review_queue.sql  # Entity review queue table
│
├── n8n/
│   └── data/                    # Persistent n8n data (auto-created)
│       └── .gitkeep
│
├── data/
│   └── import/                  # Place CSV files here for import
│       └── .gitkeep
│
├── plans/                       # Existing planning documents
│   ├── setup/
│   │   ├── relationship_schema
│   │   ├── connection_queries
│   │   ├── schema_diagram
│   │   ├── initial_prompt
│   │   └── PROJECT_SETUP_PLAN.md  # This document
│   └── import/
│       ├── import_worklow
│       └── import_workflow_diagram
│
└── CLAUDE.md                    # Project context for Claude Code
```

---

## Phase 1: Prerequisites & Docker Setup

### 1.2 Docker Desktop is Already Setup and Running

### 1.2 Create Project Structure

**Steps:**
1. Create the folder structure shown above
2. The `postgres/init/` folder is critical - files here run automatically on first startup
3. Create empty `.gitkeep` files to preserve empty directories in git

### 1.3 Create Environment Configuration

**Steps:**
1. Create `.env.example` as a template (safe to commit to git)
2. Copy `.env.example` to `.env` (never commit this file)
3. The `.env` file will contain:
   - PostgreSQL credentials
   - n8n encryption key (generate a random 32+ character string)
   - Timezone setting
   - Any future API keys

### 1.4 Create Docker Compose Configuration

**What docker-compose.yml defines:**

| Service | Image | Purpose | Volumes | Ports |
|---------|-------|---------|---------|-------|
| postgres | postgres:16-alpine | Database | `postgres-data` (persistent), `./postgres/init` (init scripts) | 5432:5432 |
| n8n | n8nio/n8n | Workflows | `n8n-data` (persistent) | 5678:5678 |

**Key configuration points:**
- Both services on same Docker network so they can communicate
- PostgreSQL uses named volume for data persistence (survives container restart)
- Init scripts mounted read-only into PostgreSQL's `/docker-entrypoint-initdb.d/`
- n8n configured to use PostgreSQL for its internal database (more reliable than SQLite)
- n8n environment variables set timezone and basic auth requirements
- Health checks ensure PostgreSQL is ready before n8n tries to connect

### 1.5 Start Docker Services

**Commands:**
```
docker compose up -d          # Start services in background
docker compose ps             # Verify both services are running
docker compose logs postgres  # Check PostgreSQL logs for errors
docker compose logs n8n       # Check n8n logs for errors
```

**Expected state after this phase:**
- Two containers running: `top_opp_agent-postgres-1` and `top_opp_agent-n8n-1`
- PostgreSQL accepting connections on localhost:5432
- n8n web UI accessible at http://localhost:5678

---

## Phase 2: Database Setup & Verification

### 2.1 DBeaver is already installed.

### 2.2 Connect DBeaver to PostgreSQL

**Connection settings:**
| Field | Value |
|-------|-------|
| Host | localhost |
| Port | 5432 |
| Database | reltracker |
| Username | reltracker |
| Password | reltracker2024 |

**Steps:**
1. Click "New Database Connection" (plug icon)
2. Select PostgreSQL
3. Enter connection details above
4. Click "Test Connection" to verify
5. Click "Finish" to save

### 2.3 Verify Schema Deployment

The init scripts should have run automatically. Verify by checking:

**Tables (8 expected):**
- [ ] companies
- [ ] people
- [ ] pe_firms
- [ ] employment_history
- [ ] pe_ownership_history
- [ ] board_memberships
- [ ] pe_professionals
- [ ] connection_cache
- [ ] entity_review_queue (added for import workflow)

**Views (3 expected):**
- [ ] v_client_current_employees
- [ ] v_client_network
- [ ] v_current_pe_ownership

**Extensions (2 expected):**
- [ ] uuid-ossp (for UUID generation)
- [ ] pg_trgm (for fuzzy text matching)

**Triggers (5 expected):**
- [ ] update_companies_updated_at
- [ ] update_people_updated_at
- [ ] update_pe_firms_updated_at
- [ ] update_employment_updated_at
- [ ] update_pe_ownership_updated_at

### 2.4 Manual Schema Verification Test

Insert a test record to verify everything works:

**Test 1: Insert a client company**
- Insert one row into `companies` table
- Verify `is_active_client` computed column works
- Verify `updated_at` trigger fires on update

**Test 2: Insert a test person**
- Insert one row into `people` table
- Verify `full_name` computed column generates correctly

**Test 3: Link person to company**
- Insert one row into `employment_history`
- Verify `is_current` and `status` computed columns work

**Test 4: Query a view**
- Query `v_client_current_employees`
- Should return the test person at the test company

**Cleanup:**
- Delete test records or keep them for reference

---

## Phase 3: n8n Setup & Configuration

### 3.1 Initial n8n Access

**Steps:**
1. Open browser to http://localhost:5678
2. First-time setup will prompt for:
   - Email address (for account)
   - First name, last name
   - Password (choose something memorable)
3. Complete the setup wizard
4. Skip or complete the optional tutorial

### 3.2 Configure PostgreSQL Credential in n8n

**Steps:**
1. Go to Settings (gear icon) → Credentials
2. Click "Add Credential"
3. Search for "Postgres"
4. Enter connection details:

| Field | Value |
|-------|-------|
| Host | postgres |
| Port | 5432 |
| Database | reltracker |
| User | reltracker |
| Password | reltracker2024 |
| SSL | Disable (local dev) |

**Important:** Host is `postgres` (container name), not `localhost`. Containers communicate via Docker network using service names.

5. Click "Test" to verify connection
6. Save the credential with name "RelTracker PostgreSQL"

### 3.3 n8n Orientation

Before building workflows, familiarize yourself with:

**Key UI Areas:**
- Workflows list (left sidebar)
- Canvas (where you build workflows)
- Node panel (right sidebar when editing)
- Execution history (see past runs)

**Essential Node Types:**
| Node | Purpose |
|------|---------|
| Manual Trigger | Start workflow with a button click |
| Webhook | Start workflow via HTTP request |
| Postgres | Query/insert/update database |
| IF | Conditional branching |
| Set | Transform data between nodes |
| Code | Custom JavaScript logic |
| HTTP Request | Call external APIs |
| Execute Workflow | Call sub-workflows |

**Learning Resources:**
- n8n's built-in templates
- https://docs.n8n.io/
- YouTube: "n8n tutorials"

### 3.4 Test Workflow: Database Connection

Build a simple workflow to verify everything connects:

**Workflow: "Test DB Connection"**
1. Manual Trigger node (start)
2. Postgres node (SELECT COUNT(*) FROM companies)
3. Verify it executes without error

This confirms n8n can talk to PostgreSQL.

---

## Phase 4: First Import Workflow

### 4.1 Goal

Create a workflow that:
1. Accepts company data via webhook
2. Performs basic entity resolution (check if exists)
3. Inserts new company or updates existing
4. Returns confirmation

### 4.2 Webhook Design

**Endpoint:** `POST /webhook/import-client`

**Request body (JSON):**
```json
{
  "name": "Acme Corporation",
  "client_start_date": "2024-01-15",
  "client_end_date": null,
  "industry": "Manufacturing",
  "website": "https://acme.com"
}
```

**Response:**
```json
{
  "status": "created",
  "company_id": "uuid-here",
  "message": "Company 'Acme Corporation' created as CLIENT"
}
```

Or if exists:
```json
{
  "status": "updated",
  "company_id": "uuid-here",
  "message": "Company 'Acme Corporation' updated to CLIENT"
}
```

### 4.3 Workflow Structure

```
┌──────────────┐     ┌─────────────────┐     ┌──────────────┐
│   Webhook    │────►│ Check if exists │────►│   IF node    │
│   Trigger    │     │  (Postgres)     │     │ exists?      │
└──────────────┘     └─────────────────┘     └──────────────┘
                                                    │
                          ┌─────────────────────────┼─────────────────────────┐
                          ▼                                                   ▼
                   ┌──────────────┐                                    ┌──────────────┐
                   │    INSERT    │                                    │    UPDATE    │
                   │   (create)   │                                    │  (existing)  │
                   └──────────────┘                                    └──────────────┘
                          │                                                   │
                          └─────────────────────────┬─────────────────────────┘
                                                    ▼
                                             ┌──────────────┐
                                             │   Respond    │
                                             │  to Webhook  │
                                             └──────────────┘
```

### 4.4 Entity Resolution Logic (Basic)

For Phase 4, keep it simple:

1. **Search by exact name** (case-insensitive)
   - `SELECT * FROM companies WHERE LOWER(name) = LOWER($name)`

2. **If found:** Update to CLIENT status if not already
3. **If not found:** Create new record

Advanced fuzzy matching (pg_trgm) comes in a later phase.

### 4.5 Testing the Workflow

**Option 1: n8n's built-in test**
- Use the "Test workflow" button in n8n
- Provide sample webhook data

**Option 2: Browser/Postman**
- Copy the webhook URL from n8n
- Send POST request with JSON body
- Check response and database

**Test cases:**
1. New company (should create)
2. Same company again (should update/no-op)
3. Company with different casing (should match existing)
4. Missing required field (should error gracefully)

---
## Useful Docker Commands Reference

| Command | Description |
|---------|-------------|
| `docker compose up -d` | Start all services in background |
| `docker compose down` | Stop all services (data preserved) |
| `docker compose down -v` | Stop all services AND delete data volumes |
| `docker compose restart postgres` | Restart just PostgreSQL |
| `docker compose restart n8n` | Restart just n8n |
| `docker compose logs -f postgres` | Follow PostgreSQL logs |
| `docker compose logs -f n8n` | Follow n8n logs |
| `docker compose ps` | List running containers |
| `docker compose exec postgres psql -U reltracker -d reltracker` | Open psql shell |

---

## Troubleshooting Guide

### Docker won't start
- Ensure virtualization enabled in BIOS
- Run `wsl --update` in PowerShell (admin)
- Restart computer

### PostgreSQL container exits immediately
- Check logs: `docker compose logs postgres`
- Common cause: init script SQL syntax error
- Fix script and run: `docker compose down -v && docker compose up -d`

### n8n can't connect to PostgreSQL
- Ensure host is `postgres` not `localhost`
- Check PostgreSQL container is healthy: `docker compose ps`
- Verify credentials match .env file

### Schema didn't auto-create
- Init scripts only run on FIRST startup with empty volume
- To re-run: `docker compose down -v && docker compose up -d`
- Or manually run SQL via DBeaver

### n8n workflow errors
- Check execution history for detailed error
- Verify Postgres credential is saved correctly
- Test simple SELECT query first

### Port already in use
- Another service using 5432 or 5678
- Either stop conflicting service, or
- Change ports in docker-compose.yml

---

## Security Notes (Local Dev)

This setup is for **local development only**. Before any production/cloud deployment:

- [ ] Use strong, unique passwords
- [ ] Enable SSL for PostgreSQL connections
- [ ] Put n8n behind authentication proxy
- [ ] Never expose ports to public internet
- [ ] Store credentials in proper secrets manager
- [ ] Enable PostgreSQL connection logging
- [ ] Regular database backups

---

## Success Criteria

### Phase 1 Complete When:
- [ ] Docker Desktop running
- [ ] `docker compose up -d` starts both containers
- [ ] `docker compose ps` shows both containers healthy

### Phase 2 Complete When:
- [ ] DBeaver connects to PostgreSQL
- [ ] All 8 tables visible in DBeaver
- [ ] Test insert/update works
- [ ] Computed columns functioning

### Phase 3 Complete When:
- [ ] n8n accessible at localhost:5678
- [ ] Account created and logged in
- [ ] PostgreSQL credential saved and tested
- [ ] Test workflow executes database query


## Next Steps After This Plan

1. **Review this plan** - Ask any clarifying questions
2. **Execute Phase 1** - Docker setup and project structure
3. **Execute Phase 2** - Database deployment and verification
4. **Execute Phase 3** - n8n configuration
---

## Document History

| Date | Change |
|------|--------|
| 2024-01-14 | Initial plan created |
