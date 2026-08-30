-- ============================================================================
-- FINANÇAS DUO - SCHEMA CONTÁBIL AVANÇADO E RATEIO DE CASAL (POSTGRESQL / SUPABASE)
-- ============================================================================
-- Equação Fundamental: Ativos = Passivos + Patrimônio Líquido + Receitas - Despesas
-- Soma dos Postings por Transação: SUM(amount) = 0
-- Rateio de Casal (Ownership): owner_only, partner_only, shared_50_50
-- Tabela de Preferências: user_settings (Zero Hardcode de Nomes e Decisão de Onboarding)
-- Otimização RLS: Suporte transparente para modo Autenticado (Auth) e Anônimo (Publishable Key)
-- Integridade Relacional: ON DELETE RESTRICT com Soft Delete (is_active)
-- ============================================================================

-- 1. EXTENSÕES NECESSÁRIAS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. ENUMS DE DOMÍNIO
DO $$ BEGIN
    CREATE TYPE public.account_type_enum AS ENUM ('ASSET', 'LIABILITY', 'REVENUE', 'EXPENSE', 'EQUITY');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE public.ownership_type_enum AS ENUM ('owner_only', 'partner_only', 'shared_50_50');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 3. TABELA DE PREFERÊNCIAS DO USUÁRIO / CASAL (ZERO HARDCODE DE NOMES & ONBOARDING)
CREATE TABLE IF NOT EXISTS public.user_settings (
    user_id UUID PRIMARY KEY DEFAULT COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid),
    owner_name TEXT DEFAULT 'Edvan' NOT NULL,
    partner_name TEXT DEFAULT 'Yasmin' NOT NULL,
    onboarding_completed BOOLEAN DEFAULT false NOT NULL,
    onboarding_decision TEXT DEFAULT NULL, -- 'smart_defaults', 'custom', 'dismissed'
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Garantir colunas caso a tabela já tenha sido criada anteriormente
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='user_settings' AND column_name='onboarding_completed') THEN
        ALTER TABLE public.user_settings ADD COLUMN onboarding_completed BOOLEAN DEFAULT false NOT NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='user_settings' AND column_name='onboarding_decision') THEN
        ALTER TABLE public.user_settings ADD COLUMN onboarding_decision TEXT DEFAULT NULL;
    END IF;
END $$;

-- 4. TABELA DE PLANO DE CONTAS (CHART OF ACCOUNTS - 100% DINÂMICO)
CREATE TABLE IF NOT EXISTS public.accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID DEFAULT COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid),
    name TEXT NOT NULL,
    account_type public.account_type_enum NOT NULL,
    subtype TEXT DEFAULT 'general',
    titular TEXT DEFAULT 'Ambos' NOT NULL,
    color TEXT DEFAULT '#4f46e5',
    icon TEXT DEFAULT 'wallet',
    is_active BOOLEAN DEFAULT true NOT NULL,
    is_archived BOOLEAN DEFAULT false NOT NULL,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 5. TABELA DE RECORRÊNCIAS (PADRÃO RFC 5545 - RRULE)
CREATE TABLE IF NOT EXISTS public.recurring_patterns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID DEFAULT COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid),
    description TEXT NOT NULL,
    rrule TEXT NOT NULL,
    template_postings JSONB NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE,
    titular TEXT DEFAULT 'Ambos' NOT NULL,
    ownership_type public.ownership_type_enum DEFAULT 'owner_only' NOT NULL,
    active BOOLEAN DEFAULT true NOT NULL,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 6. TABELA DE TRANSAÇÕES (AGRUPADOR CONTÁBIL COM OWNERSHIP TYPE)
CREATE TABLE IF NOT EXISTS public.transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID DEFAULT COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid),
    date DATE NOT NULL,
    description TEXT NOT NULL,
    titular TEXT DEFAULT 'Ambos' NOT NULL,
    status TEXT DEFAULT 'completed' NOT NULL,
    ownership_type public.ownership_type_enum DEFAULT 'owner_only' NOT NULL,
    recurrence_id UUID REFERENCES public.recurring_patterns(id) ON DELETE SET NULL,
    recurrence_date DATE,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 7. TABELA DE POSTINGS (LINHAS DE DÉBITO E CRÉDITO COM INTEGRIDADE RELACIONAL ESTRITA)
