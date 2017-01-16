+++
Categories = ["Kubernetes", "Prometheus"]
Description = ""
Tags = ["Kubernetes", "Prometheus", "Monitoring"]
date = "2016-08-03T21:03:52+08:00"
title = "使用Prometheus完成Kubernetes集群监控"

+++
当你完成了[Kubernetes]集群的最初搭建后，集群监控的需求随之而来。
集群内的N台服务器在Kubernetes的管理下自动的创建和销毁着`Pod`，
但所有`Pod`和服务器的运行状态以及消耗的资源却不能方便的获得和展示，
给人一种驾驶着一辆没有仪表板的跑车在高速公路飞驰的感觉。

对于单机的Linux服务器监控，已经有了[Nagios]，[Zabbix]这些成熟的方案。
在Kubernetes集群中，我们使用新一代的监控系统[Prometheus]来完成集群的监控。

## Prometheus简介

Prometheus是SoundCloud开源的一款监控软件。它的实现参考了Google内部的监控实现，
与同样源自Google的Kubernetes项目搭配起来非常合拍。同时它也是继Kubernetes之后
第二款捐赠给[CNCF]的开源软件。相信有CNCF的推广，它将逐步成为集群时代的重要底层组件。

Prometheus集成了数据采集，存储，异常告警多项功能，是一款一体化的完整方案。
它针对大规模的集群环境设计了拉取式的数据采集方式、多维度数据存储格式以及服务发现等创新功能。

今后我们会进一步探讨Prometheus的特性以及使用技巧，在这里我们直接演示在Kubernetes集群中
使用Prometheus的方式。

## 使用服务发现简化监控系统配置

与传统的先启动监控系统，然后配置所有服务器将运行数据发往监控系统不同。Prometheus
可以通过服务发现掌握集群内部已经暴露的监控点，然后主动拉取所有监控数据。
通过这样的架构设计，我们仅仅只需要向Kubernetes集群中部署一份Prometheus实例，
它就可以通过向`apiserver`查询集群状态，然后向所有已经支持Prometheus metrics的`kubelet`
获取所有Pod的运行数据。如果我们想采集底层服务器运行状态，通过`DaemonSet`在所有服务器上运行
配套的`node-exporter`之后，Prometheus就可以自动采集到新的这部分数据。

这种动态发现的架构，非常适合服务器和程序都不固定的Kubernetes集群环境，同时
也大大降低了运维的负担。

## 启动Prometheus服务

首先将Prometheus的配置文件，存为`ConfigMap`。

{{< highlight yaml "lineseparator=<br>" >}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
data:
  prometheus.yml: |
    global:
      scrape_interval: 30s
      scrape_timeout: 30s
    scrape_configs:
    - job_name: 'prometheus'
      static_configs:
        - targets: ['localhost:9090']
    - job_name: 'kubernetes-cluster'
      scheme: https
      tls_config:
        ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
      bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
      kubernetes_sd_configs:
      - api_servers:
        - 'https://kubernetes.default.svc'
        in_cluster: true
        role: apiserver
    - job_name: 'kubernetes-nodes'
      scheme: https
      tls_config:
        ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        insecure_skip_verify: true
      bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
      kubernetes_sd_configs:
      - api_servers:
        - 'https://kubernetes.default.svc'
        in_cluster: true
        role: node
      relabel_configs:
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)
    - job_name: 'kubernetes-service-endpoints'
      scheme: https
      kubernetes_sd_configs:
      - api_servers:
        - 'https://kubernetes.default.svc'
        in_cluster: true
        role: endpoint
      relabel_configs:
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scheme]
        action: replace
        target_label: __scheme__
        regex: (https?)
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_service_annotation_prometheus_io_port]
        action: replace
        target_label: __address__
        regex: (.+)(?::\d+);(\d+)
        replacement: $1:$2
      - action: labelmap
        regex: __meta_kubernetes_service_label_(.+)
      - source_labels: [__meta_kubernetes_service_namespace]
        action: replace
        target_label: kubernetes_namespace
      - source_labels: [__meta_kubernetes_service_name]
        action: replace
        target_label: kubernetes_name
    - job_name: 'kubernetes-services'
      scheme: https
      metrics_path: /probe
      params:
        module: [http_2xx]
      kubernetes_sd_configs:
      - api_servers:
        - 'https://kubernetes.default.svc'
        in_cluster: true
        role: service
      relabel_configs:
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_probe]
        action: keep
        regex: true
      - source_labels: [__address__]
        target_label: __param_target
      - target_label: __address__
        replacement: blackbox
      - source_labels: [__param_target]
        target_label: instance
      - action: labelmap
        regex: __meta_kubernetes_service_label_(.+)
      - source_labels: [__meta_kubernetes_service_namespace]
        target_label: kubernetes_namespace
      - source_labels: [__meta_kubernetes_service_name]
        target_label: kubernetes_name
    - job_name: 'kubernetes-pods'
      scheme: https
      kubernetes_sd_configs:
      - api_servers:
        - 'https://kubernetes.default.svc'
        in_cluster: true
        role: pod
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: (.+):(?:\d+);(\d+)
        replacement: ${1}:${2}
        target_label: __address__
      - action: labelmap
        regex: __meta_kubernetes_pod_label_(.+)
      - source_labels: [__meta_kubernetes_pod_namespace]
        action: replace
        target_label: kubernetes_namespace
      - source_labels: [__meta_kubernetes_pod_name]
        action: replace
        target_label: kubernetes_pod_name
{{< /highlight >}}

