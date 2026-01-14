-- =============================================================================
-- POSTGRESQL EXTENSIONS
-- =============================================================================
-- This script runs first to enable required PostgreSQL extensions
-- =============================================================================

-- Enable UUID generation (v4 UUIDs)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Enable trigram matching for fuzzy text search
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Verify extensions are installed
DO $$
BEGIN
    RAISE NOTICE 'Extensions installed successfully';
    RAISE NOTICE '  - uuid-ossp: UUID generation';
    RAISE NOTICE '  - pg_trgm: Fuzzy text matching';
END
$$;