CREATE TABLE IF NOT EXISTS public.postings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id UUID NOT NULL REFERENCES public.transactions(id) ON DELETE CASCADE,
    account_id UUID NOT NULL REFERENCES public.accounts(id) ON DELETE RESTRICT,
    amount NUMERIC(14, 2) NOT NULL,
    memo TEXT,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 8. TABELA DE ORÇAMENTO BASE ZERO (ZBB)
CREATE TABLE IF NOT EXISTS public.budgets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID DEFAULT COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid),
    account_id UUID NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
    month INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
    year INTEGER NOT NULL CHECK (year >= 2000),
    budgeted_amount NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
    titular TEXT DEFAULT 'Ambos' NOT NULL,
    is_custom_month BOOLEAN DEFAULT false NOT NULL,
    is_all_months BOOLEAN DEFAULT true NOT NULL,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
    CONSTRAINT uq_account_month_year UNIQUE (account_id, month, year)
);

-- 8.5. TABELA DE HISTÓRICO DE REAVALIAÇÕES DE INVESTIMENTOS (VALUATIONS & EVOLUÇÃO)
CREATE TABLE IF NOT EXISTS public.investment_valuations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID DEFAULT COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid),
    account_id UUID NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    previous_amount NUMERIC(14, 2) NOT NULL,
    new_amount NUMERIC(14, 2) NOT NULL,
    variation_amount NUMERIC(14, 2) NOT NULL,
    variation_pct NUMERIC(10, 4) NOT NULL,
    notes TEXT,
    titular TEXT DEFAULT 'Ambos' NOT NULL,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE public.investment_valuations ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- GARANTIR COLUNAS EM CASO DE TABELAS JÁ CRIADAS ANTERIORMENTE (MIGRAÇÕES SEGURAS)
-- ============================================================================
DO $$ BEGIN
    -- Colunas em transactions
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='transactions' AND column_name='titular') THEN
        ALTER TABLE public.transactions ADD COLUMN titular TEXT DEFAULT 'Ambos' NOT NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='transactions' AND column_name='status') THEN
        ALTER TABLE public.transactions ADD COLUMN status TEXT DEFAULT 'completed' NOT NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='transactions' AND column_name='ownership_type') THEN
        ALTER TABLE public.transactions ADD COLUMN ownership_type public.ownership_type_enum DEFAULT 'owner_only' NOT NULL;
    END IF;

    -- Colunas em accounts
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='accounts' AND column_name='titular') THEN
        ALTER TABLE public.accounts ADD COLUMN titular TEXT DEFAULT 'Ambos' NOT NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='accounts' AND column_name='is_active') THEN
        ALTER TABLE public.accounts ADD COLUMN is_active BOOLEAN DEFAULT true NOT NULL;
    END IF;

    -- Colunas em recurring_patterns
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='recurring_patterns' AND column_name='titular') THEN
        ALTER TABLE public.recurring_patterns ADD COLUMN titular TEXT DEFAULT 'Ambos' NOT NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='recurring_patterns' AND column_name='ownership_type') THEN
        ALTER TABLE public.recurring_patterns ADD COLUMN ownership_type public.ownership_type_enum DEFAULT 'owner_only' NOT NULL;
    END IF;

    -- Colunas em budgets
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='budgets' AND column_name='titular') THEN
        ALTER TABLE public.budgets ADD COLUMN titular TEXT DEFAULT 'Ambos' NOT NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='budgets' AND column_name='is_custom_month') THEN
        ALTER TABLE public.budgets ADD COLUMN is_custom_month BOOLEAN DEFAULT false NOT NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='budgets' AND column_name='is_all_months') THEN
        ALTER TABLE public.budgets ADD COLUMN is_all_months BOOLEAN DEFAULT true NOT NULL;
    END IF;

    -- Colunas em investment_valuations
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='investment_valuations' AND column_name='titular') THEN
        ALTER TABLE public.investment_valuations ADD COLUMN titular TEXT DEFAULT 'Ambos' NOT NULL;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='investment_valuations' AND column_name='notes') THEN
        ALTER TABLE public.investment_valuations ADD COLUMN notes TEXT;
    END IF;
END $$;

