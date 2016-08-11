+++
Categories = ["Kubernetes", "Prometheus"]
Description = ""
Tags = ["Kubernetes", "Prometheus", "Monitoring"]
date = "2016-08-08T22:38:48+08:00"
title = "使用Node Exporter扩展Prometheus数据"

+++
在[前一篇文章][previous-post]当中，我们介绍了在[Kubernetes]中使用[Prometheus]进行集群监控的方法，并配置了服务发现，让Prometheus从Kubernetes集群的各个组件中采集运行数据。
在之前的例子中，我们主要是通过`kubelet`中自带的`cadvisor`采集容器的运行状态。今天我们来进一步完善监控系统，使用Node Exporter采集底层服务器的运行状态。

## Node Exporter简介

Exporter是Prometheus的一类数据采集组件的总称。它负责从目标处搜集数据，并将其转化为Prometheus支持的格式。
与传统的数据采集组件不同的是，它并不向中央服务器发送数据，而是等待中央服务器主动前来抓取，默认的抓取地址为`http://CURRENT_IP:9100/metrics`

Prometheus提供多种类型的Exporter用于采集各种不同服务的运行状态。Node Exporter顾名思义，主要用于采集底层服务器的各种运行参数。

目前Node Exporter支持几乎所有常见的监控点，比如`conntrack`，`cpu`，`diskstats`，`filesystem`，`loadavg`，`meminfo`，`netstat`等。
详细的监控点列表请参考[其Github repo][node-exporter]。

## 部署Node Exporter

在Kubernetes中部署Node Exporter非常简单，我们使用`DaemonSet`功能，可以非常方便的在集群内的所有主机上启动Node Exporter。
在配合上Prometheus的服务发现功能，无需额外的设置，我们就可以把这些Node Exporter Pod加入到被采集的列表当中。

将以下配置文件保存为`node-exporter.yaml`， 并运行 `kubectl create -f node-exporter.yaml`。

{{< highlight yaml >}}
apiVersion: v1
kind: Service
metadata:
  annotations:
    prometheus.io/scrape: 'true'
  labels:
    app: node-exporter
    name: node-exporter
  name: node-exporter
spec:
  clusterIP: None
  ports:
  - name: scrape
    port: 9100
    protocol: TCP
  selector:
    app: node-exporter
  type: ClusterIP
----
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: node-exporter
spec:
  template:
    metadata:
      labels:
        app: node-exporter
      name: node-exporter
    spec:
      containers:
      - image: prom/node-exporter:latest
        name: node-exporter
        ports:
        - containerPort: 9100
          hostPort: 9100
          name: scrape
      hostNetwork: true
      hostPID: true
{{< /highlight >}}

国内的Kubernetes集群可以使用`registry.cn-hangzhou.aliyuncs.com/tryk8s/node-exporter:latest`
替换`prom/node-exporter:latest`解决image拉取的问题。

在确保所有服务器上的Node Exporter pod启动之后，我们就可以用Prometheus的web界面查看各个服务的状态了

## 查询服务器状态

继续使用Prometheus的web界面来验证Node Exporter的数据已经被正确的采集。

首先查询`node_load1`，`node_load5`，`node_load15`这三项CPU使用情况。

{{< figure src="/img/node-load.png" link="/img/node-load.png" >}}

接着查询`rate(node_network_receive_bytes[1m])`，`rate(node_network_transmit_bytes[1m])`这两项网络使用情况。

{{< figure src="/img/node-load.png" link="/img/node-load.png" >}}

以及`node_memory_MemAvailable`所代表的剩余内存情况。

{{< figure src="/img/node-memory.png" link="/img/node-memory.png" >}}

## 总结

通过`DaemonSet`和`Service`，我们向Kubernetes集群中的所有机器部署了Node Exporter。
Prometheus会自动通过服务发现找到这些Node Exporter服务，并从中采集服务器状态。

但是从使用过程中我们会发现，Prometheus的web界面比较适合用来做测试，如果日常使用还需要手动输入查询参数会很不方便。
接下来我们将使用[Grafana]来对Prometheus采集到的数据进行可视化展示。这样就可以在一个页面中图形化展示多个预定义的参数。

[previous-post]: {{< ref "kubernetes/kubernetes-monitoring-with-prometheus.md" >}}
[Kubernetes]: http://kubernetes.io/
[Prometheus]: https://prometheus.io/
[Grafana]: http://grafana.org/
[node-exporter]: https://github.com/prometheus/node_exporter
