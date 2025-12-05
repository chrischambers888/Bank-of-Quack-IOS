-- Fix search_path security warning for calculate_split_percentage function
-- Supabase Security Advisor flagged this function as having a mutable search_path

CREATE OR REPLACE FUNCTION public.calculate_split_percentage(
  p_amount NUMERIC,
  p_total NUMERIC
)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
BEGIN
  IF p_total IS NULL OR p_total = 0 THEN
    RETURN 0;
  END IF;
  RETURN (p_amount / p_total) * 100;
END;
$$;

