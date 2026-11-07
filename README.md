# Painel Caju — gestão interna de agência de marketing

Painel web (login + dados compartilhados em tempo real) que desenvolvi para a **Agência Caju** organizar clientes, produção de conteúdo, contratos e financeiro num só lugar. Além de resolver a operação do dia a dia, ele serve como **camada de coleta de dados**: a ideia é acumular histórico para, no futuro, construir uma pipeline de dados (ingestão → tratamento → indicadores) que ajude a agência a tomar decisões.

> Este repositório é a versão pública do projeto: chaves, URLs do banco e e-mails reais foram substituídos por placeholders.

## Funcionalidades

- **Autenticação** com e-mail/senha (Supabase Auth), confirmação de e-mail, recuperação de senha e lista de e-mails autorizados.
- **Clientes**: cadastro com contatos, link da pasta do Drive, histórico de publicações e contratos.
- **Conteúdo**: banco de pautas → produção → aprovação, cronograma mensal com datas sazonais (incluindo feriados móveis) e prévia do feed.
- **Tarefas e checklist** da equipe, **captação de leads** por etapa e **aniversariantes**.
- **Financeiro**: lançamentos, receitas/despesas recorrentes e projeção de saldo; contratos ativos geram receitas recorrentes automaticamente.
- Atualização **em tempo real** entre as contas (Supabase Realtime).

## Stack

| Camada | Tecnologia |
|---|---|
| Front-end | HTML, CSS e JavaScript puros (single-page, sem build) |
| Back-end / banco | Supabase (PostgreSQL + Auth + Realtime) |
| Segurança | Row Level Security em todas as tabelas + função `am_i_member()` (`security definer`) que libera acesso só a e-mails autorizados |
| Hospedagem | Netlify (deploy estático) |

## Modelo de dados

11 tabelas em `supabase.sql`: `allowed_emails`, `clients`, `client_contracts`, `deliveries`, `content_posts`, `team_tasks`, `team_checklist`, `leads`, `birthdays`, `finance_entries`, `finance_recurring`. Inclui gatilhos de auditoria (`updated_by`) e funções que sincronizam contratos com o financeiro.

## Segurança

- A chave usada no front-end é a **anon/public** do Supabase — pública por definição. Quem protege os dados são as políticas RLS: sem estar em `allowed_emails`, um usuário autenticado não lê nem grava nada.
- A tabela de e-mails autorizados não tem policy de leitura: só é consultada pela função `am_i_member()`.
- Nunca usar a chave `service_role` no front-end.

## Como rodar

O passo a passo completo (Supabase + Netlify) está em [`LEIA-ME.md`](LEIA-ME.md). Resumo:

1. Crie um projeto no Supabase e rode `supabase.sql` no SQL Editor (troque os e-mails de exemplo).
2. Em `index.html`, substitua `COLE_AQUI_A_URL_DO_PROJETO` e `COLE_AQUI_A_CHAVE_ANON` (e, se usar a integração com Google, `COLE_AQUI_O_CLIENT_ID_DO_GOOGLE`).
3. Publique a pasta no Netlify e configure a URL do site em *Authentication > URL Configuration*.

## Próximos passos

- Pipeline de dados (camadas bronze/silver/gold) sobre o histórico de entregas, contratos e financeiro.
- Indicadores por cliente: volume de entregas, prazo médio de aprovação, receita recorrente, churn.
- Separar o JavaScript em módulos e adicionar testes.

## Autor

**João Gabriel** — projeto desenvolvido para a Agência Caju.
