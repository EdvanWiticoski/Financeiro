# Finanças Duo 💑💰

**Finanças Duo** é um aplicativo comercial de gestão financeira inteligente projetado para casais e famílias. Construído com arquitetura financeira robusta, o sistema utiliza o método de **partidas dobradas (double-entry bookkeeping)**, garantindo integridade contábil estrita, rateio proporcional de despesas, orçamento base zero (ZBB), projeções recorrentes em conformidade com RFC 5545 e isolamento multi-tenant seguro via Row Level Security (RLS) no PostgreSQL/Supabase.

---

## 🌟 Principais Recursos

* **Contabilidade de Partidas Dobradas**: Todo lançamento gera débitos e créditos equilibrados entre contas de Ativo, Passivo, Receitas e Despesas.
* **Rateio de Casal Inteligente (Acerto de Contas)**: Divisão de despesas configurável por lançamento (Individual, 50/50, ou percentual customizado) com compensação líquida automática.
* **Orçamento Base Zero (ZBB)**: Cada real recebido é alocado em envelopes/categorias antes do início do mês com sugestões baseadas no histórico.
* **Motor de Recorrências (RFC 5545)**: Agendamentos recorrentes com projeção precisa de datas (`addMonthsClamped` / regras RRULE) prevenindo estouros no fim do mês (ex: 31 de janeiro → 28 de fevereiro).
* **Gestão de Investimentos**: Registro de aportes e reavaliações periódicas com acompanhamento de patrimônio líquido e rentabilidade.
* **Segurança & Multi-Tenant**: Isolamento estrito por `familia_id` via Supabase RLS, controle de privilégios de Super Admin e monitoramento de erros via Sentry.

---

## ⚙️ Variáveis de Ambiente

As configurações de conexão com o Supabase utilizam as variáveis de ambiente descritas no modelo [`.env.example`](.env.example):

```env
# URL do seu projeto no Supabase
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_URL=https://your-project.supabase.co
SUPABASE_URL=https://your-project.supabase.co

# Chave Pública Anônima (Anon Key)
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key-here
VITE_SUPABASE_ANON_KEY=your-anon-key-here
SUPABASE_ANON_KEY=your-anon-key-here
```

> [!IMPORTANT]
> Nunca versione o arquivo `.env` com chaves reais. Mantenha as credenciais apenas em seu ambiente local ou configuradas no painel da Vercel / plataforma de hospedagem.

---

## 🚀 Como Rodar Localmente

Como a aplicação é uma Single Page Application (SPA), você pode executá-la utilizando qualquer servidor HTTP estático:

### Opção 1: Usando Node.js / `npx serve`
```bash
npx serve . -l 3000
```
Acesse `http://localhost:3000` no seu navegador.

### Opção 2: Usando Python 3
```bash
python -m http.server 3000
```
Acesse `http://localhost:3000`.

### Opção 3: Usando a extensão Live Server (VS Code)
1. Abra o diretório do projeto no VS Code.
2. Clique com o botão direito em `index.html` e selecione **"Open with Live Server"**.

---

## 🗄️ Como Aplicar as Migrações do Supabase

### 1. Aplicando o Schema do Banco (`schema.sql`)
1. Acesse o **Supabase Dashboard** ➔ seu projeto.
2. No menu lateral, vá em **SQL Editor**.
3. Abra o arquivo [`schema.sql`](schema.sql), copie todo o conteúdo e cole no editor.
4. Clique em **Run** para criar as tabelas, índices, triggers de atualização, funções `SECURITY DEFINER` e políticas RLS.

### 2. Aplicando Dados Iniciais (`seed.sql`)
O script [`seed.sql`](seed.sql) contém categorias pré-configuradas e dados de teste.
* ⚠️ **Requisito de Segurança**: O script de seed deve ser executado em uma sessão autenticada (onde `auth.uid()` é válido). Caso seja executado sem autenticação, o script emitirá uma exceção explícita para evitar registros órfãos.

---

## 🛡️ Arquitetura de Segurança & Armazenamento

* **Autenticação**: Gerenciada pelo Supabase Auth (GoTrue), com rate limit nativo por IP e proteção contra força bruta no servidor.
* **Row Level Security (RLS)**: Cada consulta aos dados financeiros é isolada pelo `familia_id` do usuário conectado.
* **Storage de Avatares**: O bucket `avatars` é configurado como público exclusivamente para fotos de perfil organizadas pelo UID do usuário (`{auth.uid()}/avatar.png`). Novos buckets contendo dados sensíveis ou comprovantes devem ser criados como **privados** com acesso via URLs assinadas.