-- 9. ÍNDICES DE ALTA PERFORMANCE
CREATE INDEX IF NOT EXISTS idx_accounts_user_id ON public.accounts(user_id);
CREATE INDEX IF NOT EXISTS idx_accounts_active ON public.accounts(is_active);
CREATE INDEX IF NOT EXISTS idx_transactions_user_id ON public.transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_date ON public.transactions(date);
CREATE INDEX IF NOT EXISTS idx_transactions_status ON public.transactions(status);
CREATE INDEX IF NOT EXISTS idx_transactions_ownership ON public.transactions(ownership_type);
CREATE INDEX IF NOT EXISTS idx_transactions_titular ON public.transactions(titular);
CREATE INDEX IF NOT EXISTS idx_postings_transaction_id ON public.postings(transaction_id);
CREATE INDEX IF NOT EXISTS idx_postings_account_id ON public.postings(account_id);
CREATE INDEX IF NOT EXISTS idx_recurring_patterns_user_id ON public.recurring_patterns(user_id);
CREATE INDEX IF NOT EXISTS idx_budgets_user_id ON public.budgets(user_id);
CREATE INDEX IF NOT EXISTS idx_budgets_lookup ON public.budgets(year, month, account_id);

-- ============================================================================
-- 10. VALIDAÇÃO ESTRITA DE PARTIDAS DOBRADAS (CONSTRAINT TRIGGER DEFERRABLE)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.check_transaction_balance() 
RETURNS TRIGGER AS $$
DECLARE
    v_transaction_id UUID;
    v_balance NUMERIC;
    v_count INTEGER;
BEGIN
    v_transaction_id := COALESCE(NEW.transaction_id, OLD.transaction_id);
    
    IF EXISTS (SELECT 1 FROM public.transactions WHERE id = v_transaction_id) THEN
        SELECT COALESCE(SUM(amount), 0), COUNT(*) 
        INTO v_balance, v_count
        FROM public.postings
        WHERE transaction_id = v_transaction_id;

        IF v_count > 0 AND v_balance <> 0 THEN
            RAISE EXCEPTION 'VIOLAÇÃO CONTÁBIL: A transação % está desbalanceada! Soma dos postings: % (esperado: 0.00). Transação abortada.', 
                v_transaction_id, v_balance;
        END IF;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_postings_balance ON public.postings;
CREATE CONSTRAINT TRIGGER trg_check_postings_balance
AFTER INSERT OR UPDATE OR DELETE ON public.postings
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION public.check_transaction_balance();

-- ============================================================================
-- 11. RPCs PARA CRIAÇÃO E ATUALIZAÇÃO ATÔMICA DE TRANSAÇÕES (COM OWNERSHIP)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_transaction_with_postings(
    p_date DATE,
    p_description TEXT,
    p_postings JSONB,
    p_ownership_type public.ownership_type_enum DEFAULT 'owner_only',
    p_recurrence_id UUID DEFAULT NULL,
    p_recurrence_date DATE DEFAULT NULL,
    p_titular TEXT DEFAULT 'Ambos',
    p_status TEXT DEFAULT 'completed'
)
RETURNS UUID AS $$
DECLARE
    v_trans_id UUID;
    v_user_id UUID := COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid);
    v_item JSONB;
    v_total NUMERIC := 0;
    v_acc_id UUID;
    v_amt NUMERIC;
    v_memo TEXT;
BEGIN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_postings) LOOP
        v_total := v_total + (v_item->>'amount')::NUMERIC;
    END LOOP;

    IF v_total <> 0 THEN
        RAISE EXCEPTION 'Soma dos postings (%) não é igual a zero.', v_total;
    END IF;

    INSERT INTO public.transactions (user_id, date, description, titular, status, ownership_type, recurrence_id, recurrence_date)
    VALUES (v_user_id, p_date, p_description, p_titular, p_status, p_ownership_type, p_recurrence_id, p_recurrence_date)
    RETURNING id INTO v_trans_id;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_postings) LOOP
        v_acc_id := (v_item->>'account_id')::UUID;
        v_amt := (v_item->>'amount')::NUMERIC;
        v_memo := v_item->>'memo';

        INSERT INTO public.postings (transaction_id, account_id, amount, memo)
        VALUES (v_trans_id, v_acc_id, v_amt, v_memo);
    END LOOP;

    RETURN v_trans_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.update_transaction_with_postings(
    p_transaction_id UUID,
    p_date DATE,
    p_description TEXT,
    p_postings JSONB,
    p_ownership_type public.ownership_type_enum DEFAULT 'owner_only',
    p_titular TEXT DEFAULT 'Ambos',
    p_status TEXT DEFAULT 'completed'
)
RETURNS VOID AS $$
DECLARE
    v_user_id UUID := COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid);
    v_item JSONB;
    v_total NUMERIC := 0;
    v_acc_id UUID;
    v_amt NUMERIC;
    v_memo TEXT;
