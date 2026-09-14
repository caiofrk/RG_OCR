-- ==============================================================================
-- DOCUMENT SCANNER & OCR EXTRACTION SUITE: SUPABASE SCHEMA & RLS
-- PostgreSQL 15+ compatible with Zero-Cost Supabase Tier
-- ==============================================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. ENUMS & TYPES
DO $$ BEGIN
    CREATE TYPE document_type AS ENUM ('rg', 'cin', 'cnh', 'passport', 'cpf', 'other');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE verification_status AS ENUM ('auto_verified', 'manual_verified', 'flagged', 'pending');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 3. SCANNED DOCUMENTS TABLE
-- Stores scan history, original document reference, and extracted structured metadata
CREATE TABLE IF NOT EXISTS public.scanned_documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    file_name TEXT NOT NULL,
    file_path TEXT, -- Storage bucket path (client-documents/...)
    file_size_bytes BIGINT,
    mime_type TEXT DEFAULT 'image/jpeg',
    document_type document_type NOT NULL DEFAULT 'rg',
    status verification_status NOT NULL DEFAULT 'auto_verified',
    
    -- Core Extracted Document Fields
    document_number TEXT,
    cpf TEXT,
    cpf_valid BOOLEAN DEFAULT false,
    full_name TEXT,
    birth_date TEXT,
    mother_name TEXT,
    father_name TEXT,
    naturalness TEXT,
    nationality TEXT,
    gender TEXT,
    issuing_organ TEXT,
    issuing_state TEXT,
    issuing_country TEXT,
    issuing_date TEXT,
    expiry_date TEXT,
    
    -- CNH Specific Fields
    cnh_category TEXT,
    cnh_renach TEXT,
    cnh_first_license_date TEXT,
    
    -- Passport Specific Fields
    passport_mrz_lines TEXT[],
    passport_mrz_valid BOOLEAN DEFAULT false,
    passport_issuing_country TEXT,
    
    -- Raw OCR payload & confidence score
    confidence_score NUMERIC(4, 2) DEFAULT 0.00,
    raw_ocr_text TEXT,
    extracted_payload JSONB DEFAULT '{}'::jsonb,
    
    operator_notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 4. BATCH SESSIONS TABLE
CREATE TABLE IF NOT EXISTS public.batch_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_name TEXT NOT NULL,
    total_files INT NOT NULL DEFAULT 0,
    processed_files INT NOT NULL DEFAULT 0,
    successful_files INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- ==============================================================================
-- INDICES FOR ULTRA-FAST SEARCH & RETRIEVAL
-- ==============================================================================
CREATE INDEX IF NOT EXISTS idx_scanned_docs_cpf ON public.scanned_documents(cpf);
CREATE INDEX IF NOT EXISTS idx_scanned_docs_doc_num ON public.scanned_documents(document_number);
CREATE INDEX IF NOT EXISTS idx_scanned_docs_type ON public.scanned_documents(document_type);
CREATE INDEX IF NOT EXISTS idx_scanned_docs_name ON public.scanned_documents(full_name);
CREATE INDEX IF NOT EXISTS idx_scanned_docs_created ON public.scanned_documents(created_at DESC);

-- ==============================================================================
-- STORAGE BUCKET CONFIGURATION (client-documents)
-- ==============================================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'client-documents',
    'client-documents',
    true, -- Public read for instant client previews (or false for private signed URLs)
    26214400, -- 25MB limit per document capture
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
ON CONFLICT (id) DO UPDATE SET
    public = true,
    file_size_limit = 26214400;

-- ==============================================================================
-- ROW-LEVEL SECURITY (RLS) POLICIES
-- ==============================================================================
ALTER TABLE public.scanned_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.batch_sessions ENABLE ROW LEVEL SECURITY;

-- Scanned Documents Table RLS (Permit anon + authenticated for seamless mobile/kiosk operations)
DO $$ BEGIN
    DROP POLICY IF EXISTS "Allow anon and authenticated full access to scanned documents" ON public.scanned_documents;
    CREATE POLICY "Allow anon and authenticated full access to scanned documents"
    ON public.scanned_documents FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);
EXCEPTION
    WHEN undefined_object THEN null;
END $$;

-- Batch Sessions Table RLS
DO $$ BEGIN
    DROP POLICY IF EXISTS "Allow anon and authenticated full access to batch sessions" ON public.batch_sessions;
    CREATE POLICY "Allow anon and authenticated full access to batch sessions"
    ON public.batch_sessions FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);
EXCEPTION
    WHEN undefined_object THEN null;
END $$;

-- Storage Objects Policies for client-documents
DO $$ BEGIN
    DROP POLICY IF EXISTS "Allow anon and authenticated access to client-documents" ON storage.objects;
    CREATE POLICY "Allow anon and authenticated access to client-documents"
    ON storage.objects FOR ALL
    TO anon, authenticated
    USING (bucket_id = 'client-documents')
    WITH CHECK (bucket_id = 'client-documents');
EXCEPTION
    WHEN undefined_object THEN null;
END $$;

-- ==============================================================================
-- SEARCH HELPER FUNCTION
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.search_scanned_documents(search_term TEXT)
RETURNS SETOF public.scanned_documents
LANGUAGE sql
STABLE
AS $$
    SELECT *
    FROM public.scanned_documents
    WHERE
        full_name ILIKE '%' || search_term || '%'
        OR document_number ILIKE '%' || search_term || '%'
        OR cpf ILIKE '%' || search_term || '%'
        OR mother_name ILIKE '%' || search_term || '%'
    ORDER BY created_at DESC
    LIMIT 50;
$$;
