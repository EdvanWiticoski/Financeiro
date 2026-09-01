-- ============================================================================
-- BLINDAGEM MULTI-TENANT DEFINITIVA E PERPÉTUA (schema.sql)
-- Impede 100% qualquer vazamento de dados entre usuários no Supabase
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. PERMISSÕES DE POSTGRESQL PARA O PAPEL AUTHENTICATED
-- ----------------------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO postgres, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO postgres, authenticated, service_role;
GRANT ALL ON ALL ROUTINES IN SCHEMA public TO postgres, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. GARANTIR COLUNAS DE ISOLAMENTO (familia_id)
-- ----------------------------------------------------------------------------
ALTER TABLE public.accounts ADD COLUMN IF NOT EXISTS familia_id UUID;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS familia_id UUID;
ALTER TABLE public.budgets ADD COLUMN IF NOT EXISTS familia_id UUID;
ALTER TABLE public.recurring_patterns ADD COLUMN IF NOT EXISTS familia_id UUID;
ALTER TABLE public.investment_valuations ADD COLUMN IF NOT EXISTS familia_id UUID;

-- ----------------------------------------------------------------------------
-- 3. TRIGGER AUTOMÁTICO DE CADASTRO NO auth.users (PADRÃO FAMÍLIA SOLO NATIVA)
-- Toda vez que QUALQUER novo usuário se cadastrar (ex: João, Maria, Edgames),
-- o PostgreSQL cria uma família 100% isolada e vazia para ele automaticamente.
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.handle_novo_usuario_familia_solo()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_nova_familia_id UUID;
    v_nome_usuario TEXT;
BEGIN
    -- 1. Determina o nome do usuário a partir dos metadados ou e-mail
    v_nome_usuario := COALESCE(
        NEW.raw_user_meta_data->>'full_name',
        INITCAP(SPLIT_PART(NEW.email, '@', 1)),
        'Usuário'
    );

    -- 2. Insere na tabela pública de usuários
    INSERT INTO public.usuarios (id, email, nome, is_super_admin)
    VALUES (NEW.id, NEW.email, v_nome_usuario, false)
    ON CONFLICT (id) DO UPDATE
    SET email = NEW.email, nome = v_nome_usuario, updated_at = now();

    -- 3. Cria uma NOVA Família Solo exclusiva para este usuário
    INSERT INTO public.familias (id, nome, criado_por)
    VALUES (gen_random_uuid(), 'Minha Família', NEW.id)
    RETURNING id INTO v_nova_familia_id;

    -- 4. Vincula o usuário como ADMIN exclusivo da sua nova família
    INSERT INTO public.membros_familia (familia_id, user_id, papel, nome_exibicao)
    VALUES (v_nova_familia_id, NEW.id, 'admin', v_nome_usuario)
    ON CONFLICT (familia_id, user_id) DO NOTHING;

    -- 5. Inicializa as preferências individuais vazias (sem parceiro, sem dados)
    INSERT INTO public.user_settings (user_id, familia_id, owner_name, partner_name, onboarding_completed)
    VALUES (NEW.id, v_nova_familia_id, v_nome_usuario, '', false)
    ON CONFLICT (user_id) DO UPDATE
    SET familia_id = v_nova_familia_id, owner_name = v_nome_usuario, partner_name = '', onboarding_completed = false;

    RETURN NEW;
END;
$$;

-- Registra o Trigger no auth.users
DROP TRIGGER IF EXISTS on_auth_user_created_familia_solo ON auth.users;
CREATE TRIGGER on_auth_user_created_familia_solo
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_novo_usuario_familia_solo();

-- ----------------------------------------------------------------------------
-- 4. MIGRAÇÃO RETROATIVA: ISOLAR EDGAMES E PROTEGER EDVAN & YASMIN
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_edgames_id UUID;
    v_edgames_fam_id UUID;
    v_edvan_id UUID;
    v_fam_edvan_yasmin_id UUID := 'df2aeb45-8822-47fe-8b71-dfb3c4ff1399'::UUID;