BEGIN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_postings) LOOP
        v_total := v_total + (v_item->>'amount')::NUMERIC;
    END LOOP;

    IF v_total <> 0 THEN
        RAISE EXCEPTION 'Erro de Edição: A soma dos lançamentos atualizados (%) não é zero.', v_total;
    END IF;

    UPDATE public.transactions 
    SET date = p_date, description = p_description, titular = p_titular, status = p_status, ownership_type = p_ownership_type
    WHERE id = p_transaction_id AND (user_id = v_user_id OR user_id IS NULL OR v_user_id = '00000000-0000-0000-0000-000000000000'::uuid);

    DELETE FROM public.postings WHERE transaction_id = p_transaction_id;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_postings) LOOP
        v_acc_id := (v_item->>'account_id')::UUID;
        v_amt := (v_item->>'amount')::NUMERIC;
        v_memo := v_item->>'memo';

        INSERT INTO public.postings (transaction_id, account_id, amount, memo)
        VALUES (p_transaction_id, v_acc_id, v_amt, v_memo);
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 12. PROVISIONAMENTO INICIAL DE DADOS (SMART DEFAULTS / ONBOARDING TRIGGER)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.handle_new_user_seed()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.user_settings (user_id, owner_name, partner_name, onboarding_completed, onboarding_decision)
    VALUES (NEW.id, 'Edvan', 'Yasmin', true, 'smart_defaults')
    ON CONFLICT (user_id) DO NOTHING;

    IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE user_id = NEW.id) THEN
        INSERT INTO public.accounts (user_id, name, account_type, subtype, titular, color, is_active)
        VALUES
            -- 1. ATIVOS (ASSET)
            (NEW.id, 'Conta Corrente Principal', 'ASSET', 'checking', 'Ambos', '#3b82f6', true),
            (NEW.id, 'Dinheiro na Carteira', 'ASSET', 'cash', 'Ambos', '#10b981', true),
            (NEW.id, 'Reserva de Emergência', 'ASSET', 'savings', 'Ambos', '#059669', true),
            (NEW.id, 'Vale Alimentação / Refeição', 'ASSET', 'benefit', 'Ambos', '#14b8a6', true),
            (NEW.id, 'Investimentos', 'ASSET', 'investment', 'Ambos', '#6366f1', true),

            -- 2. PASSIVOS (LIABILITY)
            (NEW.id, 'Cartão de Crédito Principal', 'LIABILITY', 'credit_card', 'Ambos', '#ef4444', true),
            (NEW.id, 'Empréstimo Pessoal', 'LIABILITY', 'loan', 'Ambos', '#f43f5e', true),
            (NEW.id, 'Financiamento', 'LIABILITY', 'financing', 'Ambos', '#e11d48', true),
            (NEW.id, 'Contas a Pagar (Terceiros)', 'LIABILITY', 'payable', 'Ambos', '#be123c', true),

            -- 3. RECEITAS (REVENUE)
            (NEW.id, 'Salário Principal', 'REVENUE', 'salary', 'Ambos', '#2563eb', true),
            (NEW.id, 'Rendimentos / Juros', 'REVENUE', 'investment', 'Ambos', '#0d9488', true),
            (NEW.id, 'Renda Extra / Freelance', 'REVENUE', 'freelance', 'Ambos', '#0284c7', true),
            (NEW.id, 'Reembolsos', 'REVENUE', 'refund', 'Ambos', '#0891b2', true),
            (NEW.id, 'Vendas', 'REVENUE', 'sales', 'Ambos', '#0ea5e9', true),

            -- 4. DESPESAS (EXPENSE)
            -- Moradia
            (NEW.id, 'Aluguel / Prestação', 'EXPENSE', 'fixed_expense', 'Ambos', '#4f46e5', true),
            (NEW.id, 'Condomínio', 'EXPENSE', 'fixed_expense', 'Ambos', '#4338ca', true),
            (NEW.id, 'Energia Elétrica', 'EXPENSE', 'fixed_expense', 'Ambos', '#6366f1', true),
            (NEW.id, 'Água', 'EXPENSE', 'fixed_expense', 'Ambos', '#818cf8', true),
            (NEW.id, 'Internet', 'EXPENSE', 'fixed_expense', 'Ambos', '#4f46e5', true),
            -- Alimentação
            (NEW.id, 'Supermercado', 'EXPENSE', 'variable_expense', 'Ambos', '#ea580c', true),
            (NEW.id, 'Restaurantes / Delivery', 'EXPENSE', 'variable_expense', 'Ambos', '#f97316', true),
            (NEW.id, 'Padaria / Lanches', 'EXPENSE', 'variable_expense', 'Ambos', '#fb923c', true),
            -- Transporte
            (NEW.id, 'Combustível', 'EXPENSE', 'variable_expense', 'Ambos', '#ca8a04', true),
            (NEW.id, 'Aplicativos (Uber/99)', 'EXPENSE', 'variable_expense', 'Ambos', '#eab308', true),
            (NEW.id, 'Transporte Público', 'EXPENSE', 'variable_expense', 'Ambos', '#facc15', true),
            (NEW.id, 'Manutenção do Veículo', 'EXPENSE', 'occasional', 'Ambos', '#d97706', true),
            -- Saúde
            (NEW.id, 'Plano de Saúde', 'EXPENSE', 'fixed_expense', 'Ambos', '#dc2626', true),
            (NEW.id, 'Farmácia', 'EXPENSE', 'variable_expense', 'Ambos', '#ef4444', true),
            (NEW.id, 'Consultas / Exames', 'EXPENSE', 'occasional', 'Ambos', '#b91c1c', true),
            -- Lazer & Estilo de Vida
            (NEW.id, 'Assinaturas (Streaming/Serviços)', 'EXPENSE', 'fixed_expense', 'Ambos', '#8b5cf6', true),
            (NEW.id, 'Saídas / Bares', 'EXPENSE', 'variable_expense', 'Ambos', '#a855f7', true),
            (NEW.id, 'Hobbies', 'EXPENSE', 'occasional', 'Ambos', '#7c3aed', true),
            -- Educação
            (NEW.id, 'Cursos / Mensalidades', 'EXPENSE', 'fixed_expense', 'Ambos', '#0284c7', true),
            (NEW.id, 'Livros / Materiais', 'EXPENSE', 'occasional', 'Ambos', '#0ea5e9', true),
            -- Cuidados Pessoais
            (NEW.id, 'Academia / Esportes', 'EXPENSE', 'fixed_expense', 'Ambos', '#ec4899', true),
            (NEW.id, 'Vestuário', 'EXPENSE', 'variable_expense', 'Ambos', '#f472b6', true),
            (NEW.id, 'Salão / Estética', 'EXPENSE', 'occasional', 'Ambos', '#db2777', true),
            -- Outros / Financeiro
            (NEW.id, 'Taxas Bancárias', 'EXPENSE', 'fixed_expense', 'Ambos', '#64748b', true),
            (NEW.id, 'Juros', 'EXPENSE', 'fixed_expense', 'Ambos', '#475569', true),
            (NEW.id, 'Presentes / Doações', 'EXPENSE', 'occasional', 'Ambos', '#94a3b8', true);
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'auth' AND table_name = 'users') THEN
        DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
        CREATE TRIGGER on_auth_user_created
        AFTER INSERT ON auth.users
        FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_seed();
    END IF;
