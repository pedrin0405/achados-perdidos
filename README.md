# Achados & Perdidos

Aplicação para registrar e consultar itens achados e perdidos. Cada item tem
descrição, local e uma foto opcional. O backend é uma API Flask que grava os
registros no PostgreSQL e as fotos em um volume Docker. O ambiente sobe inteiro
com Docker Compose e inclui Adminer para inspeção do banco e Nginx como proxy
reverso.

Não existe interface web própria: a API responde em JSON e o navegador é usado
apenas para abrir as fotos enviadas. A documentação visual das capturas está em
[docs/evidencias/DESCRICAO-EVIDENCIAS.md](docs/evidencias/DESCRICAO-EVIDENCIAS.md).

## 1. O que o projeto faz

- cadastra itens com descrição, local e foto opcional;
- lista os itens e filtra por local;
- serve as fotos gravadas no volume;
- conta os itens do banco e os arquivos do volume;
- expõe um health check que testa a conexão com o banco;
- mantém os dados entre execuções com volumes nomeados;
- inclui script de backup do banco e das fotos.

## 2. Stack

| Camada | Tecnologia |
| --- | --- |
| Aplicação | Python 3.12 e Flask 3.0.3 |
| Servidor WSGI | Gunicorn 23.0.0, worker `gthread` com 2 processos e 4 threads |
| Banco | PostgreSQL 16 (`postgres:16-alpine`) |
| Driver | psycopg 3.2.3 |
| Proxy | Nginx (`nginx:alpine`) |
| Administração | Adminer (`adminer:latest`) |
| Orquestração | Docker Compose v2 |

## 3. Estrutura do projeto

```text
.
├── app/
│   ├── app.py              # rotas Flask
│   ├── Dockerfile          # imagem da aplicação
│   ├── requirements.txt    # dependências Python
│   └── .dockerignore
├── db/
│   └── init.sql            # tabela e dados iniciais
├── nginx/
│   └── default.conf        # proxy reverso para web:5000
├── scripts/
│   └── backup.sh           # backup do banco e das fotos
├── docs/
│   └── evidencias/         # capturas e descrição dos testes
├── backups/                # gerado pelo script (ignorado no Git)
├── docker-compose.yml
├── .env.example
└── README.md
```

## 4. Pré-requisitos

- Docker Desktop em execução, ou Docker Engine com o plugin Compose v2;
- portas 80, 8080 e 8081 livres;
- Git, se for clonar o repositório.

Para conferir a instalação:

```bash
docker --version
docker compose version
```

## 5. Configuração do ambiente

Crie o arquivo `.env` a partir do modelo:

```bash
cp .env.example .env
```

Depois edite o `.env` e defina as três variáveis:

| Variável | Uso |
| --- | --- |
| `POSTGRES_DB` | nome do banco |
| `POSTGRES_USER` | usuário do banco |
| `POSTGRES_PASSWORD` | senha do banco |

O Compose lê esse arquivo e repassa os valores para o serviço `db` e para o
serviço `web`. O `.env` está no `.gitignore` e não deve ser versionado. O
`.env.example` fica no repositório apenas com valores de exemplo.

A senha só é aplicada quando o volume `dados_banco` é criado. Se você trocar a
senha depois da primeira subida, o banco continua com a anterior até que o
volume seja recriado ou a senha seja alterada dentro do PostgreSQL.

## 6. Subir o ambiente

```bash
docker compose up -d --build
docker compose ps
```

Na primeira execução, o Compose constrói a imagem da aplicação, baixa as
imagens `postgres`, `adminer` e `nginx`, cria os volumes `dados_banco` e
`fotos` e inicia os quatro serviços. O PostgreSQL executa o `db/init.sql`
quando o volume de dados ainda está vazio. O `web` espera o `db` ficar
`healthy` por causa do `depends_on` com `condition: service_healthy`.

Nos primeiros segundos o `web` aparece como `starting`, por causa do
`start_period` do health check. Quando o `curl` interno para `/health` passa, o
estado muda para `healthy`.

## 7. Acessar os serviços

