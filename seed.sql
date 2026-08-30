-- ============================================================================
-- FINANÇAS DUO - SEED MULTI-TENANT E SMART DEFAULTS (seed.sql)
-- ============================================================================

DO $$
DECLARE
    v_user_id UUID := COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid);
    v_fam_id UUID;
    v_acc_checking UUID;
    v_acc_invest UUID;
    v_acc_card UUID;
    v_acc_salary UUID;
    v_acc_rent UUID;
    v_acc_supermarket UUID;
    v_acc_internet UUID;
    v_current_year INT := EXTRACT(YEAR FROM CURRENT_DATE)::INT;
BEGIN
    -- 1. Obter ou Criar Família Principal do Usuário
    SELECT id INTO v_fam_id FROM public.familias WHERE criado_por = v_user_id LIMIT 1;
    
    IF v_fam_id IS NULL THEN
        INSERT INTO public.familias (nome, criado_por)
        VALUES ('Família Edvan & Yasmin', v_user_id)
        RETURNING id INTO v_fam_id;

        INSERT INTO public.membros_familia (familia_id, user_id, papel, nome_exibicao)
        VALUES (v_fam_id, v_user_id, 'admin', 'Edvan')
        ON CONFLICT (familia_id, user_id) DO NOTHING;
    END IF;

    -- 2. Inserir Configurações Padrão de Nomes do Casal
    INSERT INTO public.user_settings (user_id, familia_id, owner_name, partner_name, onboarding_completed, onboarding_decision)
    VALUES (v_user_id, v_fam_id, 'Edvan', 'Yasmin', true, 'smart_defaults')
    ON CONFLICT (user_id) DO UPDATE 
    SET familia_id = v_fam_id, onboarding_completed = true, onboarding_decision = 'smart_defaults', updated_at = now();

    -- 3. Inserir Plano de Contas Completo com Vínculo de Família
    -- ATIVOS
    INSERT INTO public.accounts (user_id, familia_id, name, account_type, subtype, titular, color, is_active)
    VALUES 
        (v_user_id, v_fam_id, 'Conta Corrente Principal', 'ASSET', 'checking', 'Ambos', '#3b82f6', true),
        (v_user_id, v_fam_id, 'Dinheiro na Carteira', 'ASSET', 'cash', 'Ambos', '#10b981', true),
        (v_user_id, v_fam_id, 'Reserva de Emergência', 'ASSET', 'savings', 'Ambos', '#059669', true),
        (v_user_id, v_fam_id, 'Vale Alimentação / Refeição', 'ASSET', 'benefit', 'Ambos', '#14b8a6', true),
        (v_user_id, v_fam_id, 'Investimentos', 'ASSET', 'investment', 'Ambos', '#6366f1', true)
    ON CONFLICT DO NOTHING;

    -- PASSIVOS
    INSERT INTO public.accounts (user_id, familia_id, name, account_type, subtype, titular, color, is_active)
    VALUES 
        (v_user_id, v_fam_id, 'Cartão de Crédito Principal', 'LIABILITY', 'credit_card', 'Ambos', '#ef4444', true),
        (v_user_id, v_fam_id, 'Empréstimo Pessoal', 'LIABILITY', 'loan', 'Ambos', '#f43f5e', true),
        (v_user_id, v_fam_id, 'Financiamento', 'LIABILITY', 'financing', 'Ambos', '#e11d48', true),
        (v_user_id, v_fam_id, 'Contas a Pagar (Terceiros)', 'LIABILITY', 'payable', 'Ambos', '#be123c', true)
    ON CONFLICT DO NOTHING;

    -- RECEITAS
    INSERT INTO public.accounts (user_id, familia_id, name, account_type, subtype, titular, color, is_active)
    VALUES 
        (v_user_id, v_fam_id, 'Salário Principal', 'REVENUE', 'salary', 'Ambos', '#2563eb', true),
        (v_user_id, v_fam_id, 'Rendimentos / Juros', 'REVENUE', 'investment', 'Ambos', '#0d9488', true),
        (v_user_id, v_fam_id, 'Renda Extra / Freelance', 'REVENUE', 'freelance', 'Ambos', '#0284c7', true),
        (v_user_id, v_fam_id, 'Reembolsos', 'REVENUE', 'refund', 'Ambos', '#0891b2', true),
        (v_user_id, v_fam_id, 'Vendas', 'REVENUE', 'sales', 'Ambos', '#0ea5e9', true)
    ON CONFLICT DO NOTHING;

    -- DESPESAS
    INSERT INTO public.accounts (user_id, familia_id, name, account_type, subtype, titular, color, is_active)
    VALUES 
        -- Moradia
        (v_user_id, v_fam_id, 'Aluguel / Prestação', 'EXPENSE', 'fixed_expense', 'Ambos', '#4f46e5', true),
        (v_user_id, v_fam_id, 'Condomínio', 'EXPENSE', 'fixed_expense', 'Ambos', '#4338ca', true),
        (v_user_id, v_fam_id, 'Energia Elétrica', 'EXPENSE', 'fixed_expense', 'Ambos', '#6366f1', true),
        (v_user_id, v_fam_id, 'Água', 'EXPENSE', 'fixed_expense', 'Ambos', '#818cf8', true),
        (v_user_id, v_fam_id, 'Internet', 'EXPENSE', 'fixed_expense', 'Ambos', '#4f46e5', true),
        -- Alimentação
        (v_user_id, v_fam_id, 'Supermercado', 'EXPENSE', 'variable_expense', 'Ambos', '#ea580c', true),
        (v_user_id, v_fam_id, 'Restaurantes / Delivery', 'EXPENSE', 'variable_expense', 'Ambos', '#f97316', true),
        (v_user_id, v_fam_id, 'Padaria / Lanches', 'EXPENSE', 'variable_expense', 'Ambos', '#fb923c', true),
        -- Transporte
        (v_user_id, v_fam_id, 'Combustível', 'EXPENSE', 'variable_expense', 'Ambos', '#ca8a04', true),
        (v_user_id, v_fam_id, 'Aplicativos (Uber/99)', 'EXPENSE', 'variable_expense', 'Ambos', '#eab308', true),
        (v_user_id, v_fam_id, 'Transporte Público', 'EXPENSE', 'variable_expense', 'Ambos', '#facc15', true),
        (v_user_id, v_fam_id, 'Manutenção do Veículo', 'EXPENSE', 'occasional', 'Ambos', '#d97706', true),
        -- Saúde
        (v_user_id, v_fam_id, 'Plano de Saúde', 'EXPENSE', 'fixed_expense', 'Ambos', '#dc2626', true),
        (v_user_id, v_fam_id, 'Farmácia', 'EXPENSE', 'variable_expense', 'Ambos', '#ef4444', true),
        (v_user_id, v_fam_id, 'Consultas / Exames', 'EXPENSE', 'occasional', 'Ambos', '#b91c1c', true),
        -- Lazer
        (v_user_id, v_fam_id, 'Assinaturas (Streaming/Serviços)', 'EXPENSE', 'fixed_expense', 'Ambos', '#8b5cf6', true),
        (v_user_id, v_fam_id, 'Saídas / Bares', 'EXPENSE', 'variable_expense', 'Ambos', '#a855f7', true),
        (v_user_id, v_fam_id, 'Hobbies', 'EXPENSE', 'occasional', 'Ambos', '#7c3aed', true),
        -- Educação
        (v_user_id, v_fam_id, 'Cursos / Mensalidades', 'EXPENSE', 'fixed_expense', 'Ambos', '#0284c7', true),
        (v_user_id, v_fam_id, 'Livros / Materiais', 'EXPENSE', 'occasional', 'Ambos', '#0ea5e9', true),
        -- Cuidados
        (v_user_id, v_fam_id, 'Academia / Esportes', 'EXPENSE', 'fixed_expense', 'Ambos', '#ec4899', true),
        (v_user_id, v_fam_id, 'Vestuário', 'EXPENSE', 'variable_expense', 'Ambos', '#f472b6', true),
        (v_user_id, v_fam_id, 'Salão / Estética', 'EXPENSE', 'occasional', 'Ambos', '#db2777', true),
        -- Outros
        (v_user_id, v_fam_id, 'Taxas Bancárias', 'EXPENSE', 'fixed_expense', 'Ambos', '#64748b', true),
        (v_user_id, v_fam_id, 'Juros', 'EXPENSE', 'fixed_expense', 'Ambos', '#475569', true),
        (v_user_id, v_fam_id, 'Presentes / Doações', 'EXPENSE', 'occasional', 'Ambos', '#94a3b8', true)
    ON CONFLICT DO NOTHING;

    -- Obter IDs para referências
    SELECT id INTO v_acc_checking FROM public.accounts WHERE familia_id = v_fam_id AND name = 'Conta Corrente Principal' LIMIT 1;
    SELECT id INTO v_acc_invest FROM public.accounts WHERE familia_id = v_fam_id AND name = 'Investimentos' LIMIT 1;
    SELECT id INTO v_acc_card FROM public.accounts WHERE familia_id = v_fam_id AND name = 'Cartão de Crédito Principal' LIMIT 1;
    SELECT id INTO v_acc_salary FROM public.accounts WHERE familia_id = v_fam_id AND name = 'Salário Principal' LIMIT 1;
    SELECT id INTO v_acc_rent FROM public.accounts WHERE familia_id = v_fam_id AND name = 'Aluguel / Prestação' LIMIT 1;
    SELECT id INTO v_acc_supermarket FROM public.accounts WHERE familia_id = v_fam_id AND name = 'Supermercado' LIMIT 1;
    SELECT id INTO v_acc_internet FROM public.accounts WHERE familia_id = v_fam_id AND name = 'Internet' LIMIT 1;

    -- 4. Inserir Metas de Orçamento Anuais (ZBB) para todos os 12 meses
    IF v_acc_supermarket IS NOT NULL THEN
        FOR m IN 1..12 LOOP
            INSERT INTO public.budgets (user_id, familia_id, account_id, month, year, budgeted_amount, titular, is_custom_month, is_all_months)
            VALUES (v_user_id, v_fam_id, v_acc_supermarket, m, v_current_year, 1800.00, 'Ambos', false, true)
            ON CONFLICT (familia_id, account_id, month, year) DO NOTHING;
        END LOOP;
    END IF;

    IF v_acc_rent IS NOT NULL THEN
        FOR m IN 1..12 LOOP
            INSERT INTO public.budgets (user_id, familia_id, account_id, month, year, budgeted_amount, titular, is_custom_month, is_all_months)
            VALUES (v_user_id, v_fam_id, v_acc_rent, m, v_current_year, 2500.00, 'Ambos', false, true)
            ON CONFLICT (familia_id, account_id, month, year) DO NOTHING;
        END LOOP;
    END IF;

    IF v_acc_internet IS NOT NULL THEN
        FOR m IN 1..12 LOOP
            INSERT INTO public.budgets (user_id, familia_id, account_id, month, year, budgeted_amount, titular, is_custom_month, is_all_months)
            VALUES (v_user_id, v_fam_id, v_acc_internet, m, v_current_year, 150.00, 'Ambos', false, true)
            ON CONFLICT (familia_id, account_id, month, year) DO NOTHING;
        END LOOP;
    END IF;

    -- 5. Inserir Regra de Recorrência Padrão
    IF v_acc_rent IS NOT NULL AND v_acc_checking IS NOT NULL THEN
        INSERT INTO public.recurring_patterns (user_id, familia_id, description, rrule, template_postings, start_date, titular, ownership_type, active)
        VALUES (
            v_user_id,
            v_fam_id,
            'Aluguel do Apartamento',
            'FREQ=MONTHLY;BYMONTHDAY=10',
            jsonb_build_array(
                jsonb_build_object('account_id', v_acc_rent, 'amount', 2500.00),
                jsonb_build_object('account_id', v_acc_checking, 'amount', -2500.00)
            ),
            CURRENT_DATE,
            'Ambos',
            'shared_50_50',
            true
        )
        ON CONFLICT DO NOTHING;
    END IF;

    -- 6. Inserir Registro Inicial de Valuation de Investimento
    IF v_acc_invest IS NOT NULL THEN
        INSERT INTO public.investment_valuations (user_id, familia_id, account_id, date, previous_amount, new_amount, variation_amount, variation_pct, titular, notes)
        VALUES (
            v_user_id,
            v_fam_id,
            v_acc_invest,
            CURRENT_DATE,
            20000.00,
            23697.00,
            3697.00,
            18.4850,
            'Ambos',
            'Fechamento e consolidação patrimonial da carteira'
        )
        ON CONFLICT DO NOTHING;
    END IF;

