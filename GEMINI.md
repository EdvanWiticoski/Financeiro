Este é o Finanças Duo, um app comercial de gestão financeira para casais/famílias (React + Supabase). Este projeto está passando por uma auditoria de segurança e qualidade — uma lista de correções está sendo aplicada uma de cada vez.

Regras permanentes para qualquer tarefa neste projeto:
- Nunca execute DELETE, DROP, UPDATE em massa, ou qualquer migração SQL contra um banco de dados real (produção ou staging) sem antes me mostrar o comando exato e esperar minha confirmação explícita. Você pode e deve escrever o SQL, só não deve executá-lo sozinho se tiver essa capacidade.
- Nunca reintroduza autorização baseada em comparação de e-mail/nome (.includes(), .startsWith()) — autorização é sempre via RLS do Postgres ou função SECURITY DEFINER no servidor, nunca no cliente.
- O arquivo FINANCAS.html foi unificado no index.html (item 2.3 concluído). Todas as edições agora são feitas exclusivamente no index.html.
- Valide sintaxe (rodando o app localmente ou via um linter) antes de considerar a tarefa concluída.
- Se a tarefa pedir uma decisão de produto/negócio (não só técnica), pare e pergunte antes de implementar.