END $$;

CREATE OR REPLACE FUNCTION public.seed_default_accounts_for_current_user()
RETURNS VOID AS $$
DECLARE
    v_user_id UUID := COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid);
BEGIN
    INSERT INTO public.user_settings (user_id, owner_name, partner_name, onboarding_completed, onboarding_decision)
    VALUES (v_user_id, 'Edvan', 'Yasmin', true, 'smart_defaults')
    ON CONFLICT (user_id) DO UPDATE 
    SET onboarding_completed = true, onboarding_decision = 'smart_defaults', updated_at = now();

    IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE (user_id = v_user_id OR user_id IS NULL OR user_id = '00000000-0000-0000-0000-000000000000'::uuid)) THEN
        INSERT INTO public.accounts (user_id, name, account_type, subtype, titular, color, is_active)
        VALUES
            -- 1. ATIVOS
            (v_user_id, 'Conta Corrente Principal', 'ASSET', 'checking', 'Ambos', '#3b82f6', true),
            (v_user_id, 'Dinheiro na Carteira', 'ASSET', 'cash', 'Ambos', '#10b981', true),
            (v_user_id, 'Reserva de Emergência', 'ASSET', 'savings', 'Ambos', '#059669', true),
            (v_user_id, 'Vale Alimentação / Refeição', 'ASSET', 'benefit', 'Ambos', '#14b8a6', true),
            (v_user_id, 'Investimentos', 'ASSET', 'investment', 'Ambos', '#6366f1', true),

            -- 2. PASSIVOS
            (v_user_id, 'Cartão de Crédito Principal', 'LIABILITY', 'credit_card', 'Ambos', '#ef4444', true),
            (v_user_id, 'Empréstimo Pessoal', 'LIABILITY', 'loan', 'Ambos', '#f43f5e', true),
            (v_user_id, 'Financiamento', 'LIABILITY', 'financing', 'Ambos', '#e11d48', true),
            (v_user_id, 'Contas a Pagar (Terceiros)', 'LIABILITY', 'payable', 'Ambos', '#be123c', true),

            -- 3. RECEITAS
            (v_user_id, 'Salário Principal', 'REVENUE', 'salary', 'Ambos', '#2563eb', true),
            (v_user_id, 'Rendimentos / Juros', 'REVENUE', 'investment', 'Ambos', '#0d9488', true),
            (v_user_id, 'Renda Extra / Freelance', 'REVENUE', 'freelance', 'Ambos', '#0284c7', true),
            (v_user_id, 'Reembolsos', 'REVENUE', 'refund', 'Ambos', '#0891b2', true),
            (v_user_id, 'Vendas', 'REVENUE', 'sales', 'Ambos', '#0ea5e9', true),

            -- 4. DESPESAS
            -- Moradia
            (v_user_id, 'Aluguel / Prestação', 'EXPENSE', 'fixed_expense', 'Ambos', '#4f46e5', true),
            (v_user_id, 'Condomínio', 'EXPENSE', 'fixed_expense', 'Ambos', '#4338ca', true),
            (v_user_id, 'Energia Elétrica', 'EXPENSE', 'fixed_expense', 'Ambos', '#6366f1', true),
            (v_user_id, 'Água', 'EXPENSE', 'fixed_expense', 'Ambos', '#818cf8', true),
            (v_user_id, 'Internet', 'EXPENSE', 'fixed_expense', 'Ambos', '#4f46e5', true),
            -- Alimentação
            (v_user_id, 'Supermercado', 'EXPENSE', 'variable_expense', 'Ambos', '#ea580c', true),
            (v_user_id, 'Restaurantes / Delivery', 'EXPENSE', 'variable_expense', 'Ambos', '#f97316', true),
            (v_user_id, 'Padaria / Lanches', 'EXPENSE', 'variable_expense', 'Ambos', '#fb923c', true),
            -- Transporte
            (v_user_id, 'Combustível', 'EXPENSE', 'variable_expense', 'Ambos', '#ca8a04', true),
            (v_user_id, 'Aplicativos (Uber/99)', 'EXPENSE', 'variable_expense', 'Ambos', '#eab308', true),
            (v_user_id, 'Transporte Público', 'EXPENSE', 'variable_expense', 'Ambos', '#facc15', true),
            (v_user_id, 'Manutenção do Veículo', 'EXPENSE', 'occasional', 'Ambos', '#d97706', true),
            -- Saúde
            (v_user_id, 'Plano de Saúde', 'EXPENSE', 'fixed_expense', 'Ambos', '#dc2626', true),
            (v_user_id, 'Farmácia', 'EXPENSE', 'variable_expense', 'Ambos', '#ef4444', true),
            (v_user_id, 'Consultas / Exames', 'EXPENSE', 'occasional', 'Ambos', '#b91c1c', true),
            -- Lazer & Estilo de Vida
            (v_user_id, 'Assinaturas (Streaming/Serviços)', 'EXPENSE', 'fixed_expense', 'Ambos', '#8b5cf6', true),
            (v_user_id, 'Saídas / Bares', 'EXPENSE', 'variable_expense', 'Ambos', '#a855f7', true),
            (v_user_id, 'Hobbies', 'EXPENSE', 'occasional', 'Ambos', '#7c3aed', true),
            -- Educação
            (v_user_id, 'Cursos / Mensalidades', 'EXPENSE', 'fixed_expense', 'Ambos', '#0284c7', true),
            (v_user_id, 'Livros / Materiais', 'EXPENSE', 'occasional', 'Ambos', '#0ea5e9', true),
            -- Cuidados Pessoais
            (v_user_id, 'Academia / Esportes', 'EXPENSE', 'fixed_expense', 'Ambos', '#ec4899', true),
            (v_user_id, 'Vestuário', 'EXPENSE', 'variable_expense', 'Ambos', '#f472b6', true),
            (v_user_id, 'Salão / Estética', 'EXPENSE', 'occasional', 'Ambos', '#db2777', true),
            -- Outros / Financeiro
            (v_user_id, 'Taxas Bancárias', 'EXPENSE', 'fixed_expense', 'Ambos', '#64748b', true),
            (v_user_id, 'Juros', 'EXPENSE', 'fixed_expense', 'Ambos', '#475569', true),
            (v_user_id, 'Presentes / Doações', 'EXPENSE', 'occasional', 'Ambos', '#94a3b8', true)
        ON CONFLICT DO NOTHING;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 13. ROW LEVEL SECURITY (RLS) RESILIENTE PARA AUTH & ANON