将以上配置文件文件保存为`prometheus-config.yaml`，再执行

{{< highlight console "lineseparator=<br>" >}}
$ kubectl create -f prometheus-config.yaml
{{< /highlight >}}

接下来通过`Deployment`部署Prometheus

{{< highlight yaml "lineseparator=<br>" >}}
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  labels:
    name: prometheus-deployment
  name: prometheus
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      containers:
      - image: prom/prometheus:v1.0.1
        name: prometheus
        command:
        - "/bin/prometheus"
        args:
        - "-config.file=/etc/prometheus/prometheus.yml"
        - "-storage.local.path=/prometheus"
        - "-storage.local.retention=24h"
        ports:
        - containerPort: 9090
          protocol: TCP
        volumeMounts:
        - mountPath: "/prometheus"
          name: data
        - mountPath: "/etc/prometheus"
          name: config-volume
        resources:
          requests:
            cpu: 100m
            memory: 100Mi
          limits:
            cpu: 500m
            memory: 2500Mi
      volumes:
      - emptyDir: {}
        name: data
      - configMap:
          name: prometheus-config
        name: config-volume
{{< /highlight >}}

将以上文件保存为`prometheus-deployment.yaml`，接着运行

{{< highlight console "lineseparator=<br>" >}}
$ kubectl create -f prometheus-deployment.yaml
{{< /highlight >}}

如果是在国内环境，可以用`registry.cn-hangzhou.aliyuncs.com/tryk8s/prometheus:v1.0.1`
代替上面的`image`设置。

为了在本地访问Prometheus的web界面，我们利用`kubectl port-forward`将它暴露到本地

{{< highlight console "lineseparator=<br>" >}}
$ POD=`kubectl get pod -l app=prometheus -o go-template --template '{{range .items}}{{.metadata.name}}{{end}}'`
$ kubectl port-forward $POD 9090:9090
{{< /highlight >}}

这时我们用浏览器访问`http://127.0.0.1:9090`来访问Prometheus的界面，查看已经搜集到的数据。

{{< figure src="/img/prometheus-web-ui.png" link="/img/prometheus-web-ui.png" >}}

## 查询监控数据

Prometheus提供API方式的数据查询接口，用户可以使用query语言完成复杂的查询任务。
为了方便调试，web界面上提供基本的查询和图形化展示功能，我们用它做一些基本的查询。

首先查询每个容器的内存使用情况，查询`container_memory_usage_bytes{image=~".+"}`

{{< figure src="/img/container-memory.png" link="/img/container-memory.png" >}}

接下来查询各个`Pod`的CPU使用情况，查询条件是`sum(rate(container_cpu_usage_seconds_total{kubernetes_pod_name=~".+", job="kubernetes-nodes"}[1m])) by (kubernetes_pod_name, kubernetes_namespace)`。

{{< figure src="/img/pod-cpu.png" link="/img/pod-cpu.png">}}

更多的查询条件可以参考Prometheus的文档，将来也会逐步介绍，这里就不详细展开了。

## 总结

通过向Kubernetes集群内部署Prometheus，我们在不修改任何集群配置的状态下，利用Prometheus
的服务发现功能获得了基本的集群监控能力，并通过web界面对监控系统获取到的数据做了基本的查询。

未来我们将进一步完善Prometheus的使用：

- 增加更多的监控数据源
- 使用[Grafana]图形化的展示搜集到的监控数据
- 使用[AlertManager]实现异常提醒

在本文的写作过程中，CoreOS在博客上发布了[一篇相同主题的文章][coreos blog]，
本文的Prometheus配置文件根据CoreOS的分享做了修改。

[Kubernetes]: http://kubernetes.io/
[Prometheus]: https://prometheus.io/
[CNCF]: https://cncf.io/
[Nagios]: https://www.nagios.org/
[Zabbix]: http://www.zabbix.com/
[Grafana]: http://grafana.org/
[AlertManager]: https://prometheus.io/docs/alerting/alertmanager/
[coreos blog]: https://coreos.com/blog/monitoring-kubernetes-with-prometheus.html