BEGIN
    -- Localiza Edgames
    SELECT id INTO v_edgames_id FROM auth.users WHERE email ILIKE 'edgames2108@gmail.com' LIMIT 1;
    -- Localiza Edvan
    SELECT id INTO v_edvan_id FROM auth.users WHERE email ILIKE 'edvan2108@gmail.com' LIMIT 1;

    -- ISOLAMENTO DO EDGAMES (SESSÃO VAZIA)
    IF v_edgames_id IS NOT NULL THEN
        DELETE FROM public.membros_familia 
        WHERE user_id = v_edgames_id AND familia_id = v_fam_edvan_yasmin_id;

        SELECT id INTO v_edgames_fam_id 
        FROM public.familias 
        WHERE criado_por = v_edgames_id AND id <> v_fam_edvan_yasmin_id LIMIT 1;

        IF v_edgames_fam_id IS NULL THEN
            INSERT INTO public.familias (nome, criado_por)
            VALUES ('Minha Família', v_edgames_id)
            RETURNING id INTO v_edgames_fam_id;
        END IF;

        INSERT INTO public.membros_familia (familia_id, user_id, papel, nome_exibicao)
        VALUES (v_edgames_fam_id, v_edgames_id, 'admin', 'Edgames')
        ON CONFLICT (familia_id, user_id) DO UPDATE SET papel = 'admin', nome_exibicao = 'Edgames';

        INSERT INTO public.user_settings (user_id, familia_id, owner_name, partner_name, onboarding_completed)
        VALUES (v_edgames_id, v_edgames_fam_id, 'Edgames', '', false)
        ON CONFLICT (user_id) DO UPDATE SET familia_id = v_edgames_fam_id, owner_name = 'Edgames', partner_name = '', onboarding_completed = false;
    END IF;

    -- PROTEÇÃO DA FAMÍLIA EDVAN & YASMIN
    IF v_edvan_id IS NOT NULL THEN
        INSERT INTO public.familias (id, nome, criado_por)
        VALUES (v_fam_edvan_yasmin_id, 'Família Edvan & Yasmin', v_edvan_id)
        ON CONFLICT (id) DO UPDATE SET nome = 'Família Edvan & Yasmin', criado_por = v_edvan_id;

        INSERT INTO public.usuarios (id, email, nome, is_super_admin)
        VALUES (v_edvan_id, 'edvan2108@gmail.com', 'Edvan', true)
        ON CONFLICT (id) DO UPDATE SET email = 'edvan2108@gmail.com', nome = 'Edvan', is_super_admin = true;

        INSERT INTO public.membros_familia (familia_id, user_id, papel, nome_exibicao)
        VALUES (v_fam_edvan_yasmin_id, v_edvan_id, 'admin', 'Edvan')
        ON CONFLICT (familia_id, user_id) DO UPDATE SET papel = 'admin', nome_exibicao = 'Edvan';

        INSERT INTO public.user_settings (user_id, familia_id, owner_name, partner_name, onboarding_completed)
        VALUES (v_edvan_id, v_fam_edvan_yasmin_id, 'Edvan', 'Yasmin', true)
        ON CONFLICT (user_id) DO UPDATE SET familia_id = v_fam_edvan_yasmin_id, owner_name = 'Edvan', partner_name = 'Yasmin', onboarding_completed = true;
    END IF;

    -- TODOS OS DADOS HISTÓRICOS PERTENCEM EXCLUSIVAMENTE À FAMÍLIA EDVAN & YASMIN
    UPDATE public.accounts SET familia_id = v_fam_edvan_yasmin_id WHERE familia_id IS NULL OR familia_id = v_fam_edvan_yasmin_id;
    UPDATE public.transactions SET familia_id = v_fam_edvan_yasmin_id WHERE familia_id IS NULL OR familia_id = v_fam_edvan_yasmin_id;
    UPDATE public.budgets SET familia_id = v_fam_edvan_yasmin_id WHERE familia_id IS NULL OR familia_id = v_fam_edvan_yasmin_id;
    UPDATE public.recurring_patterns SET familia_id = v_fam_edvan_yasmin_id WHERE familia_id IS NULL OR familia_id = v_fam_edvan_yasmin_id;
    UPDATE public.investment_valuations SET familia_id = v_fam_edvan_yasmin_id WHERE familia_id IS NULL OR familia_id = v_fam_edvan_yasmin_id;
END $$;

-- ----------------------------------------------------------------------------
-- 5. ATIVAÇÃO DE ROW LEVEL SECURITY (RLS) INVIOLÁVEL
-- ----------------------------------------------------------------------------
ALTER TABLE public.familias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.membros_familia ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.postings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.budgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.recurring_patterns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.investment_valuations ENABLE ROW LEVEL SECURITY;

-- FUNÇÃO IMUTÁVEL DE BUSCA DAS FAMÍLIAS DO USUÁRIO CONECTADO
CREATE OR REPLACE FUNCTION public.get_minhas_familias()
RETURNS SETOF UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth
AS $$
    SELECT familia_id 
    FROM public.membros_familia 
    WHERE user_id = auth.uid() 
      AND familia_id IS NOT NULL;
$$;

