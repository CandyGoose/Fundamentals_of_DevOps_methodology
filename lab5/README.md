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

<img width="327" height="92" alt="image" src="https://github.com/user-attachments/assets/6a24423c-8bf8-4180-af43-628b57ed9f37" />

<img width="774" height="110" alt="image" src="https://github.com/user-attachments/assets/71d59329-0372-408e-8b80-6bd956e5d8a0" />

Port-forward и проверка в браузере:

```bash
kubectl port-forward -n lab5 service/hello-world 8080:80
```

<img width="381" height="142" alt="image" src="https://github.com/user-attachments/assets/90386814-afdd-4dbb-8ae3-67837ddd6f07" />

### Prometheus и Grafana

Prometheus + Grafana через helm, values в [values-prometheus.yaml](./monitoring/values-prometheus.yaml):

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install lab5-prometheus prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace -f ./lab5/monitoring/values-prometheus.yaml
kubectl get pods -n monitoring
```

<img width="725" height="79" alt="image" src="https://github.com/user-attachments/assets/49e60bc4-a3ea-4a3e-9e49-cad26ae11ea4" />

<img width="1525" height="156" alt="image" src="https://github.com/user-attachments/assets/caf258fa-fa76-43fa-a810-614e7e4f71da" />

<img width="877" height="97" alt="image" src="https://github.com/user-attachments/assets/311606b8-d558-4da0-927f-6be475ebc35d" />

Подключила hello-world к Prometheus и закинула дашборд в Grafana:

```bash
kubectl apply -f ./lab5/k8s/servicemonitor.yaml
kubectl apply -f ./lab5/monitoring/grafana-dashboard-hello-world.yaml
```

[servicemonitor.yaml](./k8s/servicemonitor.yaml) - Prometheus Operator ходит на 9113 каждые 15 секунд. [grafana-dashboard-hello-world.yaml](./monitoring/grafana-dashboard-hello-world.yaml) - ConfigMap с json дашборда.

<img width="534" height="42" alt="image" src="https://github.com/user-attachments/assets/1abec48e-164a-49b5-8e16-3dbf747cc998" />

<img width="649" height="39" alt="image" src="https://github.com/user-attachments/assets/a4642d14-30b3-45bf-9207-836271758258" />

### Графики

В Grafana смотрю:
1. Активные соединения nginx - nginx_connections_active{namespace="lab5"}
2. CPU пода - sum(rate(container_cpu_usage_seconds_total{namespace="lab5", pod=~"hello-world-.*", cpu="total"}[5m]))

Чтобы график шевелился, накидала запросов:

```bash
for i in $(seq 1 300); do curl -s -o /dev/null http://localhost:8080/ & done; wait
```

<img width="1448" height="466" alt="image" src="https://github.com/user-attachments/assets/5a11c1b7-ae3f-41ff-9d82-f4fac2f6e34b" />

Остановила сервис - графики упали:

<img width="1450" height="457" alt="image" src="https://github.com/user-attachments/assets/3fed861f-0100-4226-a48d-a4fbbde1dc9c" />

## Выводы

Подняла hello-world в k8s, повесила на него Prometheus и Grafana. Два графика живые - соединения nginx и cpu пода. Падение видно когда сервис выключить.
