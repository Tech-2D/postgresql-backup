# Backup do PostgreSQL da Tech-2D

A rotina em GitHub Actions gera uma cópia lógica do schema de aplicação `tech2d` no Neon todos os dias às **03h17 de Brasília** (06h17 UTC). Também pode ser executada manualmente em **Actions → Backup do Neon → Run workflow**.

O PostgreSQL 18 gera um arquivo no formato custom (`.dump`) pela conexão direta com TLS e validação do servidor. O workflow restaura o arquivo em um PostgreSQL descartável e confere as tabelas usadas pela Agenda e pelos horários antes do envio. O dump inclui as tabelas, os dados, as views, as funções, os índices, as sequências e as políticas do schema da aplicação.

A cópia vai para `postgresql/` no bucket privado `tech-2d-neon-backups`. Uma regra de ciclo de vida do R2 expira esses objetos depois de **sete dias**. A operação de upload autentica o runner, valida o SHA-256 e aceita arquivos de até 90 MiB. O GitHub guarda o log da execução. Os arquivos do banco ficam no R2.

## Recuperar

1. Baixe o arquivo desejado pelo painel do bucket privado e verifique o SHA-256 em relação aos metadados do objeto.
2. Confira o conteúdo com `pg_restore --list arquivo.dump`.
3. Em um PostgreSQL 18 descartável, crie o banco de teste e os papéis sem login necessários às políticas do dump.

   ```sql
   CREATE ROLE tech2d_api NOLOGIN;
   CREATE ROLE tech2d_backup NOLOGIN;
   ```

4. Restaure no banco de teste com uma conta administrativa.

   ```bash
   pg_restore --exit-on-error --single-transaction --no-owner --no-acl \
     --dbname=tech2d_teste arquivo.dump
   ```

5. Valide o conteúdo e os totais antes de usar a cópia como base para outro banco. Para um destino permanente, reaplique os papéis e as permissões do ambiente. A cópia tem a estrutura do schema e seus dados. Usuários globais do PostgreSQL, Firebase Authentication, Redis e arquivos do R2 da Agenda são fontes separadas.

## Configuração

- `NEON_BACKUP_URL` é um secret do GitHub com a conexão direta do papel `tech2d_backup`. O papel lê apenas os dados necessários ao dump, incluindo as tabelas de Notas por políticas RLS de leitura. Ao acrescentar tabelas com RLS, inclua uma política explícita de leitura para esse papel.
- `BACKUP_UPLOAD_SECRET` é um secret compartilhado pelo GitHub e pelo Worker.
- `BACKUP_UPLOAD_URL` é a variável com a URL do Worker.
- `wrangler.jsonc` vincula o Worker exclusivamente ao bucket de backups. A regra `postgresql-seven-days` é configurada no próprio R2.

Referência de arquitetura e restauração: [Astro-Inter/postgresql-backup](https://github.com/Astro-Inter/postgresql-backup).