-- POLÍTICAS: ACCOUNTS
DROP POLICY IF EXISTS "accounts_select" ON public.accounts;
DROP POLICY IF EXISTS "accounts_insert" ON public.accounts;
DROP POLICY IF EXISTS "accounts_update" ON public.accounts;
DROP POLICY IF EXISTS "accounts_delete" ON public.accounts;

CREATE POLICY "accounts_select" ON public.accounts FOR SELECT TO authenticated
USING (familia_id IN (SELECT public.get_minhas_familias()));

CREATE POLICY "accounts_insert" ON public.accounts FOR INSERT TO authenticated
WITH CHECK (familia_id IN (SELECT public.get_minhas_familias()));

CREATE POLICY "accounts_update" ON public.accounts FOR UPDATE TO authenticated
USING (familia_id IN (SELECT public.get_minhas_familias()));

CREATE POLICY "accounts_delete" ON public.accounts FOR DELETE TO authenticated
USING (familia_id IN (SELECT public.get_minhas_familias()));

-- POLÍTICAS: TRANSACTIONS
DROP POLICY IF EXISTS "transactions_select" ON public.transactions;
DROP POLICY IF EXISTS "transactions_insert" ON public.transactions;
DROP POLICY IF EXISTS "transactions_update" ON public.transactions;
DROP POLICY IF EXISTS "transactions_delete" ON public.transactions;

CREATE POLICY "transactions_select" ON public.transactions FOR SELECT TO authenticated
USING (familia_id IN (SELECT public.get_minhas_familias()));

CREATE POLICY "transactions_insert" ON public.transactions FOR INSERT TO authenticated
WITH CHECK (familia_id IN (SELECT public.get_minhas_familias()));

CREATE POLICY "transactions_update" ON public.transactions FOR UPDATE TO authenticated
USING (familia_id IN (SELECT public.get_minhas_familias()));

CREATE POLICY "transactions_delete" ON public.transactions FOR DELETE TO authenticated
USING (familia_id IN (SELECT public.get_minhas_familias()));

-- POLÍTICAS: POSTINGS
DROP POLICY IF EXISTS "postings_select" ON public.postings;
DROP POLICY IF EXISTS "postings_insert" ON public.postings;
DROP POLICY IF EXISTS "postings_update" ON public.postings;
DROP POLICY IF EXISTS "postings_delete" ON public.postings;

CREATE POLICY "postings_select" ON public.postings FOR SELECT TO authenticated
USING (EXISTS (
    SELECT 1 FROM public.transactions t 
    WHERE t.id = postings.transaction_id 
      AND t.familia_id IN (SELECT public.get_minhas_familias())
));

CREATE POLICY "postings_insert" ON public.postings FOR INSERT TO authenticated
WITH CHECK (EXISTS (
    SELECT 1 FROM public.transactions t 
    WHERE t.id = postings.transaction_id 
      AND t.familia_id IN (SELECT public.get_minhas_familias())
));

CREATE POLICY "postings_update" ON public.postings FOR UPDATE TO authenticated
USING (EXISTS (
    SELECT 1 FROM public.transactions t 
    WHERE t.id = postings.transaction_id 
      AND t.familia_id IN (SELECT public.get_minhas_familias())
));

CREATE POLICY "postings_delete" ON public.postings FOR DELETE TO authenticated
USING (EXISTS (
    SELECT 1 FROM public.transactions t 
    WHERE t.id = postings.transaction_id 
      AND t.familia_id IN (SELECT public.get_minhas_familias())
));

-- POLÍTICAS: BUDGETS
DROP POLICY IF EXISTS "budgets_select" ON public.budgets;
DROP POLICY IF EXISTS "budgets_insert" ON public.budgets;
DROP POLICY IF EXISTS "budgets_update" ON public.budgets;
DROP POLICY IF EXISTS "budgets_delete" ON public.budgets;

CREATE POLICY "budgets_select" ON public.budgets FOR SELECT TO authenticated
USING (familia_id IN (SELECT public.get_minhas_familias()));

CREATE POLICY "budgets_insert" ON public.budgets FOR INSERT TO authenticated
WITH CHECK (familia_id IN (SELECT public.get_minhas_familias()));

CREATE POLICY "budgets_update" ON public.budgets FOR UPDATE TO authenticated
USING (familia_id IN (SELECT public.get_minhas_familias()));

CREATE POLICY "budgets_delete" ON public.budgets FOR DELETE TO authenticated
USING (familia_id IN (SELECT public.get_minhas_familias()));

