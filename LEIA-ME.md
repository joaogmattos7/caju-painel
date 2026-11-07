# Painel Caju: como colocar no ar (Supabase + Cloudflare Pages)

O que você vai precisar: contas no Supabase e na Cloudflare. Separe cerca de 30 a 40 minutos para a primeira configuração.
Os nomes dos menus nos dois sites podem mudar um pouco com o tempo, mas a ideia é a mesma.

## 1. Criar o banco no Supabase
1. Entre em supabase.com, crie a conta e clique em **New project**.
2. Dê um nome (ex.: caju), crie uma senha do banco (guarde) e escolha a região mais perto de você (ex.: São Paulo).
3. Espere o projeto terminar de criar.

## 2. Criar as tabelas e liberar os e-mails
1. Abra o arquivo `supabase.sql` e troque os e-mails de exemplo no bloco `insert into public.allowed_emails` pelos e-mails reais da equipe.
2. No Supabase, vá em **SQL Editor**, cole o arquivo inteiro e clique em **Run**.
3. Deve aparecer "Success". Rode **uma vez só**.
4. Se o painel já estiver configurado e você só estiver atualizando, rode estes comandos no SQL Editor antes de publicar a nova versão:
   ```sql
   alter table public.clients add column if not exists drive_folder_url text;
   alter table public.deliveries add column if not exists publication_date date;
   notify pgrst, 'reload schema';
   ```
   Eles habilitam os links de pastas dos clientes e a data de publicação no calendário, sem alterar os prazos de produção existentes. Podem ser executados mais de uma vez.
   Execute somente esses comandos para uma atualização; não é necessário rodar novamente o arquivo SQL inteiro. A configuração de atualizações em tempo real do arquivo completo também foi ajustada para não tentar adicionar tabelas que já estejam na publicação.
   - Se o calendário continuar sem salvar, confira se a coluna existe no projeto Supabase conectado ao painel:
     ```sql
     select column_name
     from information_schema.columns
     where table_schema = 'public'
       and table_name = 'deliveries'
       and column_name = 'publication_date';
     ```
     Se não retornar uma linha, execute novamente o comando `alter table ... publication_date` no projeto correto. Se retornar uma linha, atualize o cache da API com `notify pgrst, 'reload schema';` e recarregue o painel. O formulário mostra o código e a mensagem de erros retornados pelo Supabase.
5. Para habilitar a página Financeiro em um projeto que já está em uso, abra `supabase.sql`, copie a seção `6) Financeiro: lançamentos e regras usadas apenas para projeção` até o bloco `do $$ ... end $$;` dessa seção, cole no SQL Editor e clique em **Run**. Essa migração pode ser executada mais de uma vez. Faça isso antes de publicar a página nova.
   - Os dados financeiros ficam visíveis e editáveis para todas as contas autorizadas no painel, conforme a escolha da equipe.
   - Se a migração ainda não tiver sido aplicada, a página Financeiro mostrará um aviso em vez de salvar dados incompletos.
6. Para habilitar o novo painel de conteúdo em um projeto já configurado, execute no SQL Editor a seção `7) Conteúdo, tarefas, captação e aniversários` do `supabase.sql`. Ela cria as tabelas compartilhadas, as políticas de acesso por e-mail autorizado e a atualização em tempo real. Pode ser executada mais de uma vez.
   - Execute a migração no mesmo projeto Supabase cuja URL e chave pública estão no `index.html`; recarregue o painel depois.
   - Se a seção 7 não tiver sido aplicada, o painel informa que não conseguiu carregar os dados e orienta a atualização. Não tente contornar esse aviso com armazenamento local.
   - Para atualizar a aba de tarefas, execute novamente a seção 7. A atualização preserva os registros existentes e habilita o status de **ideias e anotações** junto às tarefas abertas, em andamento e concluídas.
7. Para habilitar contatos completos e contratos, execute a seção `8) Clientes: contatos, contratos e receitas mensais vinculadas` do `supabase.sql`. Ela adiciona e-mail e telefone aos clientes e cria os contratos com políticas de acesso e atualização em tempo real. Requer que a seção 6 do Financeiro já tenha sido executada. A seção 8 pode ser executada novamente sem duplicar a migração.
   - Um contrato ativo cria uma receita mensal recorrente no Financeiro. Editar o contrato atualiza a recorrência e ajusta lançamentos futuros em aberto. Ao pausar, o painel pede confirmação e remove os lançamentos futuros ainda em aberto; valores recebidos/pagos permanecem no histórico.
   - Contratos pausados não geram previsão ativa. Para um contrato com data de término, informe o último dia no cadastro para limitar a previsão.
   - As despesas fixas devem ser cadastradas pela ação **Receita/despesa recorrente** no Financeiro, escolhendo **Despesa**. Gere os lançamentos de cada mês e marque-os como pagos para incluí-los no saldo realizado.

