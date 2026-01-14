-- =============================================================================
-- ENTITY REVIEW QUEUE
-- =============================================================================
-- For storing entities that need manual review during import workflows
-- (e.g., fuzzy matches that couldn't be auto-resolved)
-- =============================================================================

CREATE TABLE entity_review_queue (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- What type of entity needs review?
    entity_type VARCHAR(50) NOT NULL
        CHECK (entity_type IN ('COMPANY', 'PERSON', 'PE_FIRM')),

    -- Why does it need review?
    review_reason VARCHAR(100) NOT NULL,
    -- e.g., 'FUZZY_MATCH_CANDIDATE', 'DUPLICATE_SUSPECTED', 'DATA_CONFLICT', 'MANUAL_VERIFICATION'

    -- The incoming data that triggered the review
    incoming_data JSONB NOT NULL,

    -- Potential matches found (if any)
    potential_matches JSONB,  -- Array of {id, name, similarity_score, ...}

    -- Context from the import workflow
    import_source VARCHAR(100),  -- e.g., 'CLIENT_IMPORT', 'PE_IMPORT', 'PERSON_IMPORT'
    import_batch_id VARCHAR(100),  -- For tracking related imports

    -- Review status
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'IN_REVIEW', 'RESOLVED', 'SKIPPED')),

    -- Resolution details
    resolution VARCHAR(50),  -- e.g., 'MERGED', 'CREATED_NEW', 'LINKED_TO_EXISTING', 'REJECTED'
    resolved_entity_id UUID,  -- The final entity ID after resolution
    resolved_by VARCHAR(100),  -- Who resolved it
    resolved_at TIMESTAMP WITH TIME ZONE,
    resolution_notes TEXT,

    -- Metadata
    priority VARCHAR(20) DEFAULT 'NORMAL'
        CHECK (priority IN ('HIGH', 'NORMAL', 'LOW')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for review queue queries
CREATE INDEX idx_review_queue_status ON entity_review_queue(status);
CREATE INDEX idx_review_queue_type ON entity_review_queue(entity_type);
CREATE INDEX idx_review_queue_priority ON entity_review_queue(priority, created_at);
CREATE INDEX idx_review_queue_pending ON entity_review_queue(entity_type, status)
    WHERE status = 'PENDING';

-- Trigger for updated_at
CREATE TRIGGER update_review_queue_updated_at BEFORE UPDATE ON entity_review_queue
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =============================================================================
-- COMPLETION NOTICE
-- =============================================================================
DO $$
BEGIN
    RAISE NOTICE 'Entity review queue table created successfully!';
END
$$;
