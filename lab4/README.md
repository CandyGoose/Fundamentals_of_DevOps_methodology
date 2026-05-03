# Лабораторная №4 (база)

## Задание

> **1 часть**<br>
Написать "плохой" CI/CD файл, который работает, но в нем есть не менее пяти "bad practices" по написанию CI/CD<br>
> 1. Написать "хороший" CI/CD, в котором эти плохие практики исправлены<br>
> 2. В Readme описать каждую из плохих практик в плохом файле, почему она плохая и как в хорошем она была исправлена, как исправление повлияло на результат<br>
> 3. В пайплайне должно быть не менее пяти этапов
>
> **2 часть**<br>
Сделать красиво работу с секретами. Например, поднять Hashicorp Vault и сделать так, чтобы ci/cd пайплайн (или любой другой ваш сервис) ходил туда, брал секрет, использовал его не светя в логах. В Readme аргументировать почему ваш способ красивый, а также описать, почему хранение секретов в CI/CD переменных репозитория не является хорошей практикой.

## 1 часть

GitLab CI. Плохой пайплайн - [.gitlab-ci.bad.yml](./.gitlab-ci.bad.yml), нормальный - [.gitlab-ci.good.yml](./.gitlab-ci.good.yml).

Шесть этапов в обоих: prepare, lint, test, build, package, deploy. Собирается site.tar.gz со статикой и уезжает на условный деплой.

### Использование latest

В плохом файле образ плавает:

```yaml
default:
  image: alpine:latest
```

latest меняется когда хочет. Запустишь пайплайн сегодня - одно, через месяц - другое, а в git diff пусто.

В хорошем версия прибита:

```yaml
default:
  image: alpine:3.21.3
```

### Секрет захардкожен прямо в CI/CD файле

Плохой вариант - пароль прямо в yaml:

```yaml
variables:
  DEPLOY_PASSWORD: super-secret-password
```

Он в истории git, его видит каждый с доступом к репо. Поменять без коммита не выйдет.

В хорошем на deploy секрет тянется из Vault:

```yaml
- >
  DEPLOY_TOKEN=$(curl --silent --show-error --fail
  --header "X-Vault-Token: $VAULT_TOKEN"
  "$VAULT_ADDR/v1/secret/data/lab4/deploy" | jq -r '.data.data.deploy_token')
```

### Секрет светится в логах

В плохом еще и echo:

```yaml
before_script:
  - echo "Deploy password: $DEPLOY_PASSWORD"
```

Любой с доступом к логам job видит пароль текстом.

В хорошем токен только проверяется и уходит в curl, в лог не печатается:

```yaml
- test -n "$DEPLOY_TOKEN"
- curl --silent --show-error --fail --header "Authorization: Bearer $DEPLOY_TOKEN" --form "artifact=@site.tar.gz" "$DEPLOY_URL"
```

### Тесты помечены allow_failure

Плохой:

```yaml
test:
  allow_failure: true
```

Тесты упали - пайплайн все равно идет дальше, deploy может случиться на сломанном коде.

Убрала allow_failure:

```yaml
test:
  stage: test
  needs:
    - prepare
```

### Деплой идет всегда для любой ветки

Плохой:

```yaml
deploy:
  stage: deploy
  when: always
```

Деплой с любой ветки, даже если предыдущие стадии красные.

В хорошем только main:

```yaml
deploy:
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
```

## 2 часть

Секреты через Hashicorp Vault. [docker-compose.vault.yml](./docker-compose.vault.yml), bootstrap - [vault/bootstrap-dev.sh](./vault/bootstrap-dev.sh), policy - [vault/policies/lab4-ci.hcl](./vault/policies/lab4-ci.hcl).

Vault в dev-режиме, без лишней возни для лабы:

```bash
docker compose -f ./lab4/docker-compose.vault.yml up -d
```

Дальше bootstrap: kv-v2 на secret/, секрет secret/lab4/deploy, jwt auth для gitlab:

1. Включаю kv-v2 по пути secret/
2. Кладу secret/lab4/deploy с полем deploy_token
3. Настраиваю jwt auth и роль lab4-ci - короткий токен только для пайплайна нужного проекта и ветки main

```bash
docker compose -f ./lab4/docker-compose.vault.yml exec \
  -e GITLAB_PROJECT_PATH=group/project \
  vault sh /workspace/vault/bootstrap-dev.sh
```

Как deploy ходит в Vault в хорошем пайплайне:

1. GitLab дает job временный id_token
2. Job меняет JWT на Vault token через /v1/auth/jwt/login
3. Vault смотрит issuer, audience, claims
4. Токеном читаю secret/data/lab4/deploy
5. Секрет сразу в curl, не в echo

```yaml
id_tokens:
  VAULT_JWT:
    aud: https://vault.demo.local
```

```yaml
- >
  VAULT_TOKEN=$(curl --silent --show-error --fail
  --request POST
  --header "Content-Type: application/json"
  --data "{\"role\":\"lab4-ci\",\"jwt\":\"$VAULT_JWT\"}"
  "$VAULT_ADDR/v1/auth/jwt/login" | jq -r '.auth.client_token')
```

Мне так нравится больше: в CI нет вечного секрета на все секреты, JWT живет один job, Vault token короткий и только на чтение одного пути, ветку и проект можно зажать. В git и логах пароля нет.

Почему CI/CD variables хуже как основное хранилище:

- секрет долго живет, утек - пока руками не сменишь, им пользуются
- один и тот же токен копируют в кучу проектов, потом больно менять везде
- права через настройки CI, не через отдельное хранилище
- неудобно дать кому-то доступ только к одному секрету

## Выводы

Сделала два пайплайна - специально кривой и рабочий. В плохом пять косяков: latest, пароль в yaml, пароль в логах, allow_failure на тестах, deploy откуда угодно. В хорошем все это закрыла.

Vault добавила для секретов - job приходит с JWT, забирает deploy_token на минуту и деплоит. В репозитории и логах секретов нет.