END $$;
-- ============================================================================
-- FINANÇAS DUO: PROVISIONAMENTO FORÇADO DE USUÁRIOS NO SQL (SENHA 123)
-- ============================================================================

DO $$
DECLARE
    v_id_edvan UUID;
    v_id_yasmin UUID;
    v_id_admin UUID;
    v_encrypted_pw TEXT := extensions.crypt('123', extensions.gen_salt('bf'));
BEGIN
    -- 1. Cria ou Atualiza Edvan (edvan2108@gmail.com) no auth.users
    SELECT id INTO v_id_edvan FROM auth.users WHERE email = 'edvan2108@gmail.com';
    IF v_id_edvan IS NULL THEN
        INSERT INTO auth.users (id, instance_id, email, encrypted_password, email_confirmed_at, raw_user_meta_data, role, aud, created_at, updated_at)
        VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'edvan2108@gmail.com', v_encrypted_pw, now(), '{"full_name":"Edvan"}'::jsonb, 'authenticated', 'authenticated', now(), now())
        RETURNING id INTO v_id_edvan;
    ELSE
        UPDATE auth.users SET encrypted_password = v_encrypted_pw, email_confirmed_at = now() WHERE id = v_id_edvan;
    END IF;

    -- 2. Cria ou Atualiza Yasmin no auth.users
    SELECT id INTO v_id_yasmin FROM auth.users WHERE email = 'yasmin.inaciomichels@gmail.com';
    IF v_id_yasmin IS NULL THEN
        INSERT INTO auth.users (id, instance_id, email, encrypted_password, email_confirmed_at, raw_user_meta_data, role, aud, created_at, updated_at)
        VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'yasmin.inaciomichels@gmail.com', v_encrypted_pw, now(), '{"full_name":"Yasmin"}'::jsonb, 'authenticated', 'authenticated', now(), now())
        RETURNING id INTO v_id_yasmin;
    ELSE
        UPDATE auth.users SET encrypted_password = v_encrypted_pw, email_confirmed_at = now() WHERE id = v_id_yasmin;
    END IF;

    -- 3. Cria ou Atualiza Super Admin no auth.users
    SELECT id INTO v_id_admin FROM auth.users WHERE email = 'admin@exemplo.com';
    IF v_id_admin IS NULL THEN
        INSERT INTO auth.users (id, instance_id, email, encrypted_password, email_confirmed_at, raw_user_meta_data, role, aud, created_at, updated_at)
        VALUES (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'admin@exemplo.com', v_encrypted_pw, now(), '{"full_name":"Super Administrador"}'::jsonb, 'authenticated', 'authenticated', now(), now())
        RETURNING id INTO v_id_admin;
    ELSE
        UPDATE auth.users SET encrypted_password = v_encrypted_pw, email_confirmed_at = now() WHERE id = v_id_admin;
    END IF;

    -- 4. Atualiza tabela de perfis (public.usuarios)
    INSERT INTO public.usuarios (id, email, nome, is_super_admin) VALUES (v_id_edvan, 'edvan2108@gmail.com', 'Edvan', false) ON CONFLICT (id) DO UPDATE SET is_super_admin = false, nome = 'Edvan', email = 'edvan2108@gmail.com';
    INSERT INTO public.usuarios (id, email, nome, is_super_admin) VALUES (v_id_yasmin, 'yasmin.inaciomichels@gmail.com', 'Yasmin', false) ON CONFLICT (id) DO UPDATE SET is_super_admin = false, nome = 'Yasmin', email = 'yasmin.inaciomichels@gmail.com';
    INSERT INTO public.usuarios (id, email, nome, is_super_admin) VALUES (v_id_admin, 'admin@exemplo.com', 'Super Administrador', true) ON CONFLICT (id) DO UPDATE SET is_super_admin = true, nome = 'Super Administrador';

    -- 5. Executa a migração legada
    PERFORM public.migrar_familia_legada_edvan_yasmin('edvan2108@gmail.com', 'yasmin.inaciomichels@gmail.com');
END $$;
