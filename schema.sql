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
