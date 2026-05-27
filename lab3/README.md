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
Взлом считается успешным, если вы попали туда, куда не планировалось попадать пользователю, даже если там ничего нет. Успешность взлома не влияет на оценку лабы.<br>
В отчет приложить скрины попыток взлома, описание уязвимостей, на которые проверяли и итог - успешен взлом или нет.

## 1 часть

На каждый домен сделала свой self-signed сертификат:

- nginx/certs/project-a.local.crt и nginx/certs/project-a.local.key
- nginx/certs/project-b.local.crt и nginx/certs/project-b.local.key

Основной конфиг - [projects.conf](./nginx/conf.d/projects.conf): https, редирект с 80, два виртуальных хоста, alias, прокси в backend.

Редирект HTTP -> HTTPS - отдельный server на 80, отдает 301 на https://:

```nginx
server {
    listen 80;
    server_name project-a.local project-b.local;
    return 301 https://$host$request_uri;
}
```

Два server-блока на 443 - project-a.local и project-b.local. По server_name запрос уходит в нужный проект.

Alias для переопределения путей:

- project-a.local/assets/ -> /srv/shared-assets/
- project-a.local/docs/ -> /srv/project-a/public/docs/
- project-b.local/cdn/ -> /srv/shared-assets/

```nginx
location /assets/ {
    alias /srv/shared-assets/;
}
```

В upstream прокидываю заголовки Host, X-Real-IP, X-Forwarded-For, X-Forwarded-Proto.

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

<img width="536" height="293" alt="image" src="https://github.com/user-attachments/assets/957d00ce-0e4f-4ae8-b7cd-20bb7fb04bff" />

<img width="561" height="246" alt="image" src="https://github.com/user-attachments/assets/10ce2143-df9c-42e7-961c-6ccf759b756a" />

<img width="675" height="162" alt="image" src="https://github.com/user-attachments/assets/9ac66b5c-556b-4484-83c8-df98f224c51a" />

<img width="682" height="141" alt="image" src="https://github.com/user-attachments/assets/ff8f7a9c-5b47-4acc-a48a-95a4a501a212" />

<img width="655" height="156" alt="image" src="https://github.com/user-attachments/assets/34047357-915e-46ed-a9ba-b0efd437e4e3" />

Редирект с http:

```bash
curl -I http://project-a.local
```

<img width="325" height="146" alt="image" src="https://github.com/user-attachments/assets/d53e4d9a-f81a-4eeb-893a-5aa32f797ccc" />

Что project-a и project-b реально разные:

```bash
curl -k https://project-a.local
curl -k https://project-b.local
```

<img width="727" height="260" alt="image" src="https://github.com/user-attachments/assets/42ce75ec-7e71-4417-bf4a-13c5eb74986b" />

<img width="730" height="240" alt="image" src="https://github.com/user-attachments/assets/fd87fef5-5fad-4b7b-a619-88f547a72f68" />

## 2 часть

Для второй части взяла https://www.gambler.ru/ (nginx/1.28.0).

### Path Traversal (/etc/passwd, .git, .env)

Пробовала path traversal через curl с --path-as-is, чтобы nginx не нормализовал путь сам:

```bash
curl -k --path-as-is "https://www.gambler.ru/../../../../etc/passwd"
curl -k --path-as-is "https://www.gambler.ru/%252e%252e%252fetc%252fpasswd"
curl -k --path-as-is "https://www.gambler.ru/%2e%2e/%2e%2e/%2e%2e/%2e%2e/etc/passwd"
```

Ответ 400 или главная страница. /etc/passwd не отдал.

<img width="645" height="140" alt="image" src="https://github.com/user-attachments/assets/dff7ee91-609d-4552-b56e-a729180a0704" />

<img width="911" height="404" alt="image" src="https://github.com/user-attachments/assets/54e37a96-3415-4dd6-9f49-87e761388cc3" />

<img width="781" height="143" alt="image" src="https://github.com/user-attachments/assets/b88c3b17-7e87-409b-8999-b31f851afac1" />

### Тесты через ffuf

Собрала [ffuf-paths.txt](./ffuf-paths.txt) - типовые пути плюс то, что нашла в robots.txt.

<img width="430" height="916" alt="image" src="https://github.com/user-attachments/assets/1a480cc7-7ca6-4fc2-8f0f-e80d1810e26c" />

В основном 30X, местами 40X. admin/ дал 302 - в браузере попала на какую-то страницу /9/ с формой логина. Не /etc/passwd, но куда обычный пользователь вряд ли заходит.

<img width="775" height="865" alt="image" src="https://github.com/user-attachments/assets/944d7d59-8844-40c7-a2a8-a9609221d870" />

<img width="1139" height="824" alt="image" src="https://github.com/user-attachments/assets/0e754dd1-3a95-4c85-88c2-2941e2bcb89b" />

### Проверка HTTP-методов

```bash
curl -k -i -X TRACE https://www.gambler.ru
curl -k -i -X PUT https://www.gambler.ru/nonexistent-test-path
curl -k -i -X DELETE https://www.gambler.ru/nonexistent-test-path
```

Что вышло:

- TRACE -> 405
- PUT/DELETE -> 301 на главную, данных не менялось

<img width="412" height="260" alt="image" src="https://github.com/user-attachments/assets/26de4d88-09cc-4946-adfd-0d17af130fe3" />

<img width="584" height="146" alt="image" src="https://github.com/user-attachments/assets/1146947a-295d-47cd-beb4-3c6ebbef4530" />

<img width="617" height="149" alt="image" src="https://github.com/user-attachments/assets/fc020710-188f-4125-8535-4cfa4c24f4c9" />

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