-- ============================================================================
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recurring_patterns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.postings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.budgets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_settings_policy" ON public.user_settings;
CREATE POLICY "user_settings_policy" ON public.user_settings
FOR ALL USING (
    auth.uid() IS NULL 
    OR (SELECT auth.uid()) = user_id 
    OR user_id IS NULL 
    OR user_id = '00000000-0000-0000-0000-000000000000'::uuid
) 
WITH CHECK (
    auth.uid() IS NULL 
    OR (SELECT auth.uid()) = user_id 
    OR user_id IS NULL 
    OR user_id = '00000000-0000-0000-0000-000000000000'::uuid
);

DROP POLICY IF EXISTS "accounts_policy" ON public.accounts;
CREATE POLICY "accounts_policy" ON public.accounts
FOR ALL USING (
    auth.uid() IS NULL 
    OR (SELECT auth.uid()) = user_id 
    OR user_id IS NULL 
    OR user_id = '00000000-0000-0000-0000-000000000000'::uuid
) 
WITH CHECK (
    auth.uid() IS NULL 
    OR (SELECT auth.uid()) = user_id 
    OR user_id IS NULL 
    OR user_id = '00000000-0000-0000-0000-000000000000'::uuid
);

DROP POLICY IF EXISTS "recurring_patterns_policy" ON public.recurring_patterns;
CREATE POLICY "recurring_patterns_policy" ON public.recurring_patterns
FOR ALL USING (
    auth.uid() IS NULL 
    OR (SELECT auth.uid()) = user_id 
    OR user_id IS NULL 
    OR user_id = '00000000-0000-0000-0000-000000000000'::uuid
) 
WITH CHECK (
    auth.uid() IS NULL 
    OR (SELECT auth.uid()) = user_id 
    OR user_id IS NULL 
    OR user_id = '00000000-0000-0000-0000-000000000000'::uuid
);

