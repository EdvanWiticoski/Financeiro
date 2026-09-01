-- ============================================================================
-- SCRIPT DE BACKFILL: user_settings.familia_id
-- Finanças Duo - Define a família ativa padrão com base no maior volume de transações
-- ============================================================================

-- 1. Garante que todos os usuários tenham registro na tabela user_settings
INSERT INTO public.user_settings (user_id, created_at, updated_at)
SELECT u.id, now(), now()
FROM public.usuarios u
WHERE NOT EXISTS (
    SELECT 1 FROM public.user_settings us WHERE us.user_id = u.id
);

-- 2. Atualiza user_settings.familia_id onde está NULL
WITH user_family_ranks AS (
    SELECT 
        mf.user_id,
        mf.familia_id,
        COUNT(t.id) AS total_transacoes,
        ROW_NUMBER() OVER (
            PARTITION BY mf.user_id 
            ORDER BY COUNT(t.id) DESC
        ) AS ranking
    FROM public.membros_familia mf
    LEFT JOIN public.transactions t ON t.familia_id = mf.familia_id
    GROUP BY mf.user_id, mf.familia_id
)
UPDATE public.user_settings us
SET familia_id = ufr.familia_id,
    updated_at = now()
FROM user_family_ranks ufr
WHERE us.user_id = ufr.user_id
  AND ufr.ranking = 1
  AND us.familia_id IS NULL;
