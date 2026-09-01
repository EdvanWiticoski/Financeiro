-- ============================================================================
-- MIGRAÇÃO: DEDUPLICAÇÃO DE CONTAS E CRIAÇÃO DE CONSTRAINT UNIQUE
-- Finanças Duo - Integridade de Plano de Contas Multi-Tenant
-- Garante unicidade de (familia_id, name, account_type)
-- ============================================================================

BEGIN;

-- 1. Cria tabela temporária de mapeamento: conta_duplicada_id -> conta_sobrevivente_id
-- O sobrevivente é a conta mais antiga (menor created_at ou menor id)
CREATE TEMP TABLE accounts_dedup_map AS
WITH ranked_accounts AS (
    SELECT 
        id,
        familia_id,
        name,
        account_type,
        FIRST_VALUE(id) OVER (
            PARTITION BY familia_id, name, account_type 
            ORDER BY created_at ASC, id ASC
        ) AS surviving_id,
        ROW_NUMBER() OVER (
            PARTITION BY familia_id, name, account_type 
            ORDER BY created_at ASC, id ASC
        ) AS rn
    FROM public.accounts
)
SELECT 
    id AS duplicate_id,
    surviving_id
FROM ranked_accounts
WHERE rn > 1;

-- 2. Reponta os lançamentos (postings) para a conta sobrevivente
UPDATE public.postings p
SET account_id = m.surviving_id
FROM accounts_dedup_map m
WHERE p.account_id = m.duplicate_id;

-- 3. Reponta os orçamentos (budgets) para a conta sobrevivente
-- Exclui orçamentos que colidiriam no mesmo ano/mês com a conta sobrevivente
DELETE FROM public.budgets b
WHERE EXISTS (
    SELECT 1 
    FROM accounts_dedup_map m
    JOIN public.budgets existing_b 
      ON existing_b.account_id = m.surviving_id 
     AND existing_b.year = b.year 
     AND existing_b.month = b.month
    WHERE b.account_id = m.duplicate_id
);

UPDATE public.budgets b
SET account_id = m.surviving_id
FROM accounts_dedup_map m
WHERE b.account_id = m.duplicate_id;

-- 4. Reponta reavaliações de investimento (investment_valuations)
UPDATE public.investment_valuations iv
SET account_id = m.surviving_id
FROM accounts_dedup_map m
WHERE iv.account_id = m.duplicate_id;

-- 5. Remove as contas duplicadas que foram unificadas
DELETE FROM public.accounts a
USING accounts_dedup_map m
WHERE a.id = m.duplicate_id;

-- 6. Limpa a tabela temporária
DROP TABLE accounts_dedup_map;

-- 7. Cria a constraint UNIQUE definitiva em public.accounts
ALTER TABLE public.accounts 
DROP CONSTRAINT IF EXISTS accounts_familia_name_type_unique;

ALTER TABLE public.accounts 
ADD CONSTRAINT accounts_familia_name_type_unique 
UNIQUE (familia_id, name, account_type);

COMMIT;
