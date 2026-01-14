# Schema Revision Plan

## Overview

This document outlines changes to better align the schema with the consulting firm's actual workflows. The core insight is that **most companies entering the system are NOT clients** - they come from PE portfolio imports, employment history lookups, etc. Client status should be explicitly set, not assumed.

---

## Change 1: Decouple Client Status from Relationship Type

### Problem

The current design uses `relationship_type` as an enum ('CLIENT', 'PROSPECT', 'OTHER') that conflates two separate concepts:
1. **Is this company a client of ours?** (binary yes/no)
2. **Are we tracking this as a prospect?** (sales pipeline concept)

When importing a PE firm's portfolio or a person's employment history, we create companies that are neither clients nor prospects - they're just "companies in our database." The current enum forces awkward categorization.

### Current Behavior

```sql
relationship_type VARCHAR(20) NOT NULL DEFAULT 'OTHER'
    CHECK (relationship_type IN ('CLIENT', 'PROSPECT', 'OTHER')),

is_active_client BOOLEAN  -- computed from relationship_type = 'CLIENT' + dates
```

### Proposed Changes

**Replace `relationship_type` with two explicit boolean flags:**

```sql
-- Client tracking (explicit, not assumed)
is_client BOOLEAN NOT NULL DEFAULT FALSE,
client_start_date DATE,
client_end_date DATE,
is_active_client BOOLEAN NOT NULL DEFAULT FALSE,  -- trigger-computed

-- Prospect tracking (separate concern)
is_prospect BOOLEAN NOT NULL DEFAULT FALSE,
prospect_added_date DATE,
prospect_status VARCHAR(50),  -- 'RESEARCHING', 'QUALIFIED', 'PITCHED', 'CLOSED_WON', 'CLOSED_LOST'
```

### Why This is Better

1. **Default import behavior is safe**: When you import a PE portfolio company or a former employer, `is_client` defaults to FALSE. No risk of accidentally counting non-clients as clients.

2. **Explicit client designation**: The "Upload Clients" workflow explicitly sets `is_client = TRUE`. This is a deliberate action, not a default.

