-- ============================================================================
-- MIGRAÇÃO: CONSTRAINT UNIQUE EM PUBLIC.MEMBROS_FAMILIA (familia_id, user_id)
-- Finanças Duo - Integridade de Membros e Suporte Idempotente a Upserts
-- ============================================================================

BEGIN;

-- 1. Remove eventuais duplicidades mantendo a linha mais antiga / prioritária
DELETE FROM public.membros_familia mf1
USING public.membros_familia mf2
WHERE mf1.familia_id = mf2.familia_id
  AND mf1.user_id = mf2.user_id
  AND mf1.ctid > mf2.ctid;

-- 2. Cria a constraint UNIQUE definitiva em (familia_id, user_id)
ALTER TABLE public.membros_familia
DROP CONSTRAINT IF EXISTS membros_familia_familia_user_unique;

ALTER TABLE public.membros_familia
ADD CONSTRAINT membros_familia_familia_user_unique UNIQUE (familia_id, user_id);

COMMIT;
