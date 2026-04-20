# Лабораторная №3 (база)

## Задание

> **1 часть**<br>
Настроить nginx по заданному тз:<br>
> 1. Должен работать по https c сертификатом
> 2. Настроить принудительное перенаправление HTTP-запросов (порт 80) на HTTPS (порт 443) для обеспечения безопасного соединения.
> 3. Использовать alias для создания псевдонимов путей к файлам или каталогам на сервере.
> 4. Настроить виртуальные хосты для обслуживания нескольких доменных имен на одном сервере.
> 5. Что угодно еще под требования проекта
> Результат: Предположим, что у вас есть два пет проекта на одном сервере, которые должны быть доступны по https. Настроенный вами веб сервер умеет работать по https, относить нужный запрос к нужному проекту, переопределять пути исходя из требований пет проектов.

> **2 часть**<br>
Попробовать взломать nginx любого доступного сайта. Проверить минимум три уязвимости - например path traversal, перебор страниц через ffuf и/или любые другие на ваш выбор.<br>
Рекомендую выбрать не супер популярные сайты как google или яндекс, а что-то небольшое локальное, как сайт местной спортивной федерации по бальным танцам или набора инструкций к онлайн игре.<br>
Взлом считается успешным, если вы попали туда, куда не планировалось попадать пользователю, даже если там ничего нет. Успешность взлома не влияет на оценку лабы. 
В отчет приложить скрины попыток взлома, описание уязвимостей, на которые проверяли и итог - успешен взлом или нет.

## 1 часть

На каждый домен сделала свой self-signed сертификат:

- nginx/certs/project-a.local.crt и nginx/certs/project-a.local.key
- nginx/certs/project-b.local.crt и nginx/certs/project-b.local.key

Основной конфиг - [projects.conf](./nginx/conf.d/projects.conf): https, редирект с 80, два виртуальных хоста, alias, прокси в backend.

1. Редирект HTTP -> HTTPS - отдельный server на 80, отдает 301 на https://:

```nginx
server {
    listen 80;
    server_name project-a.local project-b.local;
    return 301 https://$host$request_uri;
}
```

2. Два server-блока на 443 - project-a.local и project-b.local. По server_name запрос уходит в нужный проект.

3. Alias для переопределения путей:

- project-a.local/assets/ -> /srv/shared-assets/
- project-a.local/docs/ -> /srv/project-a/public/docs/
- project-b.local/cdn/ -> /srv/shared-assets/

```nginx
location /assets/ {
    alias /srv/shared-assets/;
}
```

4. В upstream прокидываю заголовки Host, X-Real-IP, X-Forwarded-For, X-Forwarded-Proto.

Подняла все через [docker-compose.yml](./docker-compose.yml) - nginx, project-a, project-b, порты 80 и 443, конфиги и статика примонтированы в контейнер:

```yaml
nginx:
  image: nginx:1.27-alpine
  ports:
    - "80:80"
    - "443:443"
  volumes:
    - ./nginx/conf.d:/etc/nginx/conf.d:ro
    - ./nginx/certs:/etc/nginx/certs:ro
    - ./project-a/public:/srv/project-a/public:ro
    - ./project-b/public:/srv/project-b/public:ro
    - ./shared-assets:/srv/shared-assets:ro
```

Скрины из браузера:

<img width="559" height="305" alt="image" src="https://github.com/user-attachments/assets/3674ada7-ad25-41d9-81ed-348134a57e59" />

<img width="545" height="255" alt="image" src="https://github.com/user-attachments/assets/a5d4c94a-73a2-4c0a-a5f6-0b4bfab3e6f7" />

<img width="684" height="143" alt="image" src="https://github.com/user-attachments/assets/1d0890e4-bdb9-485b-90e5-023480eab366" />

<img width="681" height="135" alt="image" src="https://github.com/user-attachments/assets/e022f150-8216-4e1d-b919-a32655cac4ee" />

<img width="692" height="156" alt="image" src="https://github.com/user-attachments/assets/964164fe-dd25-4e11-bcf5-0ecee29b3c40" />

Редирект с http:

```bash
curl -I http://project-a.local
```

<img width="335" height="168" alt="image" src="https://github.com/user-attachments/assets/881ca411-d3f7-4e48-ad4a-6a79c1802c60" />

Что project-a и project-b реально разные:

```bash
curl -k https://project-a.local
curl -k https://project-b.local
```

<img width="700" height="604" alt="image" src="https://github.com/user-attachments/assets/738ce089-6425-421c-b9c7-2d5fd59a9ac6" />

## 2 часть

Для второй части взяла https://www.gambler.ru/ (nginx/1.28.0) - не гугл и не яндекс, как в задании советуют.

### Path Traversal (/etc/passwd, .git, .env)

Пробовала path traversal через curl с --path-as-is, чтобы nginx не нормализовал путь сам:

```bash
curl -k --path-as-is "https://www.gambler.ru/../../../../etc/passwd"
curl -k --path-as-is "https://www.gambler.ru/%252e%252e%252fetc%252fpasswd"
curl -k --path-as-is "https://www.gambler.ru/%2e%2e/%2e%2e/%2e%2e/%2e%2e/etc/passwd"
```

Ответ 400 или главная страница. /etc/passwd не отдал.

<img width="648" height="186" alt="image" src="https://github.com/user-attachments/assets/2b925de3-33c2-4f7d-b4e9-3f4c207c10ca" />

### Тесты через ffuf

Собрала [ffuf-paths.txt](./ffuf-paths.txt) - типовые пути плюс то, что нашла в robots.txt.

<img width="829" height="527" alt="image" src="https://github.com/user-attachments/assets/ddb00725-ec6c-42fc-8640-b284f1592dd8" />

В основном 400 и 404, местами 301/410. admin/ дал 302 - в браузере попала на какую-то страницу /9/ с формой логина. Не /etc/passwd, но куда обычный пользователь вряд ли заходит.

<img width="1159" height="459" alt="image" src="https://github.com/user-attachments/assets/df3271c1-411c-4003-b2a5-c956a12e405e" />

### Проверка HTTP-методов

```bash
curl -k -i -X TRACE https://www.gambler.ru
curl -k -i -X PUT https://www.gambler.ru/nonexistent-test-path
curl -k -i -X DELETE https://www.gambler.ru/nonexistent-test-path
```

Что вышло:

- TRACE -> 405
- PUT/DELETE -> 301 на главную, данных не менялось

<img width="409" height="331" alt="image" src="https://github.com/user-attachments/assets/33984414-16cb-4825-904d-ee66ce85ecf2" />

### Проверка CORS, Host Header и Open Redirect

```bash
curl -k -I https://www.gambler.ru -H "Origin: https://evil.test"
curl -k -I https://www.gambler.ru -H "Host: evil.com"
curl -k -I "https://www.gambler.ru/login?return=//evil.com"
curl -k -I "https://www.gambler.ru/login?return=%2F%2Fevil.com"
```

- CORS-заголовков не увидела
- редиректа на evil.com через Host не было
- return=//evil.com тоже не увел на чужой домен, 401 без Location наружу

## Выводы

В первой части на одном сервере крутятся два проекта по https - редирект с 80, разные виртуальные хосты, alias на общую статику. В браузере и через curl все сходится.

Во второй части потыкала gambler.ru - path traversal не прошел, ffuf нашел admin/ с редиректом на страницу логина, TRACE закрыт. Критичного взлома в проверенных сценариях не получилось, но admin/ - единственное место, куда удалось зайти не туда.