3. **Independent tracking**: A company can be:
   - Neither client nor prospect (most companies)
   - A prospect only (you're pursuing them)
   - A client only (established relationship)
   - Both client AND prospect (existing client, pursuing additional work)

4. **Cleaner queries**: `WHERE is_client = TRUE` vs `WHERE relationship_type = 'CLIENT'`

### Trigger Logic for `is_active_client`

The trigger should compute:
```sql
is_active_client := (
    is_client = TRUE
    AND client_start_date IS NOT NULL
    AND (client_end_date IS NULL OR client_end_date > CURRENT_DATE)
);
```

### Migration Consideration

No existing data to migrate - this is a fresh schema. We can simply drop and recreate tables as needed.

---

## Change 2: Track Known Contacts vs Discovered People

### Problem

The `people` table treats everyone the same, but the consulting firm needs to distinguish:
- **Known contacts**: People you already have relationships with (from your CRM, business cards, direct connections)
- **Discovered people**: Found through enrichment (LinkedIn scrapes, PE firm lookups, company leadership imports)

This distinction matters for:
- Prioritizing outreach (warm vs cold)
- Understanding your actual network vs the graph
- Reporting ("we know 5 people at this prospect" vs "we found 50 people in their org chart")

### Proposed Changes

Add to `people` table:

```sql
-- Contact classification
is_known_contact BOOLEAN NOT NULL DEFAULT FALSE,
contact_source VARCHAR(100),  -- 'CRM_IMPORT', 'MANUAL_ENTRY', 'LINKEDIN_SCRAPE', 'PE_RESEARCH', etc.
```

### How It Works in Practice

| Import Type | is_known_contact | contact_source |
|-------------|------------------|----------------|
| CRM import | TRUE | 'CRM_IMPORT' |
| Manual entry of a contact | TRUE | 'MANUAL_ENTRY' |
| LinkedIn scrape of company leadership | FALSE | 'LINKEDIN_SCRAPE' |
| PE firm professional lookup | FALSE | 'PE_RESEARCH' |
| Employment history enrichment | FALSE | 'EMPLOYMENT_ENRICHMENT' |

### Query Examples

```sql
-- Find known contacts at a prospect
SELECT p.* FROM people p
JOIN employment_history eh ON p.id = eh.person_id
JOIN companies c ON eh.company_id = c.id
WHERE c.is_prospect = TRUE
  AND eh.is_current = TRUE
  AND p.is_known_contact = TRUE;

-- Report: Connection paths through known contacts only
-- (warmer leads than discovered people)
```

### Upgrading Discovered to Known

When you actually meet someone who was previously "discovered," you can upgrade them:
```sql
UPDATE people
SET is_known_contact = TRUE,
    contact_source = 'MET_AT_CONFERENCE'  -- or update source
WHERE id = ?;
```

---

## Change 3: Simplify PE Ownership History

### Problem

The current schema tracks `ownership_percentage`, `investment_type`, and `deal_type` which are not needed for this use case.

### Current Columns

```sql
ownership_percentage DECIMAL(5, 2),  -- Remove
investment_type VARCHAR(50),         -- Remove
deal_type VARCHAR(50),               -- Remove
```

### Proposed Changes

**Remove from `pe_ownership_history`:**
- `ownership_percentage`
- `investment_type`
- `deal_type`

**Update `v_current_pe_ownership` view:**
Remove the `ownership_percentage` column from the view definition.

### Rationale

For connection-finding purposes, you only need to know:
1. Which PE firm owned/owns the company (the relationship)
2. When (acquisition_date, exit_date for temporal tracking)

You don't need the financial details (ownership percentage, investment type, deal type).

---

## Updated Schema Summary

### `companies` Table Changes

| Column | Change | Notes |
|--------|--------|-------|
| `relationship_type` | REMOVE | Replaced by explicit flags |
| `is_client` | ADD | `BOOLEAN NOT NULL DEFAULT FALSE` |
| `is_active_client` | MODIFY | Already exists, update trigger logic |
| `is_prospect` | ADD | `BOOLEAN NOT NULL DEFAULT FALSE` |
| `client_start_date` | KEEP | No change |
| `client_end_date` | KEEP | No change |
| `prospect_added_date` | KEEP | No change |
| `prospect_status` | KEEP | No change |

### `people` Table Changes

| Column | Change | Notes |
|--------|--------|-------|
| `is_known_contact` | ADD | `BOOLEAN NOT NULL DEFAULT FALSE` |
| `contact_source` | ADD | `VARCHAR(100)` |

### `pe_ownership_history` Table Changes

| Column | Change | Notes |
|--------|--------|-------|
| `ownership_percentage` | REMOVE | Not needed |
| `investment_type` | REMOVE | Not needed |
| `deal_type` | REMOVE | Not needed |

### Views to Update

- `v_client_current_employees`: Change `relationship_type = 'CLIENT'` to `is_client = TRUE`
- `v_client_network`: Change `relationship_type = 'CLIENT'` to `is_client = TRUE`
- `v_current_pe_ownership`: Remove `ownership_percentage` from SELECT

### Indexes to Update

- `idx_companies_relationship`: Remove (was on `relationship_type`)
- Add `idx_companies_is_client` on `(is_client) WHERE is_client = TRUE`
- Add `idx_companies_is_prospect` on `(is_prospect) WHERE is_prospect = TRUE`
- Add `idx_people_known_contact` on `(is_known_contact) WHERE is_known_contact = TRUE`

---

## Import Workflow Implications

### Client Company Import
```
1. Create/update company record
2. Set is_client = TRUE explicitly
3. Set client_start_date
4. is_active_client computed by trigger
5. Optionally set is_prospect = FALSE (if they were a prospect that converted)
```

### PE Portfolio Import
```
1. Create/update company record
2. is_client defaults to FALSE (no change needed)
3. is_prospect defaults to FALSE
4. Link to pe_ownership_history
```

### Prospect Import
```
1. Create/update company record
2. is_client defaults to FALSE
3. Set is_prospect = TRUE
4. Set prospect_added_date, prospect_status
```

### Person Import (from CRM/Manual)
```
1. Create person record
2. Set is_known_contact = TRUE
3. Set contact_source = 'CRM_IMPORT' or 'MANUAL_ENTRY'
```

### Person Discovery (from LinkedIn/Enrichment)
```
1. Create person record
2. is_known_contact defaults to FALSE
3. Set contact_source = 'LINKEDIN_SCRAPE' (or appropriate)
```

---

## Design Decisions (Finalized)

1. **`is_client` and `is_prospect` are NOT mutually exclusive.**
   A company can be both - e.g., an existing client you're pursuing for additional work.

2. **Single `prospect_status` field is sufficient.**
   No need for prospect history tracking at this time.

3. **`is_known_contact` is always set by the import process, defaulting to FALSE.**
   This should never be automatically inferred. Even if you have someone's email from LinkedIn, you don't "know" them until you've actually connected.

4. **`pe_firms.is_client` remains unchanged.**
   This is separate from `companies.is_client` and tracks whether a PE firm itself is a client.

---

## Implementation Order

Since there is no existing data, we can simply regenerate the schema files:

1. Update `postgres/init/02_schema.sql` with the revised schema
2. Update `plans/setup/relationship_schema` to match
3. Reset the database (`docker compose down -v && docker compose up -d`)
4. Update n8n workflows to use new column names