## 3. Pegar as duas chaves
1. No Supabase, vá em **Project Settings > API** (ou "API Keys").
2. Copie a **Project URL** e a chave pública (**anon / public**, ou "publishable").
3. Abra o `index.html` num editor de texto e, no começo do bloco `<script>`, troque:
   - `COLE_AQUI_A_URL_DO_PROJETO` pela Project URL completa, incluindo `https://` e `.supabase.co` (ex.: `https://seuprojeto.supabase.co`; não use apenas o identificador do projeto)
   - `COLE_AQUI_A_CHAVE_ANON` pela chave pública
4. **Nunca** use a chave `service_role` aqui. Ela dá acesso total ao banco.

A chave pública pode ficar no site. Quem protege os dados são as regras do passo 2: sem estar na lista de e-mails autorizados, ninguém enxerga nada.

## 4. Publicar no Cloudflare Pages
1. Entre em dash.cloudflare.com e crie a conta.
2. Vá em **Workers & Pages > Create > Pages > Upload assets**, dê um nome ao projeto e arraste a pasta que contém o `index.html`. (Outra opção: **Connect to Git** e escolher este repositório, para publicar a cada commit.)
3. A Cloudflare gera um endereço no formato `https://nome-do-projeto.pages.dev`. Um domínio próprio pode ser ligado em **Custom domains**.

## 5. Avisar o Supabase qual é o endereço do site
1. No Supabase, vá em **Authentication > URL Configuration**.
2. Em **Site URL**, cole o endereço do Cloudflare Pages.
3. Em **Redirect URLs**, adicione o mesmo endereço.
Sem isso, os links dos e-mails de confirmação e de recuperar senha não voltam para o painel.

## 6. Criar as contas
1. Abra o endereço do site e clique em **Criar conta**, usando um dos e-mails autorizados.
2. Confirme pelo e-mail que chegar (olhe também o spam) e entre.
3. A segunda pessoa faz o mesmo com o e-mail dela.
Deixe a confirmação de e-mail do Supabase **ligada** (é o padrão). Ela garante que ninguém crie conta com o e-mail de outra pessoa.

## Dia a dia
- **Banco de pautas**: registre uma ideia, legenda/briefing, formato, cliente e, se desejar, capa e data pretendida.
- **Produção e Aprovação**: avance o conteúdo de ideia para produção, envie para aprovação, aprove ou devolva para ajustes. O cronograma e a prévia do feed usam a data e a capa salvas no conteúdo.
- **Cronograma**: consulte os conteúdos no calendário mensal e use **Datas importantes do mês** para planejar campanhas a partir de datas sazonais brasileiras e internacionais. A lista inclui feriados móveis como Carnaval, Páscoa, Dia das Mães, Dia dos Pais, Black Friday e Cyber Monday; use a opção **Criar pauta** para iniciar uma ideia ligada a uma data. A seleção é uma referência de planejamento e feriados locais podem variar. O painel não publica automaticamente no Instagram nem envia notificações externas.
- **Tendências**: abra as tendências atuais do Brasil ou explore temas globais pelo Google Trends. Pesquise um assunto por região e transforme-o em pauta com o link de referência. Os resultados ao vivo são fornecidos pelo Google em outra aba; o painel não coleta nem apresenta uma lista própria em tempo real. Não é necessário configurar API ou executar migração do banco.
- **Tarefas e anotações / Checklist**: organize a aba em **Para fazer**, **Feitos** e **Ideias e anotações**. Adicione tarefas ou ideias, marque tarefas concluídas, escolha **Em andamento** quando necessário e edite títulos, responsáveis, prazos e anotações. As tarefas com prazo de hoje também aparecem na página principal. As alterações são compartilhadas com a equipe.
- **Captação**: cadastre contatos e atualize a etapa do relacionamento. **Aniversariantes** guarda datas de clientes, equipe e parceiros.
- **Clientes**: cadastre responsável, e-mail, telefone e link da pasta do Drive. No perfil do cliente, alterne entre **Publicações** e **Contrato**. O link externo do contrato pode ser consultado no perfil, e contratos ativos alimentam automaticamente as receitas recorrentes no Financeiro.
- **Financeiro**: contratos ativos aparecem como recorrências de receita. Use **Receita/despesa recorrente** para mensalidades, despesas fixas ou outras entradas previsíveis; gere os lançamentos mensais para registrar recebimentos e pagamentos reais e acompanhar o saldo realizado e projetado.
- Os registros novos são compartilhados entre as contas autorizadas e ficam no Supabase. Para permitir que uma pessoa veja o painel, adicione o e-mail dela à lista `allowed_emails`.
- Os cadastros antigos de clientes, entregas e financeiro permanecem no banco. A tela de Clientes e o Financeiro estão disponíveis no menu do painel.
- Para liberar mais alguém: no SQL Editor, rode `insert into public.allowed_emails values ('novo@exemplo.com');`
- Para tirar o acesso: `delete from public.allowed_emails where email = 'saiu@exemplo.com';`
- Para atualizar o visual do painel depois: edite o `index.html` e envie a pasta de novo no projeto do Cloudflare Pages (**Create deployment**), ou faça um commit no GitHub se o projeto estiver conectado ao repositório.
- O envio de e-mails do Supabase no plano de testes tem limite por hora. Para duas pessoas costuma bastar, mas confira os limites atuais no site deles.