DROP POLICY IF EXISTS "transactions_policy" ON public.transactions;
CREATE POLICY "transactions_policy" ON public.transactions
FOR ALL USING (
    auth.uid() IS NULL 
    OR (SELECT auth.uid()) = user_id 
    OR user_id IS NULL 
    OR user_id = '00000000-0000-0000-0000-000000000000'::uuid
) 
WITH CHECK (
    auth.uid() IS NULL 
    OR (SELECT auth.uid()) = user_id 
    OR user_id IS NULL 
    OR user_id = '00000000-0000-0000-0000-000000000000'::uuid
);

DROP POLICY IF EXISTS "postings_policy" ON public.postings;
CREATE POLICY "postings_policy" ON public.postings
FOR ALL USING (
    auth.uid() IS NULL OR
    EXISTS (
        SELECT 1 FROM public.transactions t 
        WHERE t.id = postings.transaction_id 
          AND ((SELECT auth.uid()) = t.user_id OR t.user_id IS NULL OR t.user_id = '00000000-0000-0000-0000-000000000000'::uuid)
    )
) WITH CHECK (
    auth.uid() IS NULL OR
    EXISTS (
        SELECT 1 FROM public.transactions t 
        WHERE t.id = postings.transaction_id 
          AND ((SELECT auth.uid()) = t.user_id OR t.user_id IS NULL OR t.user_id = '00000000-0000-0000-0000-000000000000'::uuid)
    )
);

