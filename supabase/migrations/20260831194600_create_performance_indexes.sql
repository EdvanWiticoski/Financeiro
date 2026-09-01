-- ============================================================================
-- MIGRAÇÃO: ÍNDICES DE PERFORMANCE PARA RLS & QUERIES (CONCURRENTLY)
-- Finanças Duo - Otimização de RLS, Foreign Keys e Ordenação Temporal
-- ============================================================================

-- NOTA: Comandos com CONCURRENTLY devem ser executados fora de blocos BEGIN/COMMIT.

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_accounts_familia_id 
ON public.accounts(familia_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_transactions_familia_id 
ON public.transactions(familia_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_transactions_familia_date 
ON public.transactions(familia_id, date DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_postings_transaction_id 
ON public.postings(transaction_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_budgets_familia_id 
ON public.budgets(familia_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_recurring_patterns_familia_id 
ON public.recurring_patterns(familia_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_investment_valuations_familia_id 
ON public.investment_valuations(familia_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_membros_familia_user_id 
ON public.membros_familia(user_id);
