-- Quack App - Multi-Tenant Schema
-- Supports multiple households with multiple members each
--------------------------------------------------------------------------------

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

--------------------------------------------------------------------------------
-- HOUSEHOLDS (the "banks")
--------------------------------------------------------------------------------
CREATE TABLE public.households (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  invite_code TEXT UNIQUE DEFAULT encode(gen_random_bytes(6), 'hex'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

--------------------------------------------------------------------------------
-- HOUSEHOLD MEMBERS
--------------------------------------------------------------------------------
CREATE TABLE public.household_members (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  avatar_url TEXT,
  role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('owner', 'admin', 'member')),
  color TEXT DEFAULT '#26A69A', -- For charts and visual identification
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(household_id, user_id)
);

-- Index for faster lookups
CREATE INDEX idx_household_members_user_id ON public.household_members(user_id);
CREATE INDEX idx_household_members_household_id ON public.household_members(household_id);

--------------------------------------------------------------------------------
-- CATEGORIES (per household)
--------------------------------------------------------------------------------
CREATE TABLE public.categories (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  icon TEXT, -- emoji or icon name
  color TEXT DEFAULT '#26A69A',
  image_url TEXT,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(household_id, name)
);

CREATE INDEX idx_categories_household_id ON public.categories(household_id);

--------------------------------------------------------------------------------
-- SECTORS (category groups, per household)
--------------------------------------------------------------------------------
CREATE TABLE public.sectors (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  color TEXT DEFAULT '#004D40',
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(household_id, name)
);

CREATE INDEX idx_sectors_household_id ON public.sectors(household_id);

--------------------------------------------------------------------------------
-- SECTOR CATEGORIES (many-to-many)
--------------------------------------------------------------------------------
CREATE TABLE public.sector_categories (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  sector_id UUID NOT NULL REFERENCES public.sectors(id) ON DELETE CASCADE,
  category_id UUID NOT NULL REFERENCES public.categories(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(sector_id, category_id)
);

--------------------------------------------------------------------------------
-- TRANSACTIONS
--------------------------------------------------------------------------------
CREATE TABLE public.transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  description TEXT NOT NULL,
  amount NUMERIC NOT NULL CHECK (amount >= 0),
  transaction_type TEXT NOT NULL DEFAULT 'expense' 
    CHECK (transaction_type IN ('expense', 'income', 'settlement', 'reimbursement')),
  
  -- Who paid/received
  paid_by_member_id UUID REFERENCES public.household_members(id) ON DELETE SET NULL,
  paid_to_member_id UUID REFERENCES public.household_members(id) ON DELETE SET NULL,
  
  -- Expense specifics
  category_id UUID REFERENCES public.categories(id) ON DELETE SET NULL,
  split_type TEXT DEFAULT 'equal' CHECK (split_type IN ('equal', 'custom', 'payer_only')),
  
  -- For reimbursements
  reimburses_transaction_id UUID REFERENCES public.transactions(id) ON DELETE SET NULL,
  
  -- Budget exclusions
  excluded_from_budget BOOLEAN DEFAULT FALSE,
  
  -- Metadata
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_transactions_household_id ON public.transactions(household_id);
CREATE INDEX idx_transactions_date ON public.transactions(date DESC);
CREATE INDEX idx_transactions_category_id ON public.transactions(category_id);

--------------------------------------------------------------------------------
-- TRANSACTION SPLITS (for custom splits among members)
--------------------------------------------------------------------------------
CREATE TABLE public.transaction_splits (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  transaction_id UUID NOT NULL REFERENCES public.transactions(id) ON DELETE CASCADE,
  member_id UUID NOT NULL REFERENCES public.household_members(id) ON DELETE CASCADE,
  amount NUMERIC NOT NULL CHECK (amount >= 0),
  percentage NUMERIC, -- Optional: store percentage for reference
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(transaction_id, member_id)
);

CREATE INDEX idx_transaction_splits_transaction_id ON public.transaction_splits(transaction_id);

--------------------------------------------------------------------------------
-- BUDGETS (monthly, per category or sector)
--------------------------------------------------------------------------------
CREATE TABLE public.budgets (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
  
  -- Target (either category or sector, not both)
  category_id UUID REFERENCES public.categories(id) ON DELETE CASCADE,
  sector_id UUID REFERENCES public.sectors(id) ON DELETE CASCADE,
  
  -- Time period
  year INTEGER NOT NULL,
  month INTEGER CHECK (month >= 1 AND month <= 12), -- NULL for yearly budgets
  
  -- Budget amount
  amount NUMERIC NOT NULL CHECK (amount >= 0),
  
  -- For per-member budgets
  budget_type TEXT DEFAULT 'household' CHECK (budget_type IN ('household', 'per_member')),
  
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  -- Ensure either category or sector, not both
  CONSTRAINT budget_target_check CHECK (
    (category_id IS NOT NULL AND sector_id IS NULL) OR
    (category_id IS NULL AND sector_id IS NOT NULL)
  ),
  -- Unique constraint per target per period
  UNIQUE(household_id, category_id, sector_id, year, month)
);

CREATE INDEX idx_budgets_household_id ON public.budgets(household_id);

--------------------------------------------------------------------------------
-- MEMBER BUDGETS (individual budget allocations)
--------------------------------------------------------------------------------
CREATE TABLE public.member_budgets (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  budget_id UUID NOT NULL REFERENCES public.budgets(id) ON DELETE CASCADE,
  member_id UUID NOT NULL REFERENCES public.household_members(id) ON DELETE CASCADE,
  amount NUMERIC NOT NULL CHECK (amount >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(budget_id, member_id)
);

--------------------------------------------------------------------------------
-- TRANSACTION TEMPLATES
--------------------------------------------------------------------------------
CREATE TABLE public.transaction_templates (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
  created_by_member_id UUID REFERENCES public.household_members(id) ON DELETE SET NULL,
  
  name TEXT NOT NULL,
  description TEXT NOT NULL,
  amount NUMERIC NOT NULL CHECK (amount >= 0),
  transaction_type TEXT NOT NULL DEFAULT 'expense',
  category_id UUID REFERENCES public.categories(id) ON DELETE SET NULL,
  split_type TEXT DEFAULT 'equal',
  
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_transaction_templates_household_id ON public.transaction_templates(household_id);

--------------------------------------------------------------------------------
-- HOUSEHOLD SETTINGS (key-value store for household preferences)
--------------------------------------------------------------------------------
CREATE TABLE public.household_settings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  household_id UUID NOT NULL REFERENCES public.households(id) ON DELETE CASCADE,
  key TEXT NOT NULL,
  value TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(household_id, key)
);

--------------------------------------------------------------------------------
-- VIEWS
--------------------------------------------------------------------------------

-- Transactions with related data
CREATE OR REPLACE VIEW public.transactions_view AS
SELECT 
  t.*,
  c.name AS category_name,
  c.icon AS category_icon,
  c.color AS category_color,
  pm.display_name AS paid_by_name,
  pm.avatar_url AS paid_by_avatar,
  ptm.display_name AS paid_to_name,
  ptm.avatar_url AS paid_to_avatar
FROM public.transactions t
LEFT JOIN public.categories c ON t.category_id = c.id
LEFT JOIN public.household_members pm ON t.paid_by_member_id = pm.id
LEFT JOIN public.household_members ptm ON t.paid_to_member_id = ptm.id;

-- Member balances (who owes whom)
CREATE OR REPLACE VIEW public.member_balances AS
WITH member_expenses AS (
  -- What each member has paid
  SELECT 
    t.household_id,
    t.paid_by_member_id AS member_id,
    SUM(CASE 
      WHEN t.transaction_type = 'expense' AND t.split_type = 'equal' THEN t.amount
      WHEN t.transaction_type = 'expense' AND t.split_type = 'payer_only' THEN t.amount
      ELSE 0
    END) AS total_paid
  FROM public.transactions t
  WHERE t.paid_by_member_id IS NOT NULL
  GROUP BY t.household_id, t.paid_by_member_id
),
member_shares AS (
  -- What each member owes (their share of expenses)
  SELECT
    t.household_id,
    hm.id AS member_id,
    SUM(
      CASE 
        WHEN t.split_type = 'equal' THEN t.amount / member_count.cnt
        WHEN t.split_type = 'payer_only' AND t.paid_by_member_id = hm.id THEN t.amount
        WHEN t.split_type = 'custom' THEN COALESCE(ts.amount, 0)
        ELSE 0
      END
    ) AS total_share
  FROM public.transactions t
  CROSS JOIN public.household_members hm
  LEFT JOIN public.transaction_splits ts ON ts.transaction_id = t.id AND ts.member_id = hm.id
  LEFT JOIN LATERAL (
    SELECT COUNT(*) AS cnt 
    FROM public.household_members 
    WHERE household_id = t.household_id
  ) member_count ON TRUE
  WHERE t.household_id = hm.household_id
    AND t.transaction_type = 'expense'
  GROUP BY t.household_id, hm.id
),
settlements AS (
  SELECT
    household_id,
    paid_by_member_id AS from_member_id,
    paid_to_member_id AS to_member_id,
    SUM(amount) AS settled_amount
  FROM public.transactions
  WHERE transaction_type = 'settlement'
  GROUP BY household_id, paid_by_member_id, paid_to_member_id
)
SELECT 
  hm.household_id,
  hm.id AS member_id,
  hm.display_name,
  COALESCE(me.total_paid, 0) AS total_paid,
  COALESCE(ms.total_share, 0) AS total_share,
  COALESCE(me.total_paid, 0) - COALESCE(ms.total_share, 0) AS balance
FROM public.household_members hm
LEFT JOIN member_expenses me ON me.member_id = hm.id
LEFT JOIN member_shares ms ON ms.member_id = hm.id;

--------------------------------------------------------------------------------
-- ROW LEVEL SECURITY
--------------------------------------------------------------------------------

ALTER TABLE public.households ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.household_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sectors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sector_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transaction_splits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.budgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.member_budgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transaction_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.household_settings ENABLE ROW LEVEL SECURITY;

-- Helper function to check household membership
CREATE OR REPLACE FUNCTION public.user_household_ids()
RETURNS SETOF UUID
LANGUAGE SQL
SECURITY DEFINER
STABLE
AS $$
  SELECT household_id FROM public.household_members WHERE user_id = auth.uid();
$$;

-- Households: users can see households they belong to
CREATE POLICY "Users can view their households" ON public.households
  FOR SELECT USING (id IN (SELECT public.user_household_ids()));

CREATE POLICY "Users can create households" ON public.households
  FOR INSERT WITH CHECK (TRUE);

CREATE POLICY "Owners can update households" ON public.households
  FOR UPDATE USING (
    id IN (
      SELECT household_id FROM public.household_members 
      WHERE user_id = auth.uid() AND role = 'owner'
    )
  );

-- Household Members
CREATE POLICY "Members can view household members" ON public.household_members
  FOR SELECT USING (household_id IN (SELECT public.user_household_ids()));

CREATE POLICY "Users can join households" ON public.household_members
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Members can update their own profile" ON public.household_members
  FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "Owners can manage members" ON public.household_members
  FOR DELETE USING (
    household_id IN (
      SELECT household_id FROM public.household_members 
      WHERE user_id = auth.uid() AND role = 'owner'
    )
  );

-- Categories
CREATE POLICY "Members can view categories" ON public.categories
  FOR SELECT USING (household_id IN (SELECT public.user_household_ids()));

CREATE POLICY "Members can manage categories" ON public.categories
  FOR ALL USING (household_id IN (SELECT public.user_household_ids()));

-- Sectors
CREATE POLICY "Members can view sectors" ON public.sectors
  FOR SELECT USING (household_id IN (SELECT public.user_household_ids()));

CREATE POLICY "Members can manage sectors" ON public.sectors
  FOR ALL USING (household_id IN (SELECT public.user_household_ids()));

-- Sector Categories
CREATE POLICY "Members can view sector categories" ON public.sector_categories
  FOR SELECT USING (
    sector_id IN (SELECT id FROM public.sectors WHERE household_id IN (SELECT public.user_household_ids()))
  );

CREATE POLICY "Members can manage sector categories" ON public.sector_categories
  FOR ALL USING (
    sector_id IN (SELECT id FROM public.sectors WHERE household_id IN (SELECT public.user_household_ids()))
  );

-- Transactions
CREATE POLICY "Members can view transactions" ON public.transactions
  FOR SELECT USING (household_id IN (SELECT public.user_household_ids()));

CREATE POLICY "Members can manage transactions" ON public.transactions
  FOR ALL USING (household_id IN (SELECT public.user_household_ids()));

-- Transaction Splits
CREATE POLICY "Members can view splits" ON public.transaction_splits
  FOR SELECT USING (
    transaction_id IN (SELECT id FROM public.transactions WHERE household_id IN (SELECT public.user_household_ids()))
  );

CREATE POLICY "Members can manage splits" ON public.transaction_splits
  FOR ALL USING (
    transaction_id IN (SELECT id FROM public.transactions WHERE household_id IN (SELECT public.user_household_ids()))
  );

-- Budgets
CREATE POLICY "Members can view budgets" ON public.budgets
  FOR SELECT USING (household_id IN (SELECT public.user_household_ids()));

CREATE POLICY "Members can manage budgets" ON public.budgets
  FOR ALL USING (household_id IN (SELECT public.user_household_ids()));

-- Member Budgets
CREATE POLICY "Members can view member budgets" ON public.member_budgets
  FOR SELECT USING (
    budget_id IN (SELECT id FROM public.budgets WHERE household_id IN (SELECT public.user_household_ids()))
  );

CREATE POLICY "Members can manage member budgets" ON public.member_budgets
  FOR ALL USING (
    budget_id IN (SELECT id FROM public.budgets WHERE household_id IN (SELECT public.user_household_ids()))
  );

-- Transaction Templates
CREATE POLICY "Members can view templates" ON public.transaction_templates
  FOR SELECT USING (household_id IN (SELECT public.user_household_ids()));

CREATE POLICY "Members can manage templates" ON public.transaction_templates
  FOR ALL USING (household_id IN (SELECT public.user_household_ids()));

-- Household Settings
CREATE POLICY "Members can view settings" ON public.household_settings
  FOR SELECT USING (household_id IN (SELECT public.user_household_ids()));

CREATE POLICY "Members can manage settings" ON public.household_settings
  FOR ALL USING (household_id IN (SELECT public.user_household_ids()));

--------------------------------------------------------------------------------
-- FUNCTIONS
--------------------------------------------------------------------------------

-- Create household and add creator as owner
CREATE OR REPLACE FUNCTION public.create_household(
  p_name TEXT,
  p_display_name TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_household_id UUID;
BEGIN
  -- Create household
  INSERT INTO public.households (name)
  VALUES (p_name)
  RETURNING id INTO v_household_id;
  
  -- Add creator as owner
  INSERT INTO public.household_members (household_id, user_id, display_name, role)
  VALUES (v_household_id, auth.uid(), p_display_name, 'owner');
  
  RETURN v_household_id;
END;
$$;

-- Join household by invite code
CREATE OR REPLACE FUNCTION public.join_household(
  p_invite_code TEXT,
  p_display_name TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_household_id UUID;
BEGIN
  -- Find household by invite code
  SELECT id INTO v_household_id
  FROM public.households
  WHERE invite_code = p_invite_code;
  
  IF v_household_id IS NULL THEN
    RAISE EXCEPTION 'Invalid invite code';
  END IF;
  
  -- Check if already a member
  IF EXISTS (
    SELECT 1 FROM public.household_members 
    WHERE household_id = v_household_id AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Already a member of this household';
  END IF;
  
  -- Add as member
  INSERT INTO public.household_members (household_id, user_id, display_name, role)
  VALUES (v_household_id, auth.uid(), p_display_name, 'member');
  
  RETURN v_household_id;
END;
$$;

-- Regenerate invite code
CREATE OR REPLACE FUNCTION public.regenerate_invite_code(p_household_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_new_code TEXT;
BEGIN
  -- Verify user is owner
  IF NOT EXISTS (
    SELECT 1 FROM public.household_members 
    WHERE household_id = p_household_id 
      AND user_id = auth.uid() 
      AND role = 'owner'
  ) THEN
    RAISE EXCEPTION 'Only owners can regenerate invite codes';
  END IF;
  
  v_new_code := encode(gen_random_bytes(6), 'hex');
  
  UPDATE public.households
  SET invite_code = v_new_code, updated_at = NOW()
  WHERE id = p_household_id;
  
  RETURN v_new_code;
END;
$$;

--------------------------------------------------------------------------------
-- TRIGGERS
--------------------------------------------------------------------------------

-- Update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER update_households_updated_at
  BEFORE UPDATE ON public.households
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER update_household_members_updated_at
  BEFORE UPDATE ON public.household_members
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER update_transactions_updated_at
  BEFORE UPDATE ON public.transactions
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER update_budgets_updated_at
  BEFORE UPDATE ON public.budgets
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER update_transaction_templates_updated_at
  BEFORE UPDATE ON public.transaction_templates
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER update_household_settings_updated_at
  BEFORE UPDATE ON public.household_settings
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

--------------------------------------------------------------------------------
-- STORAGE BUCKETS
--------------------------------------------------------------------------------

INSERT INTO storage.buckets (id, name, public)
VALUES
  ('avatars', 'avatars', true),
  ('category-images', 'category-images', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies
CREATE POLICY "Authenticated users can upload avatars"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'avatars' AND auth.uid() IS NOT NULL);

CREATE POLICY "Anyone can view avatars"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

CREATE POLICY "Users can update their avatars"
  ON storage.objects FOR UPDATE
  USING (bucket_id = 'avatars' AND auth.uid() IS NOT NULL);

CREATE POLICY "Authenticated users can upload category images"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'category-images' AND auth.uid() IS NOT NULL);

CREATE POLICY "Anyone can view category images"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'category-images');