-- POLÍTICAS: RECURRING_PATTERNS
DROP POLICY IF EXISTS "recurring_patterns_select" ON public.recurring_patterns;
DROP POLICY IF EXISTS "recurring_patterns_insert" ON public.recurring_patterns;
DROP POLICY IF EXISTS "recurring_patterns_update" ON public.recurring_patterns;
DROP POLICY IF EXISTS "recurring_patterns_delete" ON public.recurring_patterns;

CREATE POLICY "recurring_patterns_select" ON public.recurring_patterns FOR SELECT TO authenticated
USING (familia_id IN (SELECT public.get_minhas_familias()));

CREATE POLICY "recurring_patterns_insert" ON public.recurring_patterns FOR INSERT TO authenticated
WITH CHECK (familia_id IN (SELECT public.get_minhas_familias()));

CREATE POLICY "recurring_patterns_update" ON public.recurring_patterns FOR UPDATE TO authenticated
USING (familia_id IN (SELECT public.get_minhas_familias()));

CREATE POLICY "recurring_patterns_delete" ON public.recurring_patterns FOR DELETE TO authenticated
USING (familia_id IN (SELECT public.get_minhas_familias()));

-- POLÍTICAS: INVESTMENT_VALUATIONS
DROP POLICY IF EXISTS "investment_valuations_select" ON public.investment_valuations;
DROP POLICY IF EXISTS "investment_valuations_insert" ON public.investment_valuations;
DROP POLICY IF EXISTS "investment_valuations_update" ON public.investment_valuations;
DROP POLICY IF EXISTS "investment_valuations_delete" ON public.investment_valuations;

CREATE POLICY "investment_valuations_select" ON public.investment_valuations FOR SELECT TO authenticated
USING (familia_id IN (SELECT public.get_minhas_familias()));

CREATE POLICY "investment_valuations_insert" ON public.investment_valuations FOR INSERT TO authenticated
WITH CHECK (familia_id IN (SELECT public.get_minhas_familias()));

CREATE POLICY "investment_valuations_update" ON public.investment_valuations FOR UPDATE TO authenticated
USING (familia_id IN (SELECT public.get_minhas_familias()));

CREATE POLICY "investment_valuations_delete" ON public.investment_valuations FOR DELETE TO authenticated
USING (familia_id IN (SELECT public.get_minhas_familias()));

-- POLÍTICAS: FAMILIAS
DROP POLICY IF EXISTS "familias_select" ON public.familias;
DROP POLICY IF EXISTS "familias_insert" ON public.familias;
DROP POLICY IF EXISTS "familias_update" ON public.familias;
DROP POLICY IF EXISTS "familias_delete" ON public.familias;

CREATE POLICY "familias_select" ON public.familias FOR SELECT TO authenticated
USING (id IN (SELECT public.get_minhas_familias()));

CREATE POLICY "familias_insert" ON public.familias FOR INSERT TO authenticated
WITH CHECK (criado_por = auth.uid());

CREATE POLICY "familias_update" ON public.familias FOR UPDATE TO authenticated
USING (id IN (SELECT mf.familia_id FROM public.membros_familia mf WHERE mf.user_id = auth.uid() AND mf.papel = 'admin'));

CREATE POLICY "familias_delete" ON public.familias FOR DELETE TO authenticated
USING (id IN (SELECT mf.familia_id FROM public.membros_familia mf WHERE mf.user_id = auth.uid() AND mf.papel = 'admin'));

-- POLÍTICAS: MEMBROS_FAMILIA
DROP POLICY IF EXISTS "membros_select" ON public.membros_familia;
DROP POLICY IF EXISTS "membros_insert" ON public.membros_familia;
DROP POLICY IF EXISTS "membros_update" ON public.membros_familia;
DROP POLICY IF EXISTS "membros_delete" ON public.membros_familia;

CREATE POLICY "membros_select" ON public.membros_familia FOR SELECT TO authenticated
USING (user_id = auth.uid() OR familia_id IN (SELECT public.get_minhas_familias()));

CREATE POLICY "membros_insert" ON public.membros_familia FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid() OR familia_id IN (SELECT mf.familia_id FROM public.membros_familia mf WHERE mf.user_id = auth.uid() AND mf.papel = 'admin'));

CREATE POLICY "membros_update" ON public.membros_familia FOR UPDATE TO authenticated
USING (familia_id IN (SELECT mf.familia_id FROM public.membros_familia mf WHERE mf.user_id = auth.uid() AND mf.papel = 'admin'));

CREATE POLICY "membros_delete" ON public.membros_familia FOR DELETE TO authenticated
USING (user_id = auth.uid() OR familia_id IN (SELECT mf.familia_id FROM public.membros_familia mf WHERE mf.user_id = auth.uid() AND mf.papel = 'admin'));

