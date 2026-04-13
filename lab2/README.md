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

<img width="1081" height="95" alt="image" src="https://github.com/user-attachments/assets/b85bc5a3-32b1-48d9-8f84-c70a50576eda" />

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

<img width="338" height="76" alt="image" src="https://github.com/user-attachments/assets/db9c484c-5c54-4e1d-a5fa-ee43ad68f4db" />

### Проверка состояния

На все объекты повесила метку app: hello-world - так проще смотреть get -l:

```bash
kubectl get configmap,deployment,service -l app=hello-world
kubectl get pods -l app=hello-world
```

<img width="734" height="219" alt="image" src="https://github.com/user-attachments/assets/f0050abc-61c0-45b4-9e5c-6ad83d518f8d" />

Под Running, deployment 1/1.

### Проверка в браузере

Из браузера сервис не виден, нужен port-forward:

```bash
kubectl port-forward service/hello-world 8080:80
```

<img width="457" height="91" alt="image" src="https://github.com/user-attachments/assets/4dd41208-4910-47af-a56e-a8329169caa2" />

http://localhost:8080 - "Hello, world" на месте.

<img width="346" height="162" alt="image" src="https://github.com/user-attachments/assets/dad6ad62-4b3a-4e85-9b02-2a6d4ebe9b33" />

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

<img width="407" height="142" alt="image" src="https://github.com/user-attachments/assets/514599f7-c135-43ac-805c-72898e20b1c1" />

### Проверка состояния

helm list, helm status, kubectl get - посмотреть что поднялось:

```bash
helm list
helm status hw
kubectl get configmap,deployment,service,pods -l app.kubernetes.io/instance=hw
```

<img width="722" height="795" alt="image" src="https://github.com/user-attachments/assets/0c0001da-2043-4169-89be-33061b1fc754" />

Port-forward, как в части 1:

```bash
kubectl port-forward service/hw-hello-world 8080:80
```

<img width="483" height="89" alt="image" src="https://github.com/user-attachments/assets/e6d39145-26b3-4932-a5a3-4072c3b51ad1" />

http://localhost:8080 - текст из values.yaml, совпадает.

<img width="330" height="155" alt="image" src="https://github.com/user-attachments/assets/a20ea200-89fb-4a09-b4b8-a1ccf97bd020" />

### Обновление релиза

helm upgrade с values-v2.yaml - поменяла заголовок и число реплик, сами yaml в templates не трогала:

```bash
helm upgrade hw ./lab2/chart/hello-world -f ./lab2/chart/hello-world/values-v2.yaml
kubectl get pods -l app.kubernetes.io/instance=hw
```

Port-forward еще раз. В браузере "Hello, world - v2", подов две штуки.

<img width="317" height="159" alt="image" src="https://github.com/user-attachments/assets/83554ca7-e585-4a4e-bdee-de0a5248ee12" />

### 3 причины, почему Helm удобнее, чем только kubernetes манифесты

1. Один chart на разные среды - меняю values, а не копирую yaml папками.
2. helm history и rollback - когда upgrade что-то сломал, не надо вспоминать что правила в трех файлах.
3. helm uninstall hw сносит весь релиз разом. С манифестами я бы удаляла configmap, deployment и service по отдельности.

## Выводы

Одну и ту же страницу выложила два раза: сначала kubectl apply на три yaml, потом то же через Helm. Первая часть быстрее собирается, во второй дольше возиться с chart, зато upgrade одной командой и не лезу в каждый файл руками.
