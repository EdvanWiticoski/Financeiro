// ============================================================================
// FINANÇAS DUO: PROVISIONAMENTO FORÇADO DE USUÁRIOS (seed_auth_admin.js)
// ============================================================================
// Execução: node scripts/seed_auth_admin.js
// Requer: npm install @supabase/supabase-js dotenv

require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = process.env.SUPABASE_URL || process.env.NEXT_PUBLIC_SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error("❌ Erro: Configure SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY no seu arquivo .env");
  process.exit(1);
}

// Inicializa cliente com privilégios de Admin (Bypass de RLS e validações de cliente)
const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: {
    autoRefreshToken: false,
    persistSession: false
  }
});

const USUARIOS_INICIAIS = [
  {
    email: 'teste1@staging.local',
    password: process.env.SEED_DEFAULT_PASSWORD || 'StagingPass_2026!#',
    nome: 'Usuário Staging 1',
    role_familia: 'admin',
    is_super_admin: false
  },
  {
    email: 'teste2@staging.local',
    password: process.env.SEED_DEFAULT_PASSWORD || 'StagingPass_2026!#',
    nome: 'Usuário Staging 2',
    role_familia: 'membro',
    is_super_admin: false
  },
  {
    email: 'admin@staging.local',
    password: process.env.SEED_DEFAULT_PASSWORD || 'StagingPass_2026!#',
    nome: 'Super Administrador Staging',
    role_familia: 'admin',
    is_super_admin: true
  }
];

async function provisionarUsuarios() {
  console.log("🚀 Iniciando provisionamento seguro de usuários de staging/teste...\n");
  const usersMap = {};

  for (const u of USUARIOS_INICIAIS) {
    try {
      const { data: { users }, error: listError } = await supabaseAdmin.auth.admin.listUsers();
      if (listError) throw listError;

      let user = users.find(existing => existing.email.toLowerCase() === u.email.toLowerCase());

      if (user) {
        const { data: updated, error: updateError } = await supabaseAdmin.auth.admin.updateUserById(user.id, {
          password: u.password,
          email_confirm: true,
          user_metadata: { full_name: u.nome }
        });
        if (updateError) throw updateError;
        user = updated.user;
        console.log(`✅ [ATUALIZADO] ${u.nome} (${u.email})`);
      } else {
        const { data: created, error: createError } = await supabaseAdmin.auth.admin.createUser({
          email: u.email,
          password: u.password,
          email_confirm: true,
          user_metadata: { full_name: u.nome }
        });
        if (createError) throw createError;
        user = created.user;
        console.log(`✨ [CRIADO] ${u.nome} (${u.email})`);
      }

      usersMap[u.email] = user;

      await supabaseAdmin.from('usuarios').upsert({
        id: user.id,
        email: u.email,
        nome: u.nome,
        is_super_admin: u.is_super_admin,
        updated_at: new Date().toISOString()
      });

    } catch (err) {
      console.error(`❌ Erro ao processar ${u.email}:`, err.message);
    }
  }

  console.log("\n✅ Provisionamento de contas de teste finalizado com sucesso!");
}

provisionarUsuarios();