DROP POLICY IF EXISTS "budgets_policy" ON public.budgets;
CREATE POLICY "budgets_policy" ON public.budgets
FOR ALL USING (
    auth.uid() IS NULL 
    OR (SELECT auth.uid()) = user_id 
    OR user_id IS NULL 
    OR user_id = '00000000-0000-0000-0000-000000000000'::uuid
) 
WITH CHECK (
    auth.uid() IS NULL 
    OR (SELECT auth.uid()) = user_id 
    OR user_id IS NULL 
    OR user_id = '00000000-0000-0000-0000-000000000000'::uuid
);

DROP POLICY IF EXISTS "investment_valuations_policy" ON public.investment_valuations;
CREATE POLICY "investment_valuations_policy" ON public.investment_valuations
FOR ALL USING (
    auth.uid() IS NULL 
    OR (SELECT auth.uid()) = user_id 
    OR user_id IS NULL 
    OR user_id = '00000000-0000-0000-0000-000000000000'::uuid
) 
WITH CHECK (
    auth.uid() IS NULL 
    OR (SELECT auth.uid()) = user_id 
    OR user_id IS NULL 
    OR user_id = '00000000-0000-0000-0000-000000000000'::uuid
);

-- ============================================================================
-- 14. PERMISSÕES E GRANTS PARA ROLES SUPABASE (AUTHENTICATED & ANON)
-- ============================================================================
GRANT USAGE ON SCHEMA public TO authenticated, anon;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated, anon;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated, anon;
GRANT ALL ON ALL ROUTINES IN SCHEMA public TO authenticated, anon;

-- ============================================================================
-- 15. RPC ANALÍTICA DE RELATÓRIOS E DASHBOARDS (ITEM 12)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_financial_analytics_report(
    p_view_mode TEXT DEFAULT 'ambos',
    p_year INT DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::INT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
BEGIN
    -- Agrupamento e agregação com ponderação de rateio
    WITH weighted_tx AS (
        SELECT 
            t.id,
            t.date,
            t.description,
            t.ownership_type,
            t.titular,
            t.status,
            CASE 
                WHEN p_view_mode = 'owner' THEN 
                    CASE WHEN t.ownership_type = 'owner_only' THEN 1.0 WHEN t.ownership_type = 'shared_50_50' THEN 0.5 ELSE 0.0 END
                WHEN p_view_mode = 'partner' THEN 
                    CASE WHEN t.ownership_type = 'partner_only' THEN 1.0 WHEN t.ownership_type = 'shared_50_50' THEN 0.5 ELSE 0.0 END
                ELSE 1.0
            END AS weight
        FROM public.transactions t
        WHERE EXTRACT(YEAR FROM t.date) = p_year
    ),
    weighted_postings AS (
        SELECT 
            p.id,
            wt.date,
            EXTRACT(MONTH FROM wt.date)::INT AS month_num,
            p.account_id,
            a.name AS account_name,
            a.account_type,
            a.color AS account_color,
            p.amount * wt.weight AS weighted_amount
        FROM public.postings p
        JOIN weighted_tx wt ON p.transaction_id = wt.id
        JOIN public.accounts a ON p.account_id = a.id
        WHERE wt.weight > 0
    ),
    monthly_flow AS (
        SELECT 
            month_num,
            COALESCE(SUM(CASE WHEN account_type = 'REVENUE' THEN ABS(weighted_amount) ELSE 0 END), 0) AS total_revenue,
            COALESCE(SUM(CASE WHEN account_type = 'EXPENSE' THEN ABS(weighted_amount) ELSE 0 END), 0) AS total_expense
        FROM weighted_postings
        GROUP BY month_num
    ),
    category_expenses AS (
        SELECT 
            account_name,
            account_color,
            COALESCE(SUM(ABS(weighted_amount)), 0) AS total_amount
        FROM weighted_postings
        WHERE account_type = 'EXPENSE'
        GROUP BY account_name, account_color
    )
    SELECT jsonb_build_object(
        'year', p_year,
        'view_mode', p_view_mode,
        'monthly_cash_flow', COALESCE((SELECT jsonb_agg(jsonb_build_object('month', month_num, 'revenue', total_revenue, 'expense', total_expense, 'net', total_revenue - total_expense)) FROM monthly_flow), '[]'::jsonb),
        'expenses_by_category', COALESCE((SELECT jsonb_agg(jsonb_build_object('name', account_name, 'color', account_color, 'total', total_amount)) FROM category_expenses), '[]'::jsonb)
    ) INTO v_result;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_financial_analytics_report(TEXT, INT) TO authenticated, anon;