| Serviço | URL | Observação |
| --- | --- | --- |
| Aplicação via Nginx | <http://localhost> | porta 80, caminho usado pelo proxy |
| Aplicação direta | <http://localhost:8080> | sem passar pelo Nginx |
| Adminer | <http://localhost:8081> | interface web do banco |
| Health check | <http://localhost/health> | resposta em JSON |
| Fotos | <http://localhost/fotos/nome-do-arquivo> | arquivo enviado no cadastro |

No Adminer, use o sistema `PostgreSQL`, o servidor `db` (não `localhost`) e as
credenciais do `.env`. O Adminer roda dentro da rede do Compose, então o
hostname do banco é o nome do serviço.

## 8. Serviços do Compose

| Serviço | Imagem ou build | Porta no host | Volumes | Depende de |
| --- | --- | --- | --- | --- |
| `db` | `postgres:16-alpine` | nenhuma | `dados_banco`, `./db/init.sql` |  |
| `web` | build em `./app` | `8080:5000` | `fotos:/app/uploads` | `db` healthy |
| `adminer` | `adminer:latest` | `8081:8080` |  | `db` |
| `proxy` | `nginx:alpine` | `80:80` | `./nginx/default.conf` | `web` |

Fluxo das requisições:

```text
:80    -> proxy (Nginx) -> web:5000
:8080  -> web:5000
:8081  -> adminer -> db:5432
web:5000 -> db:5432 (SQL) e volume fotos (arquivos)
```

O banco não publica porta no host. Ele só é alcançável pelos outros contêineres
da rede `rede_interna`.

## 9. API

| Método | Rota | O que faz |
| --- | --- | --- |
| `GET` | `/health` | testa a aplicação e a conexão com o banco |
| `GET` | `/itens` | lista os itens; aceita `?local=` para filtrar |
| `POST` | `/itens` | cadastra um item com foto opcional |
| `GET` | `/fotos/<nome>` | devolve o arquivo da foto |
| `GET` | `/estatisticas` | conta itens no banco e fotos no volume |

Não há rotas de edição ou remoção de itens.

### 9.1 GET /health

```bash
curl http://localhost/health
```

```json
{"banco":"conectado","container":"4bd7d0047bd0","status":"ok"}
```

O endpoint executa `SELECT 1` no PostgreSQL. Se a consulta falhar, responde
`503` com `status: erro` e a mensagem da exceção no campo `banco`.

### 9.2 GET /itens

```bash
curl http://localhost/itens
curl "http://localhost/itens?local=biblioteca"
```

```json
[
  {
    "id": 1,
    "descricao": "Garrafa termica azul",
    "local": "Biblioteca",
    "foto": null,
    "criado_em": "2026-10-19T13:29:16.090725"
  }
]
```

O filtro `local` usa `ILIKE`, então a busca não diferencia maiúsculas de
minúsculas e aceita trechos do nome. Quando o item tem foto, o campo `foto`
traz o caminho `/fotos/<arquivo>`. O exemplo mostra um dos registros; a
resposta traz todos os itens, do mais recente para o mais antigo.

### 9.3 POST /itens

```bash
curl -X POST http://localhost/itens \
  -F "descricao=Caneta azul" \
  -F "local=Bloco D" \
  -F "foto=@minha-foto.jpg"
```

```json
{"id": 5, "foto": "3f2c1a9d8b7e4c6f5a1b2c3d4e5f6a7b.jpg"}
```

O corpo precisa ser `multipart/form-data`, não JSON. `descricao` e `local` são
obrigatórios; sem os dois, a resposta é `400` com a mensagem
`campos 'descricao' e 'local' sao obrigatorios`. A foto é opcional: sem ela, o
campo `foto` volta `null`.

O arquivo é gravado em `/app/uploads` com um nome UUID e a extensão original.
O nome enviado pelo cliente não é usado, o que evita colisão entre arquivos
com o mesmo nome.

### 9.4 GET /fotos/<nome>

Abra a URL no navegador ou baixe com `curl`:

```bash
curl -O http://localhost/fotos/3f2c1a9d8b7e4c6f5a1b2c3d4e5f6a7b.jpg
```

Arquivos inexistentes retornam `404`.

### 9.5 GET /estatisticas

```bash
curl http://localhost/estatisticas
```