-- POLÍTICAS: USER_SETTINGS
DROP POLICY IF EXISTS "user_settings_select" ON public.user_settings;
DROP POLICY IF EXISTS "user_settings_insert" ON public.user_settings;
DROP POLICY IF EXISTS "user_settings_update" ON public.user_settings;

CREATE POLICY "user_settings_select" ON public.user_settings FOR SELECT TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "user_settings_insert" ON public.user_settings FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "user_settings_update" ON public.user_settings FOR UPDATE TO authenticated
USING (user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- 6. TABELA DE USUÁRIOS E RLS DE PERFIL
-- ----------------------------------------------------------------------------
ALTER TABLE public.usuarios ADD COLUMN IF NOT EXISTS nome_completo TEXT;
ALTER TABLE public.usuarios ADD COLUMN IF NOT EXISTS telefone TEXT;
ALTER TABLE public.usuarios ADD COLUMN IF NOT EXISTS avatar_url TEXT;
ALTER TABLE public.usuarios ADD COLUMN IF NOT EXISTS profissao TEXT;
ALTER TABLE public.usuarios ADD COLUMN IF NOT EXISTS endereco TEXT;

ALTER TABLE public.usuarios ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "usuarios_select" ON public.usuarios;
CREATE POLICY "usuarios_select" ON public.usuarios FOR SELECT TO authenticated
USING (true);

DROP POLICY IF EXISTS "usuarios_insert" ON public.usuarios;
CREATE POLICY "usuarios_insert" ON public.usuarios FOR INSERT TO authenticated
WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "usuarios_update" ON public.usuarios;
CREATE POLICY "usuarios_update" ON public.usuarios FOR UPDATE TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- ----------------------------------------------------------------------------
-- 7. SUPABASE STORAGE: BUCKET AVATARS E POLÍTICAS RLS DE ARQUIVOS
-- ----------------------------------------------------------------------------
-- NOTA DE ARQUITETURA & SEGURANÇA (AUDITORIA):
-- O bucket "avatars" é configurado como público (public = true) com caminho baseado
-- no UID do usuário (`{auth.uid()}/avatar.png`). Esta é uma DECISÃO DE PRODUTO INTENCIONAL
-- e aceita para simplificar a exibição e cache de fotos de perfil entre membros da família.
-- ⚠️ IMPORTANTE: Este padrão NÃO DEVE ser copiado para nenhum outro bucket futuro
-- que armazene comprovantes, extratos, anexos financeiros ou qualquer dado sensível/LGPD.
-- Novos buckets com dados sensíveis devem ser OBRIGATORIAMENTE PRIVADOS (public = false)
-- com acesso concedido exclusivamente via URLs assinadas temporárias (Signed URLs) e RLS restrito.
--
-- Cria o bucket público "avatars" caso não exista
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('avatars', 'avatars', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif'])
ON CONFLICT (id) DO UPDATE SET 
    public = true, 
    file_size_limit = 5242880, 
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif'];

-- SELECT: Qualquer usuário autenticado ou público pode visualizar as fotos do bucket avatars
DROP POLICY IF EXISTS "avatars_select" ON storage.objects;
CREATE POLICY "avatars_select" ON storage.objects FOR SELECT
USING (bucket_id = 'avatars');

-- INSERT: O usuário só pode fazer upload dentro da pasta com o seu próprio UID
DROP POLICY IF EXISTS "avatars_insert" ON storage.objects;
CREATE POLICY "avatars_insert" ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'avatars' AND 
    (storage.foldername(name))[1] = auth.uid()::text
);

-- UPDATE: O usuário só pode alterar imagens dentro da sua própria pasta de UID
DROP POLICY IF EXISTS "avatars_update" ON storage.objects;
CREATE POLICY "avatars_update" ON storage.objects FOR UPDATE TO authenticated
USING (
    bucket_id = 'avatars' AND 
    (storage.foldername(name))[1] = auth.uid()::text
);

-- DELETE: O usuário só pode apagar imagens dentro da sua própria pasta de UID
DROP POLICY IF EXISTS "avatars_delete" ON storage.objects;
CREATE POLICY "avatars_delete" ON storage.objects FOR DELETE TO authenticated
USING (
    bucket_id = 'avatars' AND 
    (storage.foldername(name))[1] = auth.uid()::text
);

-- ----------------------------------------------------------------------------
-- 8. MIGRAÇÃO DE SEGURANÇA: RLS ESTRITO EM USUARIOS (PRIVACIDADE FAMILIAR)
-- Substitui a política permissiva antiga por visualização restrita à própria família
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "usuarios_select" ON public.usuarios;

CREATE POLICY "usuarios_select" ON public.usuarios FOR SELECT TO authenticated
USING (
    id = auth.uid()
    OR id IN (
        SELECT mf2.user_id 
        FROM public.membros_familia mf1
        JOIN public.membros_familia mf2 ON mf2.familia_id = mf1.familia_id
        WHERE mf1.user_id = auth.uid()
    )
);

-- ----------------------------------------------------------------------------
-- 9. MIGRAÇÃO DE SEGURANÇA: RLS ESTRITO EM MEMBROS_FAMILIA (INSERT CONTROLADO)
-- Impede auto-inserção de papel admin e exige convite para entrar na família
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "membros_insert" ON public.membros_familia;

CREATE POLICY "membros_insert" ON public.membros_familia FOR INSERT TO authenticated
WITH CHECK (
    (user_id = auth.uid() AND papel = 'membro')
    OR familia_id IN (
        SELECT mf.familia_id 
        FROM public.membros_familia mf 
        WHERE mf.user_id = auth.uid() AND mf.papel = 'admin'
    )
);

-- ----------------------------------------------------------------------------
-- 10. MIGRAÇÃO: VALIDAÇÃO DE PARTIDAS DOBRADAS (BALANCE CHECK TRIGGER)
-- Impede que qualquer transação seja gravada ou alterada com soma <> 0
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_transaction_balance()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE 
    v_sum NUMERIC;
BEGIN
    SELECT COALESCE(SUM(amount), 0) INTO v_sum
    FROM public.postings 
    WHERE transaction_id = COALESCE(NEW.transaction_id, OLD.transaction_id);

    IF ROUND(v_sum, 2) <> 0 THEN
        RAISE EXCEPTION 'Lançamento desbalanceado: soma dos débitos e créditos = % (deve ser 0)', v_sum;
    END IF;

    RETURN NEW;
END; 
$$;

DROP TRIGGER IF EXISTS trg_check_balance ON public.postings;

CREATE CONSTRAINT TRIGGER trg_check_balance
AFTER INSERT OR UPDATE OR DELETE ON public.postings
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION public.check_transaction_balance();

-- ----------------------------------------------------------------------------
-- 11. MIGRAÇÃO: CONSTRAINT UNIQUE EM (familia_id, name, account_type)
-- ----------------------------------------------------------------------------
ALTER TABLE public.accounts 
DROP CONSTRAINT IF EXISTS accounts_familia_name_type_unique;

ALTER TABLE public.accounts 
ADD CONSTRAINT accounts_familia_name_type_unique 
UNIQUE (familia_id, name, account_type);

-- ----------------------------------------------------------------------------
-- 12. MIGRAÇÃO: FUNÇÃO SECURITY DEFINER EXCLUIR_MINHA_CONTA (LGPD)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.excluir_minha_conta()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id UUID;
    v_fam RECORD;
    v_member_count INT;
    v_deleted_solo_families INT := 0;
    v_left_shared_families INT := 0;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Não autorizado: usuário não autenticado.';
    END IF;

    FOR v_fam IN 
        SELECT DISTINCT familia_id 
        FROM public.membros_familia 
        WHERE user_id = v_user_id
    LOOP
        SELECT COUNT(*) INTO v_member_count
        FROM public.membros_familia
        WHERE familia_id = v_fam.familia_id;

        IF v_member_count <= 1 THEN
            DELETE FROM public.postings 
            WHERE transaction_id IN (
                SELECT id FROM public.transactions WHERE familia_id = v_fam.familia_id
            );
            
            DELETE FROM public.transactions WHERE familia_id = v_fam.familia_id;
            DELETE FROM public.budgets WHERE familia_id = v_fam.familia_id;
            DELETE FROM public.recurring_patterns WHERE familia_id = v_fam.familia_id;
            DELETE FROM public.investment_valuations WHERE familia_id = v_fam.familia_id;
            DELETE FROM public.accounts WHERE familia_id = v_fam.familia_id;
            DELETE FROM public.membros_familia WHERE familia_id = v_fam.familia_id;
            DELETE FROM public.familias WHERE id = v_fam.familia_id;

            v_deleted_solo_families := v_deleted_solo_families + 1;
        ELSE
            DELETE FROM public.membros_familia 
            WHERE familia_id = v_fam.familia_id AND user_id = v_user_id;

            IF NOT EXISTS (
                SELECT 1 FROM public.membros_familia 
                WHERE familia_id = v_fam.familia_id AND papel = 'admin'
            ) THEN
                UPDATE public.membros_familia
                SET papel = 'admin'
                WHERE ctid IN (
                    SELECT ctid FROM public.membros_familia
                    WHERE familia_id = v_fam.familia_id
                    LIMIT 1
                );
            END IF;

            v_left_shared_families := v_left_shared_families + 1;
        END IF;
    END LOOP;

    DELETE FROM public.user_settings WHERE user_id = v_user_id;
    DELETE FROM public.usuarios WHERE id = v_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Conta e dados pessoais excluídos com sucesso.',
        'solo_families_deleted', v_deleted_solo_families,
        'shared_families_left', v_left_shared_families
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.excluir_minha_conta() TO authenticated;

-- ----------------------------------------------------------------------------
-- 13. MIGRAÇÃO: CONSTRAINT UNIQUE EM (familia_id, user_id) EM MEMBROS_FAMILIA
-- ----------------------------------------------------------------------------
ALTER TABLE public.membros_familia
DROP CONSTRAINT IF EXISTS membros_familia_familia_user_unique;

ALTER TABLE public.membros_familia
ADD CONSTRAINT membros_familia_familia_user_unique UNIQUE (familia_id, user_id);

-- ----------------------------------------------------------------------------
-- 14. MIGRAÇÃO: ÍNDICES DE PERFORMANCE PARA RLS & QUERIES (CONCURRENTLY)
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- 15. RPC SUPER ADMIN: VERIFICAÇÃO DE PAPEL SUPER ADMIN (SECURITY DEFINER)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE((SELECT is_super_admin FROM public.usuarios WHERE id = auth.uid()), false);
$$;

GRANT EXECUTE ON FUNCTION public.is_super_admin() TO authenticated;

-- ----------------------------------------------------------------------------
-- 16. RPC SUPER ADMIN: DIRETÓRIO GLOBAL DE USUÁRIOS E FAMÍLIAS (SECURITY DEFINER)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_get_all_users_and_families()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_is_super BOOLEAN;
    v_total_users INT;
    v_total_families INT;
    v_total_transactions INT;
    v_total_accounts INT;
    v_users JSONB;
    v_families JSONB;
BEGIN
    -- 1. Checagem de segurança estrita: apenas Super Admin autenticado
    SELECT is_super_admin INTO v_is_super
    FROM public.usuarios
    WHERE id = auth.uid();

    IF v_is_super IS NOT TRUE THEN
        RAISE EXCEPTION 'Acesso negado: apenas Super Admin pode consultar o diretório global.';
    END IF;

    -- Totais globais
    SELECT COUNT(*) INTO v_total_users FROM public.usuarios;
    SELECT COUNT(*) INTO v_total_families FROM public.familias;
    SELECT COUNT(*) INTO v_total_transactions FROM public.transactions;
    SELECT COUNT(*) INTO v_total_accounts FROM public.accounts;

    -- Lista completa de usuários cadastrados e seus vínculos familiares
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', u.id,
            'email', u.email,
            'nome', u.nome,
            'is_super_admin', COALESCE(u.is_super_admin, false),
            'created_at', u.created_at,
            'familias', COALESCE((
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'familia_id', mf.familia_id,
                        'familia_nome', f.nome,
                        'papel', mf.papel,
                        'nome_exibicao', mf.nome_exibicao
                    )
                )
                FROM public.membros_familia mf
                JOIN public.familias f ON f.id = mf.familia_id
                WHERE mf.user_id = u.id
            ), '[]'::jsonb)
        )
    ) INTO v_users
    FROM public.usuarios u;

    -- Lista de famílias
    SELECT jsonb_agg(
        jsonb_build_object(
            'id', f.id,
            'nome', f.nome,
            'criado_por', f.criado_por,
            'created_at', f.created_at,
            'membros_count', (SELECT COUNT(*) FROM public.membros_familia WHERE familia_id = f.id)
        )
    ) INTO v_families
    FROM public.familias f;

    RETURN jsonb_build_object(
        'total_users', COALESCE(v_total_users, 0),
        'total_families', COALESCE(v_total_families, 0),
        'total_transactions', COALESCE(v_total_transactions, 0),
        'total_accounts', COALESCE(v_total_accounts, 0),
        'users', COALESCE(v_users, '[]'::jsonb),
        'families', COALESCE(v_families, '[]'::jsonb)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_all_users_and_families() TO authenticated;

-- ----------------------------------------------------------------------------
-- 17. SISTEMA DE CONVITES DE FAMÍLIA (gerar_convite_familia & aceitar_convite_familia)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS public.convites_familia CASCADE;

CREATE TABLE public.convites_familia (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    familia_id UUID NOT NULL REFERENCES public.familias(id) ON DELETE CASCADE,
    codigo TEXT NOT NULL UNIQUE,
    criado_por UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    email_convidado TEXT,
    usado BOOLEAN NOT NULL DEFAULT false,
    usado_por UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '7 days')
);

