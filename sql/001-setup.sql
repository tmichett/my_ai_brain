-- Open Brain Database Setup
-- Run against local Supabase Postgres (port 54322)
-- Usage: podman exec supabase_db_<project> psql -U postgres -f /path/to/001-setup.sql
-- Or paste into Supabase Studio SQL Editor (http://127.0.0.1:54323)

-- 1. Enable pgvector extension
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;

-- 2. Create thoughts table
CREATE TABLE IF NOT EXISTS public.thoughts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  content text NOT NULL,
  embedding extensions.vector(768),
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS thoughts_metadata_idx ON public.thoughts USING gin (metadata);
CREATE INDEX IF NOT EXISTS thoughts_created_idx ON public.thoughts (created_at DESC);

-- 3. Create semantic search function
CREATE OR REPLACE FUNCTION public.match_thoughts(
  query_embedding extensions.vector(768),
  match_threshold float DEFAULT 0.5,
  match_count int DEFAULT 10,
  filter jsonb DEFAULT '{}'::jsonb
)
RETURNS TABLE (
  id uuid,
  content text,
  metadata jsonb,
  similarity float,
  created_at timestamptz
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    t.id,
    t.content,
    t.metadata,
    1 - (t.embedding <=> query_embedding) AS similarity,
    t.created_at
  FROM public.thoughts t
  WHERE
    t.embedding IS NOT NULL
    AND 1 - (t.embedding <=> query_embedding) > match_threshold
    AND (filter = '{}'::jsonb OR t.metadata @> filter)
  ORDER BY t.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;

-- 4. Row Level Security
ALTER TABLE public.thoughts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Service role full access" ON public.thoughts;
-- Local Supabase sb_secret_* keys bind as Postgres role service_role directly;
-- auth.role() JWT checks fail for INSERT (42501). Use TO service_role instead.
CREATE POLICY "Service role full access"
  ON public.thoughts
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

GRANT ALL ON TABLE public.thoughts TO service_role;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.thoughts TO anon, authenticated, service_role;