```json
{"fotos_no_volume": 1, "itens_no_banco": 4}
```

O primeiro número vem de um `os.listdir` em `/app/uploads` e o segundo de um
`COUNT(*)` na tabela `itens`.

## 10. Banco de dados

O schema fica em `db/init.sql`:

```sql
CREATE TABLE IF NOT EXISTS itens (
    id SERIAL PRIMARY KEY,
    descricao VARCHAR(200) NOT NULL,
    local VARCHAR(100) NOT NULL,
    foto VARCHAR(100),
    criado_em TIMESTAMP NOT NULL DEFAULT NOW()
);
```

O mesmo arquivo insere três itens de exemplo (Biblioteca, Laboratorio 3 e
Cantina). Ele é montado em `/docker-entrypoint-initdb.d/init.sql` e executado
pelo PostgreSQL apenas quando o diretório de dados está vazio, ou seja, na
primeira criação do volume `dados_banco`.

Para rodar o `init.sql` de novo, é preciso remover o volume com
`docker compose down -v` e subir o ambiente outra vez. Reiniciar os contêineres
não repete a inicialização.

## 11. Volumes e persistência

| Volume | Montagem | Conteúdo |
| --- | --- | --- |
| `dados_banco` | `/var/lib/postgresql/data` | arquivos do PostgreSQL |
| `fotos` | `/app/uploads` | fotos enviadas pela API |

Os volumes são nomeados e recebem o prefixo do projeto Compose:

```bash
docker volume ls
docker volume inspect achados-perdidos_fotos
```

`docker compose down` remove contêineres e rede, mas mantém os dois volumes.
`docker compose down -v` remove também os volumes e apaga os dados. Na próxima
subida, o banco é criado vazio e o `init.sql` roda novamente.

## 12. Rede e proxy

Os quatro serviços ficam na rede `rede_interna`, do tipo bridge. O `db` não
tem porta publicada. O `web` publica `8080:5000`, o Adminer publica
`8081:8080` e o proxy publica `80:80`.

O Nginx encaminha todas as requisições para a aplicação:

```nginx
location / {
    proxy_pass http://web:5000;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    client_max_body_size 10M;
}
```

O limite de 10 MB vale para uploads feitos pela porta 80. Acessando
`localhost:8080` diretamente, o Nginx não participa e esse limite não é
aplicado.

## 13. Backup e restauração

O script `scripts/backup.sh` gera dois arquivos em `backups/`, com data e hora
no nome:

```bash
chmod +x scripts/backup.sh
./scripts/backup.sh
```

O ambiente precisa estar no ar, porque o script usa `docker compose exec` no
serviço `db`. Os arquivos gerados são ignorados pelo Git, já que podem conter
fotos reais.

Os exemplos de restauração abaixo usam o timestamp `20261019_112225`, que é o
do backup que está em `backups/`. Troque pelo nome do arquivo que você quer
restaurar.

### 13.1 Banco de dados

O script executa `pg_dump` dentro do contêiner `db` e grava
`backups/banco_<timestamp>.sql`.

Para restaurar, limpe o schema atual antes de carregar o dump. O arquivo gerado
pelo `pg_dump` contém `CREATE TABLE`, mas não contém `DROP TABLE`, então a
restauração sobre uma tabela existente falha.

```bash
# apaga o conteúdo atual (não há volta sem backup)
docker compose exec -T db sh -c \
  'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "DROP SCHEMA public CASCADE" -c "CREATE SCHEMA public"'

# carrega o dump
docker compose exec -T db \
  sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  < backups/banco_20261019_112225.sql
```

Depois da restauração, a API já enxerga os dados, porque abre uma conexão nova
a cada requisição.

### 13.2 Fotos (volume `fotos`)

O script empacota o volume em `backups/fotos_<timestamp>.tar.gz` usando um
contêiner `alpine` temporário. O nome do volume é
`achados-perdidos_fotos`, que é o nome do projeto Compose mais o nome do volume
declarado no `docker-compose.yml`.

