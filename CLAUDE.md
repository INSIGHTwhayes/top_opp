# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **relationship tracking system** for a consulting firm to find connections between their existing client network and prospective clients. The core problem is temporal: people change jobs, companies change PE ownership, and the system must track these changes over time to identify relationship paths.

**Use case**: "A former employee of our current client now works at the prospect company" or "A PE firm that owns one of our clients used to own the prospect."

## Architecture

### Database Design (PostgreSQL)

The schema uses **SCD Type 2 pattern** for temporal tracking with `start_date`, `end_date`, and computed `is_current` columns.

**Core entities**:
- `companies` - Tagged as CLIENT, PROSPECT, or OTHER (unified table, not separate)
- `people` - Shared across all companies
- `pe_firms` - Private equity firms

**Relationship tables** (all with temporal tracking):
- `employment_history` - Links people to companies with dates
- `pe_ownership_history` - Links PE firms to companies with acquisition/exit dates
- `board_memberships` - Board seats
- `pe_professionals` - PE firm employees

**Key design decision**: Single unified schema where entities can connect both client and prospect sides, rather than separate schemas.

### Data Import Workflows (n8n)

Three entry-point workflows with cascade controls:
1. **Client Company Import** - Enriches with LinkedIn, PE ownership, leadership, board
2. **PE Firm Import** - Full vs lightweight variants to prevent infinite loops
3. **Person Import** - Full employment history scrape vs lightweight stub

**Critical concept**: `depth` parameter controls cascade enrichment:
- `depth=0`: Full import
- `depth=1`: Lightweight (no portfolio discovery)
- `depth>=2`: Stub record only

### Entity Resolution

LinkedIn ID is the primary deduplication key for people. Company resolution uses: LinkedIn URL → website domain → exact name → fuzzy match → manual review queue.

## Key Files

**Planning documents**:
- `plans/setup/relationship_schema` - Full PostgreSQL schema with indexes and triggers
- `plans/setup/connection_queries` - 8 connection-finding queries ranked by strength
- `plans/setup/PROJECT_SETUP_PLAN.md` - Detailed setup instructions
- `plans/import/import_worklow` - Detailed n8n workflow specifications
- `plans/setup/schema_diagram` - Mermaid ERD
- `plans/import/import_workflow_diagram` - Mermaid flowchart

**Infrastructure**:
- `docker-compose.yml` - PostgreSQL 16 + n8n services
- `.env` - Environment variables (credentials, not committed)
- `postgres/init/*.sql` - Database initialization scripts (run on first startup)

## Connection Types (by strength)

1. Former client employee now at prospect (strongest)
2. PE client currently owns prospect
3. Current client employee formerly at prospect
4. PE client formerly owned prospect
5. Common PE ownership (same PE owns both)
6. Mutual former employee (weakest)

## External Services Referenced

- **LinkedIn data**:
- **PE ownership**: PitchBook (expensive), Crunchbase, Google News
- **Contact info**: Hunter.io, Apollo.io, ZoomInfo

## Development Environment

### Docker Services

Start services:
```bash
docker compose up -d
```

Stop services (preserves data):
```bash
docker compose down
```

Reset database (deletes all data):
```bash
docker compose down -v && docker compose up -d
```

View logs:
```bash
docker compose logs postgres
docker compose logs n8n
```

### Database Connection

| Setting | Value |
|---------|-------|
| Host (external) | `localhost` |
| Host (from n8n) | `postgres` |
| Port | `5432` |
| Database | `reltracker` |
| Username | `reltracker` |
| Password | `reltracker2024` |

Direct psql access:
```bash
docker compose exec postgres psql -U reltracker -d reltracker
```

### n8n Access

- URL: http://localhost:5678
- First-time setup requires creating an account
- PostgreSQL credential host must be `postgres` (Docker network name), not `localhost`

## Schema Implementation Notes

**`is_active_client` column**: Uses a trigger instead of a generated column because PostgreSQL doesn't allow `CURRENT_DATE` in generated columns (not immutable). The trigger `compute_companies_is_active_client` recalculates on INSERT/UPDATE.

**Computed columns** (generated):
- `companies.is_active_client` - Trigger-based (see above)
- `people.full_name` - Generated from first_name + last_name
- `employment_history.is_current` - Generated from end_date IS NULL
- `employment_history.status` - Generated ('CURRENT' or 'FORMER')
- `pe_ownership_history.is_current_holding` - Generated from exit_date IS NULL
- `pe_ownership_history.status` - Generated ('CURRENT' or 'EXITED')

**Triggers**:
- `update_*_updated_at` - Auto-updates `updated_at` timestamp on all main tables
- `compute_companies_is_active_client` - Computes active client status

**Extensions**:
- `uuid-ossp` - UUID generation for primary keys
- `pg_trgm` - Trigram matching for fuzzy text search
