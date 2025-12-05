-- Split Validation Migration
-- Adds database-level validation to ensure split sums equal transaction amounts
-- Also adds a balance health check view to detect households with non-zero balance sums
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- STEP 1: Create helper function to validate transaction splits
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.validate_transaction_splits(
  p_transaction_id UUID,
  p_expected_amount NUMERIC
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_total_owed NUMERIC;
  v_total_paid NUMERIC;
  v_tolerance NUMERIC := 0.01;  -- Allow for small rounding differences
BEGIN
  -- Calculate sum of owed amounts
  SELECT COALESCE(SUM(owed_amount), 0)
  INTO v_total_owed
  FROM public.transaction_splits
  WHERE transaction_id = p_transaction_id;
  
  -- Calculate sum of paid amounts
  SELECT COALESCE(SUM(paid_amount), 0)
  INTO v_total_paid
  FROM public.transaction_splits
  WHERE transaction_id = p_transaction_id;
  
  -- Validate owed amounts sum to transaction amount
  IF ABS(v_total_owed - p_expected_amount) > v_tolerance THEN
    RAISE EXCEPTION 'Split owed amounts (%) do not equal transaction amount (%). Difference: %',
      v_total_owed, p_expected_amount, (v_total_owed - p_expected_amount);
  END IF;
  
  -- Validate paid amounts sum to transaction amount
  IF ABS(v_total_paid - p_expected_amount) > v_tolerance THEN
    RAISE EXCEPTION 'Split paid amounts (%) do not equal transaction amount (%). Difference: %',
      v_total_paid, p_expected_amount, (v_total_paid - p_expected_amount);
  END IF;
END;
$$;

--------------------------------------------------------------------------------
-- STEP 2: Create function to auto-calculate percentages from amounts
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.calculate_split_percentage(
  p_amount NUMERIC,
  p_total NUMERIC
)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_total IS NULL OR p_total = 0 THEN
    RETURN 0;
  END IF;
  RETURN (p_amount / p_total) * 100;
END;
$$;

--------------------------------------------------------------------------------
-- STEP 3: Update create_transaction_with_splits to validate and auto-calculate percentages
--------------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.create_transaction_with_splits(UUID, DATE, TEXT, NUMERIC, TEXT, UUID, UUID, UUID, TEXT, TEXT, UUID, UUID, BOOLEAN, TEXT, UUID, JSONB);

CREATE OR REPLACE FUNCTION public.create_transaction_with_splits(
  p_household_id UUID,
  p_date DATE,
  p_description TEXT,
  p_amount NUMERIC,
  p_transaction_type TEXT,
  p_paid_by_member_id UUID,
  p_paid_to_member_id UUID,
  p_category_id UUID,
  p_split_type TEXT,
  p_paid_by_type TEXT,
  p_split_member_id UUID,
  p_reimburses_transaction_id UUID,
  p_excluded_from_budget BOOLEAN,
  p_notes TEXT,
  p_created_by_user_id UUID,
  p_splits JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_transaction_id UUID;
  v_split JSONB;
  v_member_count INT;
  v_equal_share NUMERIC;
  v_member RECORD;
  v_owed_amount NUMERIC;
  v_owed_percentage NUMERIC;
  v_paid_amount NUMERIC;
  v_paid_percentage NUMERIC;
BEGIN
  -- Create the transaction
  INSERT INTO public.transactions (
    household_id, date, description, amount, transaction_type,
    paid_by_member_id, paid_to_member_id, category_id, split_type,
    paid_by_type, split_member_id, reimburses_transaction_id, excluded_from_budget, notes, created_by_user_id
  )
  VALUES (
    p_household_id, p_date, p_description, p_amount, p_transaction_type,
    p_paid_by_member_id, p_paid_to_member_id, p_category_id, p_split_type,
    p_paid_by_type, p_split_member_id, p_reimburses_transaction_id, p_excluded_from_budget, p_notes, p_created_by_user_id
  )
  RETURNING id INTO v_transaction_id;

  -- Only create splits for expenses
  IF p_transaction_type = 'expense' THEN
    IF p_splits IS NOT NULL AND jsonb_array_length(p_splits) > 0 THEN
      -- Use provided splits
      FOR v_split IN SELECT * FROM jsonb_array_elements(p_splits)
      LOOP
        v_owed_amount := COALESCE((v_split->>'owed_amount')::NUMERIC, 0);
        v_paid_amount := COALESCE((v_split->>'paid_amount')::NUMERIC, 0);
        
        -- Auto-calculate percentages if not provided or zero
        v_owed_percentage := (v_split->>'owed_percentage')::NUMERIC;
        IF v_owed_percentage IS NULL OR v_owed_percentage = 0 THEN
          v_owed_percentage := public.calculate_split_percentage(v_owed_amount, p_amount);
        END IF;
        
        v_paid_percentage := (v_split->>'paid_percentage')::NUMERIC;
        IF v_paid_percentage IS NULL OR v_paid_percentage = 0 THEN
          v_paid_percentage := public.calculate_split_percentage(v_paid_amount, p_amount);
        END IF;
        
        INSERT INTO public.transaction_splits (
          transaction_id, member_id, amount, percentage, 
          owed_amount, owed_percentage, paid_amount, paid_percentage
        )
        VALUES (
          v_transaction_id,
          (v_split->>'member_id')::UUID,
          v_owed_amount,
          v_owed_percentage,
          v_owed_amount,
          v_owed_percentage,
          v_paid_amount,
          v_paid_percentage
        );
      END LOOP;
      
      -- Validate that splits sum correctly
      PERFORM public.validate_transaction_splits(v_transaction_id, p_amount);
    ELSE
      -- Fallback: Auto-generate splits based on split_type and paid_by_type
      -- This is for backwards compatibility with older clients
      SELECT COUNT(*) INTO v_member_count
      FROM public.household_members
      WHERE household_id = p_household_id AND status = 'approved';
      
      v_equal_share := p_amount / GREATEST(v_member_count, 1);
      
      FOR v_member IN 
        SELECT id FROM public.household_members 
        WHERE household_id = p_household_id AND status = 'approved'
      LOOP
        INSERT INTO public.transaction_splits (
          transaction_id, member_id, amount, owed_amount, owed_percentage, paid_amount, paid_percentage
        )
        VALUES (
          v_transaction_id,
          v_member.id,
          CASE 
            WHEN p_split_type = 'custom' THEN v_equal_share
            WHEN p_split_type = 'member_only' AND v_member.id = p_split_member_id THEN p_amount
            WHEN p_split_type = 'payer_only' AND v_member.id = p_paid_by_member_id THEN p_amount
            ELSE 0
          END,
          CASE 
            WHEN p_split_type = 'custom' THEN v_equal_share
            WHEN p_split_type = 'member_only' AND v_member.id = p_split_member_id THEN p_amount
            WHEN p_split_type = 'payer_only' AND v_member.id = p_paid_by_member_id THEN p_amount
            ELSE 0
          END,
          CASE 
            WHEN p_split_type = 'custom' THEN 100.0 / v_member_count
            WHEN p_split_type = 'member_only' AND v_member.id = p_split_member_id THEN 100
            WHEN p_split_type = 'payer_only' AND v_member.id = p_paid_by_member_id THEN 100
            ELSE 0
          END,
          CASE 
            WHEN p_paid_by_type = 'single' AND v_member.id = p_paid_by_member_id THEN p_amount
            WHEN p_paid_by_type = 'custom' THEN v_equal_share
            ELSE 0
          END,
          CASE 
            WHEN p_paid_by_type = 'single' AND v_member.id = p_paid_by_member_id THEN 100
            WHEN p_paid_by_type = 'custom' THEN 100.0 / v_member_count
            ELSE 0
          END
        );
      END LOOP;
    END IF;
  END IF;
  
  RETURN v_transaction_id;
END;
$$;

--------------------------------------------------------------------------------
-- STEP 4: Update update_transaction_with_splits to validate and auto-calculate percentages
--------------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.update_transaction_with_splits(UUID, DATE, TEXT, NUMERIC, TEXT, UUID, UUID, UUID, TEXT, TEXT, UUID, UUID, BOOLEAN, TEXT, JSONB);

CREATE OR REPLACE FUNCTION public.update_transaction_with_splits(
  p_transaction_id UUID,
  p_date DATE,
  p_description TEXT,
  p_amount NUMERIC,
  p_transaction_type TEXT,
  p_paid_by_member_id UUID,
  p_paid_to_member_id UUID,
  p_category_id UUID,
  p_split_type TEXT,
  p_paid_by_type TEXT,
  p_split_member_id UUID,
  p_reimburses_transaction_id UUID,
  p_excluded_from_budget BOOLEAN,
  p_notes TEXT,
  p_splits JSONB DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_household_id UUID;
  v_split JSONB;
  v_member_count INT;
  v_equal_share NUMERIC;
  v_member RECORD;
  v_owed_amount NUMERIC;
  v_owed_percentage NUMERIC;
  v_paid_amount NUMERIC;
  v_paid_percentage NUMERIC;
BEGIN
  -- Get the household_id for the transaction
  SELECT household_id INTO v_household_id
  FROM public.transactions
  WHERE id = p_transaction_id;
  
  IF v_household_id IS NULL THEN
    RAISE EXCEPTION 'Transaction not found';
  END IF;

  -- Update the transaction
  UPDATE public.transactions
  SET
    date = p_date,
    description = p_description,
    amount = p_amount,
    transaction_type = p_transaction_type,
    paid_by_member_id = p_paid_by_member_id,
    paid_to_member_id = p_paid_to_member_id,
    category_id = p_category_id,
    split_type = p_split_type,
    paid_by_type = p_paid_by_type,
    split_member_id = p_split_member_id,
    reimburses_transaction_id = p_reimburses_transaction_id,
    excluded_from_budget = p_excluded_from_budget,
    notes = p_notes,
    updated_at = NOW()
  WHERE id = p_transaction_id;

  -- Only update splits for expenses
  IF p_transaction_type = 'expense' THEN
    -- Delete existing splits
    DELETE FROM public.transaction_splits WHERE transaction_id = p_transaction_id;
    
    IF p_splits IS NOT NULL AND jsonb_array_length(p_splits) > 0 THEN
      -- Use provided splits
      FOR v_split IN SELECT * FROM jsonb_array_elements(p_splits)
      LOOP
        v_owed_amount := COALESCE((v_split->>'owed_amount')::NUMERIC, 0);
        v_paid_amount := COALESCE((v_split->>'paid_amount')::NUMERIC, 0);
        
        -- Auto-calculate percentages if not provided or zero
        v_owed_percentage := (v_split->>'owed_percentage')::NUMERIC;
        IF v_owed_percentage IS NULL OR v_owed_percentage = 0 THEN
          v_owed_percentage := public.calculate_split_percentage(v_owed_amount, p_amount);
        END IF;
        
        v_paid_percentage := (v_split->>'paid_percentage')::NUMERIC;
        IF v_paid_percentage IS NULL OR v_paid_percentage = 0 THEN
          v_paid_percentage := public.calculate_split_percentage(v_paid_amount, p_amount);
        END IF;
        
        INSERT INTO public.transaction_splits (
          transaction_id, member_id, amount, percentage,
          owed_amount, owed_percentage, paid_amount, paid_percentage
        )
        VALUES (
          p_transaction_id,
          (v_split->>'member_id')::UUID,
          v_owed_amount,
          v_owed_percentage,
          v_owed_amount,
          v_owed_percentage,
          v_paid_amount,
          v_paid_percentage
        );
      END LOOP;
      
      -- Validate that splits sum correctly
      PERFORM public.validate_transaction_splits(p_transaction_id, p_amount);
    ELSE
      -- Fallback: Auto-generate splits based on split_type and paid_by_type
      SELECT COUNT(*) INTO v_member_count
      FROM public.household_members
      WHERE household_id = v_household_id AND status = 'approved';
      
      v_equal_share := p_amount / GREATEST(v_member_count, 1);
      
      FOR v_member IN 
        SELECT id FROM public.household_members 
        WHERE household_id = v_household_id AND status = 'approved'
      LOOP
        INSERT INTO public.transaction_splits (
          transaction_id, member_id, amount, owed_amount, owed_percentage, paid_amount, paid_percentage
        )
        VALUES (
          p_transaction_id,
          v_member.id,
          CASE 
            WHEN p_split_type = 'custom' THEN v_equal_share
            WHEN p_split_type = 'member_only' AND v_member.id = p_split_member_id THEN p_amount
            WHEN p_split_type = 'payer_only' AND v_member.id = p_paid_by_member_id THEN p_amount
            ELSE 0
          END,
          CASE 
            WHEN p_split_type = 'custom' THEN v_equal_share
            WHEN p_split_type = 'member_only' AND v_member.id = p_split_member_id THEN p_amount
            WHEN p_split_type = 'payer_only' AND v_member.id = p_paid_by_member_id THEN p_amount
            ELSE 0
          END,
          CASE 
            WHEN p_split_type = 'custom' THEN 100.0 / v_member_count
            WHEN p_split_type = 'member_only' AND v_member.id = p_split_member_id THEN 100
            WHEN p_split_type = 'payer_only' AND v_member.id = p_paid_by_member_id THEN 100
            ELSE 0
          END,
          CASE 
            WHEN p_paid_by_type = 'single' AND v_member.id = p_paid_by_member_id THEN p_amount
            WHEN p_paid_by_type = 'custom' THEN v_equal_share
            ELSE 0
          END,
          CASE 
            WHEN p_paid_by_type = 'single' AND v_member.id = p_paid_by_member_id THEN 100
            WHEN p_paid_by_type = 'custom' THEN 100.0 / v_member_count
            ELSE 0
          END
        );
      END LOOP;
    END IF;
  ELSE
    -- Non-expense transactions don't have splits
    DELETE FROM public.transaction_splits WHERE transaction_id = p_transaction_id;
  END IF;
  
  RETURN TRUE;
END;
$$;

--------------------------------------------------------------------------------
-- STEP 5: Create balance health check view
-- This view detects households where member balances don't sum to zero
--------------------------------------------------------------------------------

DROP VIEW IF EXISTS public.balance_health_check;

CREATE VIEW public.balance_health_check
WITH (security_invoker = on)
AS
SELECT 
  household_id,
  SUM(balance) AS total_imbalance,
  COUNT(*) AS member_count,
  CASE 
    WHEN ABS(SUM(balance)) < 0.01 THEN 'OK'
    ELSE 'IMBALANCED'
  END AS status,
  CASE 
    WHEN ABS(SUM(balance)) < 0.01 THEN NULL
    ELSE 'Member balances do not sum to zero. Total imbalance: ' || ROUND(SUM(balance)::NUMERIC, 2)::TEXT
  END AS message
FROM public.member_balances
GROUP BY household_id;

-- Add comment for documentation
COMMENT ON VIEW public.balance_health_check IS 
'Health check view to detect households where member balances do not sum to zero. 
Status will be OK if balances are balanced (within tolerance), or IMBALANCED if there is an issue.
An imbalance indicates a bug in transaction creation or editing that should be investigated.';

--------------------------------------------------------------------------------
-- STEP 6: Create a constraint trigger for additional safety
-- This trigger validates splits after each statement (handles direct DB access)
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.trigger_validate_transaction_splits()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_transaction_record RECORD;
  v_total_owed NUMERIC;
  v_total_paid NUMERIC;
  v_tolerance NUMERIC := 0.01;
BEGIN
  -- For each distinct transaction_id affected by this statement
  FOR v_transaction_record IN
    SELECT DISTINCT ts.transaction_id, t.amount
    FROM public.transaction_splits ts
    JOIN public.transactions t ON t.id = ts.transaction_id
    WHERE ts.transaction_id IN (
      SELECT DISTINCT transaction_id 
      FROM public.transaction_splits 
      WHERE transaction_id = COALESCE(NEW.transaction_id, OLD.transaction_id)
    )
    AND t.transaction_type = 'expense'
  LOOP
    -- Calculate totals
    SELECT COALESCE(SUM(owed_amount), 0), COALESCE(SUM(paid_amount), 0)
    INTO v_total_owed, v_total_paid
    FROM public.transaction_splits
    WHERE transaction_id = v_transaction_record.transaction_id;
    
    -- Validate owed amounts
    IF ABS(v_total_owed - v_transaction_record.amount) > v_tolerance THEN
      RAISE WARNING 'Split validation warning: Transaction % owed amounts (%) do not equal transaction amount (%)',
        v_transaction_record.transaction_id, v_total_owed, v_transaction_record.amount;
    END IF;
    
    -- Validate paid amounts
    IF ABS(v_total_paid - v_transaction_record.amount) > v_tolerance THEN
      RAISE WARNING 'Split validation warning: Transaction % paid amounts (%) do not equal transaction amount (%)',
        v_transaction_record.transaction_id, v_total_paid, v_transaction_record.amount;
    END IF;
  END LOOP;
  
  RETURN NULL;
END;
$$;

-- Create the trigger (fires as a constraint trigger at end of statement)
-- Using WARNING instead of EXCEPTION to avoid breaking existing data/migrations
-- The RPC functions will enforce strict validation; this is a safety net for direct DB access
DROP TRIGGER IF EXISTS validate_splits_trigger ON public.transaction_splits;

CREATE CONSTRAINT TRIGGER validate_splits_trigger
AFTER INSERT OR UPDATE ON public.transaction_splits
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION public.trigger_validate_transaction_splits();

--------------------------------------------------------------------------------
-- STEP 7: Create problematic_transactions view
-- This view identifies transactions where splits don't sum correctly
--------------------------------------------------------------------------------

DROP VIEW IF EXISTS public.problematic_transactions;

CREATE VIEW public.problematic_transactions
WITH (security_invoker = on)
AS
SELECT 
  t.id AS transaction_id,
  t.household_id,
  t.date,
  t.description,
  t.amount AS expected_amount,
  COALESCE(SUM(ts.owed_amount), 0) AS actual_owed_sum,
  COALESCE(SUM(ts.paid_amount), 0) AS actual_paid_sum,
  t.amount - COALESCE(SUM(ts.owed_amount), 0) AS owed_difference,
  t.amount - COALESCE(SUM(ts.paid_amount), 0) AS paid_difference
FROM public.transactions t
LEFT JOIN public.transaction_splits ts ON ts.transaction_id = t.id
WHERE t.transaction_type = 'expense'
GROUP BY t.id, t.household_id, t.date, t.description, t.amount
HAVING 
  ABS(t.amount - COALESCE(SUM(ts.owed_amount), 0)) > 0.01
  OR ABS(t.amount - COALESCE(SUM(ts.paid_amount), 0)) > 0.01;

COMMENT ON VIEW public.problematic_transactions IS 
'View to identify transactions where split owed/paid amounts do not equal the transaction amount.
These transactions indicate data integrity issues that need investigation.';

--------------------------------------------------------------------------------
-- STEP 8: Grant permissions
--------------------------------------------------------------------------------

-- Grant execute on new functions to authenticated users
GRANT EXECUTE ON FUNCTION public.validate_transaction_splits(UUID, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.calculate_split_percentage(NUMERIC, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION public.trigger_validate_transaction_splits() TO authenticated;

-- Grant select on views to authenticated users
GRANT SELECT ON public.balance_health_check TO authenticated;
GRANT SELECT ON public.problematic_transactions TO authenticated;