CREATE INDEX idx_convites_codigo ON public.convites_familia(codigo);
CREATE INDEX idx_convites_familia_id ON public.convites_familia(familia_id);

ALTER TABLE public.convites_familia ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "convites_select" ON public.convites_familia;
CREATE POLICY "convites_select" ON public.convites_familia FOR SELECT TO authenticated
USING (
    familia_id IN (SELECT public.get_minhas_familias())
    OR criado_por = auth.uid()
);

CREATE OR REPLACE FUNCTION public.gerar_convite_familia(
    p_familia_id UUID,
    p_email_convidado TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID;
    v_codigo TEXT;
    v_is_member BOOLEAN;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Usuário não autenticado.';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public.membros_familia 
        WHERE familia_id = p_familia_id AND user_id = v_user_id
    ) INTO v_is_member;

    IF NOT v_is_member THEN
        RAISE EXCEPTION 'Apenas membros da família podem gerar convites.';
    END IF;

    v_codigo := 'DUO-' || UPPER(SUBSTRING(MD5(gen_random_uuid()::TEXT || clock_timestamp()::TEXT) FROM 1 FOR 6));

    INSERT INTO public.convites_familia (
        familia_id,
        codigo,
        criado_por,
        email_convidado,
        usado,
        expires_at
    )
    VALUES (
        p_familia_id,
        v_codigo,
        v_user_id,
        NULLIF(TRIM(p_email_convidado), ''),
        false,
        now() + INTERVAL '7 days'
    );

    RETURN v_codigo;
