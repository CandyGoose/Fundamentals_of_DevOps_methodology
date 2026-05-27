# Лабораторная №2 (база)

## Задание

> **1 часть**<br><br>
Поднять kubernetes кластер локально (например minikube), в нем развернуть свой сервис, используя 2-3 ресурса kubernetes. В идеале разворачивать кодом из yaml файлов одной командой запуска. Показать работоспособность сервиса.<br>
(сервис любой из своих не опенсорсных, вывод "hello world" в браузер тоже подойдет)<br><br>
**2 часть**
> 1. Создать helm chart на основе части 1
> 2. Задеплоить его в кластер
> 3. Поменять что-то в сервисе, задеплоить новую версию при помощи апгрейда релиза
> 4. В отчете приложить скрины всего процесса, все использованные файлы, а также привести три причины, по которым использовать Helm удобнее, чем классический деплой через kubernetes манифесты

## 1 часть

### Запуск кластера

Kubernetes включила в Docker Desktop, minikube не ставила. Первая команда - просто посмотреть, что кластер отвечает:

```bash
kubectl cluster-info
```

<img width="1081" height="93" alt="image" src="https://github.com/user-attachments/assets/2849aa17-4fe8-4c2b-b8e0-ae31244a62a1" />

### Манифесты

Нужна страница "hello world" в браузере. Взяла nginx, html положила в ConfigMap - свой образ собирать не стала. [configmap.yaml](./k8s/configmap.yaml):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: hello-world-html
  labels:
    app: hello-world
data:
  index.html: |
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <title>Hello</title>
    </head>
    <body>
      <h1>Hello, world</h1>
    </body>
    </html>
```

[deployment.yaml](./k8s/deployment.yaml) поднимает nginx:1.28-alpine и монтирует html в /usr/share/nginx/html:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-world
  labels:
    app: hello-world
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hello-world
  template:
    metadata:
      labels:
        app: hello-world
    spec:
      containers:
        - name: web
          image: nginx:1.28-alpine
          ports:
            - containerPort: 80
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html
              readOnly: true
      volumes:
        - name: html
          configMap:
            name: hello-world-html
```

И [service.yaml](./k8s/service.yaml) - NodePort, порт 80, те же метки. Без него к поду неудобно, ip у него плавает:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: hello-world
  labels:
    app: hello-world
spec:
  type: NodePort
  selector:
    app: hello-world
  ports:
    - name: http
      port: 80
      targetPort: 80
```

Три файла сложила в [kustomization.yaml](./k8s/kustomization.yaml), чтобы apply прошел одной командой:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - configmap.yaml
  - deployment.yaml
  - service.yaml
```

### Развертывание

Применила:

```bash
kubectl apply -k ./lab2/k8s
```

<img width="328" height="69" alt="image" src="https://github.com/user-attachments/assets/6bfb7cbc-2137-4588-8a54-6eb903e71cc1" />

### Проверка состояния

На все объекты повесила метку app: hello-world, чтобы было проще смотреть get -l:

```bash
kubectl get configmap,deployment,service -l app=hello-world
kubectl get pods -l app=hello-world
```

<img width="581" height="62" alt="image" src="https://github.com/user-attachments/assets/b8412c14-b6ff-4648-abad-4a2db158dc0f" />

Под Running, deployment 1/1.

### Проверка в браузере

Из браузера сервис не виден, нужен port-forward:

```bash
kubectl port-forward service/hello-world 8080:80
```

<img width="458" height="69" alt="image" src="https://github.com/user-attachments/assets/dd0d2fdc-a6f9-4c8c-8ec6-756749463aea" />

http://localhost:8080 - "Hello, world" на месте.

<img width="394" height="146" alt="image" src="https://github.com/user-attachments/assets/cad9c63e-fa78-464a-b5f2-dc3e2627a4d8" />

## 2 часть

### Создание Helm chart

Тот же nginx, только теперь Helm chart. [Chart.yaml](./chart/hello-world/Chart.yaml):

```yaml
apiVersion: v2
name: hello-world
description: Веб-страница hello world
type: application
version: 0.1.0
appVersion: "1.0"
```

[values.yaml](./chart/hello-world/values.yaml) - образ, порты, реплики и текст страницы, все что в первой части было прямо в yaml:

```yaml
replicaCount: 1

image:
  repository: nginx
  tag: "1.28-alpine"
  pullPolicy: IfNotPresent

service:
  type: NodePort
  port: 80
  targetPort: 80

pageTitle: "Hello, world"
```

[values-v2.yaml](./chart/hello-world/values-v2.yaml) для upgrade - другой заголовок, replicaCount: 2:

```yaml
pageTitle: "Hello, world - v2"
replicaCount: 2
```

Манифесты из части 1 переписала в шаблоны - [configmap.yaml](./chart/hello-world/templates/configmap.yaml), [deployment.yaml](./chart/hello-world/templates/deployment.yaml), [service.yaml](./chart/hello-world/templates/service.yaml):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-hello-world-html
  labels:
    app.kubernetes.io/name: hello-world
    app.kubernetes.io/instance: {{ .Release.Name }}
data:
  index.html: |
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <title>Hello</title>
    </head>
    <body>
      <h1>{{ .Values.pageTitle }}</h1>
    </body>
    </html>
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-hello-world
  labels:
    app.kubernetes.io/name: hello-world
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app.kubernetes.io/name: hello-world
      app.kubernetes.io/instance: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: hello-world
        app.kubernetes.io/instance: {{ .Release.Name }}
    spec:
      containers:
        - name: web
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: {{ .Values.service.targetPort }}
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html
              readOnly: true
      volumes:
        - name: html
          configMap:
            name: {{ .Release.Name }}-hello-world-html
```

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-hello-world
  labels:
    app.kubernetes.io/name: hello-world
    app.kubernetes.io/instance: {{ .Release.Name }}
spec:
  type: {{ .Values.service.type }}
  selector:
    app.kubernetes.io/name: hello-world
    app.kubernetes.io/instance: {{ .Release.Name }}
  ports:
    - name: http
      port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
```

### Установка релиза

helm install, релиз назвала hw:

```bash
helm install hw ./lab2/chart/hello-world
```

<img width="386" height="140" alt="image" src="https://github.com/user-attachments/assets/49b531bf-27d4-4f93-b8df-5a5ac436609f" />

### Проверка состояния

helm list, helm status, kubectl get - посмотреть что поднялось:

```bash
helm list
helm status hw
kubectl get configmap,deployment,service,pods -l app.kubernetes.io/instance=hw
```

<img width="1189" height="59" alt="image" src="https://github.com/user-attachments/assets/b78a1982-89a6-41db-9f1c-c32bc3929e99" />

<img width="680" height="447" alt="image" src="https://github.com/user-attachments/assets/f9e52752-12ba-450b-8ad0-578a633f5c5a" />

<img width="769" height="141" alt="image" src="https://github.com/user-attachments/assets/98b17b73-13cc-4f2a-bbad-b0e8ff672262" />

Port-forward, как в части 1:

```bash
kubectl port-forward service/hw-hello-world 8080:80
```

<img width="489" height="57" alt="image" src="https://github.com/user-attachments/assets/74b6ba28-445e-4e7f-8bcd-365d03c6e69f" />

http://localhost:8080 - текст из values.yaml, совпадает.

<img width="384" height="145" alt="image" src="https://github.com/user-attachments/assets/3601ed90-6f87-4bb1-9b24-8b15c0ef5c8c" />

### Обновление релиза

helm upgrade с values-v2.yaml - поменяла заголовок и число реплик, сами yaml в templates не трогала:

```bash
helm upgrade hw ./lab2/chart/hello-world -f ./lab2/chart/hello-world/values-v2.yaml
kubectl get pods -l app.kubernetes.io/instance=hw
```

Port-forward еще раз. В браузере "Hello, world - v2", подов две штуки.

<img width="371" height="150" alt="image" src="https://github.com/user-attachments/assets/605d3d8c-2006-4d6b-9bb3-0e933bae7849" />

### 3 причины, почему Helm удобнее, чем только kubernetes манифесты

1. Один chart на разные среды - меняю values, а не копирую yaml папками.
2. helm history и rollback - когда upgrade что-то сломал, не надо вспоминать что правила в трех файлах.
3. helm uninstall hw сносит весь релиз разом. С манифестами я бы удаляла configmap, deployment и service по отдельности.

## Выводы

Одну и ту же страницу выложила два раза: сначала kubectl apply на три yaml, потом то же через Helm. Первая часть быстрее собирается, во второй дольше возиться с chart, зато upgrade одной командой и не лезу в каждый файл руками.
