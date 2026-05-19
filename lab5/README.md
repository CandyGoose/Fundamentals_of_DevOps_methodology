# Лабораторная №5 (база)

## Задание

> **Обычная**<br>
Сделать мониторинг сервиса, поднятого в кубере (использовать, например, prometheus и grafana). Показать хотя бы два рабочих графика, которые будут отражать состояние системы. Приложить скриншоты всего процесса настройки.<br><br>
**Со звездочкой**<br>
Настроить алерт кодом IaaC (например через конфиг алертменеджера, главное - не в интерфейсе графаны:), показать пример его срабатывания. Попробовать сделать так, чтобы он приходил, например, на почту или в телеграм. Если не получится - показать имеющийся результат и аргументировать, почему дальше невозможно реализовать.

Выбрала обычный вариант.

Hello world на nginx, поверх него мониторинг.

### Развертывание

[configmap-nginx.yaml](./k8s/configmap-nginx.yaml) - html и конфиг nginx со stub_status:

```nginx
location /stub_status {
  stub_status;
  allow 127.0.0.1;
  deny all;
}
```

[deployment.yaml](./k8s/deployment.yaml) - два контейнера в одном поде: nginx на 80, nginx-prometheus-exporter на 9113 снимает метрики со stub_status.

[service.yaml](./k8s/service.yaml) - порты наружу.

```bash
kubectl apply -k ./lab5/k8s
kubectl get pods,svc -n lab5
```

<img width="730" height="241" alt="image" src="https://github.com/user-attachments/assets/09233aa7-8502-4e95-a2cd-c9c2fa5ac119" />

Port-forward и проверка в браузере:

```bash
kubectl port-forward -n lab5 service/hello-world 8080:80
```

<img width="363" height="144" alt="image" src="https://github.com/user-attachments/assets/2873d72c-f0cf-44f5-a775-217e1e8a9078" />

### Prometheus и Grafana

Prometheus + Grafana через helm, values в [values-prometheus.yaml](./monitoring/values-prometheus.yaml):

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install lab5-prometheus prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace -f ./lab5/monitoring/values-prometheus.yaml
kubectl get pods -n monitoring
```

<img width="722" height="554" alt="image" src="https://github.com/user-attachments/assets/186a85f8-f7a6-4302-8795-c874c101a789" />

Подключила hello-world к Prometheus и закинула дашборд в Grafana:

```bash
kubectl apply -f ./lab5/k8s/servicemonitor.yaml
kubectl apply -f ./lab5/monitoring/grafana-dashboard-hello-world.yaml
```

[servicemonitor.yaml](./k8s/servicemonitor.yaml) - Prometheus Operator ходит на 9113 каждые 15 секунд. [grafana-dashboard-hello-world.yaml](./monitoring/grafana-dashboard-hello-world.yaml) - ConfigMap с json дашборда.

### Графики

В Grafana смотрю:
1. Активные соединения nginx - nginx_connections_active{namespace="lab5"}
2. CPU пода - sum(rate(container_cpu_usage_seconds_total{namespace="lab5", pod=~"hello-world-.*", cpu="total"}[5m]))

Чтобы график шевелился, накидала запросов:

```bash
for i in $(seq 1 300); do curl -s -o /dev/null http://localhost:8080/ & done; wait
```

<img width="1610" height="357" alt="image" src="https://github.com/user-attachments/assets/8b1c993a-b51d-48e9-90bb-f5e48af63cc2" />

Остановила сервис - графики упали:

<img width="1529" height="351" alt="image" src="https://github.com/user-attachments/assets/99cbdfc8-f1c9-4735-b1c7-b14c1b87e2d4" />

## Выводы

Подняла hello-world в k8s, повесила на него Prometheus и Grafana. Два графика живые - соединения nginx и cpu пода. Нагрузку curl'ом, падение видно когда сервис выключить.