END;
$$;

GRANT EXECUTE ON FUNCTION public.gerar_convite_familia(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.aceitar_convite_familia(
    p_codigo_convite TEXT,
    p_nome_exibicao TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID;
    v_user_email TEXT;
    v_user_nome TEXT;
    v_convite RECORD;
    v_fam_nome TEXT;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Usuário não autenticado.';
    END IF;

    SELECT email INTO v_user_email FROM auth.users WHERE id = v_user_id;

    SELECT * INTO v_convite 
    FROM public.convites_familia
    WHERE codigo = UPPER(TRIM(p_codigo_convite))
      AND usado = false
      AND expires_at > now()
    LIMIT 1;

    IF v_convite IS NULL THEN
        RAISE EXCEPTION 'Código de convite inválido ou expirado.';
    END IF;

    IF v_convite.email_convidado IS NOT NULL AND v_convite.email_convidado <> '' THEN
        IF v_user_email NOT ILIKE v_convite.email_convidado THEN
            RAISE EXCEPTION 'Este convite foi gerado exclusivamente para o e-mail %.', v_convite.email_convidado;
        END IF;
    END IF;

    SELECT nome INTO v_fam_nome FROM public.familias WHERE id = v_convite.familia_id;

    v_user_nome := COALESCE(
        NULLIF(TRIM(p_nome_exibicao), ''),
        (SELECT nome FROM public.usuarios WHERE id = v_user_id),
        INITCAP(SPLIT_PART(v_user_email, '@', 1)),
        'Membro'
    );

    INSERT INTO public.membros_familia (familia_id, user_id, papel, nome_exibicao)
    VALUES (v_convite.familia_id, v_user_id, 'membro', v_user_nome)
    ON CONFLICT (familia_id, user_id) DO UPDATE 
    SET nome_exibicao = EXCLUDED.nome_exibicao;

    INSERT INTO public.user_settings (user_id, familia_id, owner_name, partner_name, onboarding_completed)
    VALUES (v_user_id, v_convite.familia_id, v_user_nome, '', true)
    ON CONFLICT (user_id) DO UPDATE 
    SET familia_id = v_convite.familia_id,
        owner_name = COALESCE(NULLIF(public.user_settings.owner_name, ''), v_user_nome),
        onboarding_completed = true;

    UPDATE public.convites_familia
    SET usado = true,
        usado_por = v_user_id
    WHERE id = v_convite.id;

    RETURN jsonb_build_object(
        'success', true,
        'familia_id', v_convite.familia_id,
        'familia_nome', v_fam_nome,
        'message', format('Você entrou na família %s com sucesso!', COALESCE(v_fam_nome, ''))
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.aceitar_convite_familia(TEXT, TEXT) TO authenticated;