Esse prefixo vem do nome da pasta. Se o projeto for clonado em outra pasta, o
volume passa a ser `<nome-da-pasta>_fotos`. O script continua apontando para
`achados-perdidos_fotos`; se esse volume não existir, o Docker cria um volume
vazio com esse nome e o backup das fotos sai sem os arquivos. Confira o nome
com `docker volume ls` e ajuste a linha 14 do script antes de rodar.

Para restaurar as fotos, com o ambiente no ar:

```bash
docker compose exec -T -u root web \
  sh -c 'rm -rf /app/uploads/* && tar xzf - -C /app/uploads' \
  < backups/fotos_20261019_112225.tar.gz

docker compose exec -T -u root web chown -R appuser:appuser /app/uploads
```

O `chown` é uma proteção: o `tar` foi criado por `root` e, dependendo da origem
do arquivo, pode restaurar os donos com outro UID. O usuário da aplicação é
`appuser`.

## 14. Logs e diagnóstico

Comandos usados com frequência:

```bash
docker compose ps
docker compose logs -f web
docker compose logs -f proxy
docker compose exec db sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
curl -i http://localhost/health
```

O `web` registra cada requisição no stdout por causa do `--access-logfile -` do
Gunicorn. O `proxy` registra os acessos no formato padrão do Nginx.

### 14.1 Problemas comuns

| Sintoma | Causa provável | Correção |
| --- | --- | --- |
| `port is already allocated` | porta 80, 8080 ou 8081 em uso | pare o serviço conflitante ou ajuste `ports` no Compose |
| `password authentication failed` | `.env` mudou depois que o volume do banco foi criado | recriar com `down -v` (apaga os dados) ou alterar a senha dentro do PostgreSQL |
| `init.sql` não rodou | volume `dados_banco` já existia | `docker compose down -v` e subir de novo |
| `413 Request Entity Too Large` | upload maior que 10 MB pela porta 80 | aumentar `client_max_body_size` ou usar a porta 8080 |
| Adminer não conecta | servidor preenchido como `localhost` | usar `db` no campo Servidor |
| script de backup não encontra o volume | pasta do projeto com outro nome | conferir `docker volume ls` e ajustar o nome no script |
| `WORKER TIMEOUT` no log | worker do Gunicorn travado | ver `docker compose logs web`; o Dockerfile usa `gthread` justamente para evitar o bloqueio por conexão ociosa |

## 15. Limpeza

```bash
# para e remove contêineres e rede, mantendo os volumes
docker compose down

# remove também os volumes e apaga banco e fotos
docker compose down -v

# remove a imagem construída pela aplicação
docker compose down --rmi local
```

Use `down -v` quando quiser voltar ao estado inicial. Os arquivos de backup em
`backups/` continuam no disco.

## 16. Evidências

As capturas de tela dos testes estão em
[`docs/evidencias/`](docs/evidencias/), com a descrição de cada uma em
[`DESCRICAO-EVIDENCIAS.md`](docs/evidencias/DESCRICAO-EVIDENCIAS.md). O
documento cobre a subida do ambiente, o health check, o cadastro com foto, a
persistência dos volumes, a remoção com `down -v`, a inspeção da rede e das
imagens, e os bônus (Adminer, backup e Nginx).

## 17. Segurança e limitações

- O `.env` não é versionado. O `.env.example` tem apenas valores fictícios.
- O PostgreSQL não publica porta no host; o acesso fica restrito à rede interna.
- A aplicação roda com o usuário `appuser`, sem privilégios de root.
- O Adminer fica exposto na porta 8081 e aceita login com as credenciais do
  banco. Use apenas em desenvolvimento e não exponha essa porta na internet.
- A API não tem autenticação nem autorização. Qualquer cliente com acesso às
  portas publicadas pode cadastrar e consultar itens.
- O upload não valida tipo ou conteúdo do arquivo. A extensão original é
  preservada e o limite de 10 MB existe apenas no Nginx, ou seja, não vale para
  acessos diretos à porta 8080.
- Fotos e backups podem conter dados pessoais. `image.png`, `*.tar.gz` e a pasta
  `backups/` estão no `.gitignore`.

Para uso em produção, seria necessário adicionar TLS, autenticação, validação
dos uploads, limite de tamanho na aplicação e um local de armazenamento fora do
volume local.
