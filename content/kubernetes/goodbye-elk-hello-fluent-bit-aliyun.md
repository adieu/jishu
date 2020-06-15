+++
Categories = ["Kubernetes"]
Tags = ["Kubernetes","logging", "fluent-bit", "aliyun"]
Description = ""
date = "2017-06-28T17:40:05+08:00"
title = "再见ELK，您好fluent-bit-aliyun"
+++
`ELK`是[Elasticsearch][elasticsearch]，[Logstash][logstash]，[Kibana][kibana]的缩写，是我们在处理日志时最常用到的方案。其中`Logstash`负责日志采集，
`Elasticsearch`负责日志存储，`Kibana`负责日志展示。三款开源项目分工合作，提供了完整的解决方案。
此外也有使用[Fluentd][fluentd]替换`Logstash`组成的`EFK`方案，同样也非常受欢迎。

针对不同的环境，已经有大量的文档详细介绍了安装和配置的方法。在Kubernetes环境中，管理员甚至可以使用一键部署脚本完成安装。
这些总结下来的经验极大的降低了`ELK`的上手门槛，运维人员可以很方便的开始将所有服务器产出日志统一的搜集起来。

但在使用了一段时间之后，随着数据量的增加以及集群规模的扩大，维护一套高效运转的`ELK`系统所需要付出的运维成本在逐渐增大。
管理员将面临以下几个挑战：

- 多种不同应用的日志格式不同，需要为不同的应用配置专门的日志解析器
- 在所有服务器上更新组件版本以及配置带来的运维工作量的增加
- 单机版本的`Elasticsearch`的性能跟不上日志产出的速度，需要集群化部署`ES`
- `ES`集群的搭建和管理过程中的复杂度对运维人员的能力要求较高。过度依赖脚本和教程的工程师可能无法顺利完成
- `ES`消耗的IO，CPU，内存资源均较高。为了能够提供足够的日志处理能力，`ELK`所需要的计算资源投入对于小型团队来说是不小的负担
- `ELK`方案中缺少日志归档，持久保存的功能。而`ES`的存储能力受集群规模的限制无法无限扩张。管理员需要面临删除老数据或是研发数据导出存档功能的选择

在Kubernetes环境中，使用k8s所提供的调度功能和`ConfigMap`所提倡的配置管理最佳实践，再配合上[elasticsearch-operator][elasticsearch-operator]这样的工具，
可以大大降低日常的运维负担，但在算力消耗以及成本增加的问题上，能够带来的改善有限。

对于小型项目，我们需要更加轻量更加经济的解决方案，将日志管理SaaS化，交给合适的供应商来提供，用户按需付费可能是更适合的解决方案。

## 阿里云日志服务

[阿里云提供的日志服务][aliyun-sis]是一套完整的日志管理解决方案。它提供的搜集、消费、存储、查询、归档等功能基本覆盖了日志管理绝大部分的需求。
具体的功能清单如下图所示，在阿里云的网站上有更加详细的介绍，这里就不进一步展开了。

{{< figure src="/img/aliyun-sls.png" link="/img/aliyun-sls.png" >}}

阿里云日志服务对运行在阿里云上的服务器有原生的支持，但是对于Kubernetes下的容器环境的支持有限，此外对于非阿里云服务器，
用户需要自己完成配置和对接。为了解决容器环境的日志搜集以及方便大量的非阿里云用户使用阿里云日志服务，
我们为`fluent-bit`开发了插件来支持向阿里云日志服务输出日志。

## fluent-bit-aliyun

`fluent-bit`和`fluentd`来自同一家公司。[fluent-bit][fluent-bit]使用C语言开发，比使用Ruby开发的`fluentd`性能更好，资源占用更低。
作为一个新项目，虽然目前支持的插件还没有`fluentd`丰富，但已经有不少团队开始在生产环境中使用它。

`fluent-bit-aliyun`是使用Go语言开发的`fluent-bit`插件，通过API调用将日志输出到阿里云日志服务。
项目地址在[https://github.com/kubeup/fluent-bit-aliyun][fluent-bit-aliyun]。

为了方便使用，我们提供了打包好的Docker镜像，在[https://hub.docker.com/r/kubeup/fluent-bit-aliyun/][fluent-bit-aliyun-docker]

### 在Docker环境中安装

Docker原生支持`fluentd`格式日志输出。我们可以在容器中运行`fluent-bit-aliyun`，然后在启动新容器时进行配置将日志发送给它即可。

{{< highlight bash "lineseparator=<br>" >}}
$ docker run -d --network host -e ALIYUN_ACCESS_KEY=YOUR_ACCESS_KEY -e ALIYUN_ACCESS_KEY_SECRET=YOUR_ACCESS_KEY_SECRET -e ALIYUN_SLS_PROJECT=YOUR_PROJECT -e ALIYUN_SLS_LOGSTORE=YOUR_LOGSTORE -e ALIYUN_SLS_ENDPOINT=cn-hangzhou.log.aliyuncs.com kubeup/fluent-bit-aliyun:master /fluent-bit/bin/fluent-bit -c /fluent-bit/etc/fluent-bit-forwarder.conf -e /fluent-bit/out_sls.so
$ docker run --log-driver=fluentd -d nginx
{{< /highlight >}}

如果在启动Docker Daemon时进行配置，还可以默认将所有日志发送到阿里云日志服务。

### 在Kubernetes环境中安装

在Kubernetes环境中，我们使用`DaemonSet`在集群中的所有`Node`上部署`fluent-bit-aliyun`，它将搜集每台服务器上所有Pod所输出的日志。
`fluent-bit`内置的`kubernetes`过滤器会将Pod的元数据附加到日志上。

首先，我们创建一个新的`Secret`来保存所有的配置信息：

{{< highlight bash "lineseparator=<br>" >}}
$ kubectl create secret generic fluent-bit-config --namespace=kube-system --from-literal=ALIYUN_ACCESS_KEY=YOUR_ACCESS_KEY --from-literal=ALIYUN_ACCESS_KEY_SECRET=YOUR_ACCESS_KEY_SECRET --from-literal=ALIYUN_SLS_PROJECT=YOUR_PROJECT --from-literal=ALIYUN_SLS_LOGSTORE=YOUR_LOGSTORE --from-literal=ALIYUN_SLS_ENDPOINT=cn-hangzhou.log.aliyuncs.com
{{< /highlight >}}

接下来部署`DaemonSet`:

{{< highlight bash "lineseparator=<br>" >}}
$ kubectl create -f https://raw.githubusercontent.com/kubeup/fluent-bit-aliyun/master/fluent-bit-daemonset.yaml
{{< /highlight >}}

我们可以使用`kubectl`来检查部署情况：

{{< highlight bash "lineseparator=<br>" >}}
$ kubectl get pods --namespace=kube-system
{{< /highlight >}}

### 在阿里云中查看日志

当日志发送到阿里云之后，可以通过管理界面的日志预览功能确认日志搜集和发送的正确性。

{{< figure src="/img/sls-preview.png" link="/img/sls-preview.png" >}}

在日志查询中开启索引后，可以进行复杂的过滤和查询。

{{< figure src="/img/sls-search.png" link="/img/sls-search.png" >}}

### 配置日志归档

阿里云还提供了在`ELK`方案中缺失的归档功能，只需要简单配置即可开通。

{{< figure src="/img/sls-export.png" link="/img/sls-export.png" >}}

具体的设置方案以及其他相关功能，在[阿里云有详细的文档说明][sls-doc]，这里就不过多展开了。

## 总结

本文介绍了使用`ELK`管理日志可能遇到的挑战，同时提出了新的基于阿里云日志服务以及`fluent-bit-aliyun`管理日志的办法。
新的办法有如下特点：

- 不再依赖`Elasticsearch`，减少大量计算资源消耗。`fluent-bit`的资源占用也远远低于`fluentd`，可以随着任务Pod部署
- 当负载增加时，仅需要在阿里云添加更多的Shard即可，伸缩性更好
- SaaS模式的计费方式，根据使用量计费，大部分情况下可以降低运行成本
- 依赖阿里云日志服务的扩展功能，可以实现基于日志的消息处理总线，架构上更加灵活
- 基于开源系统搭建，仅替换了`fluent-bit`的输出插件，可以复用input和filter插件。当需要切换后端时，前端无需修改
- 内置归档功能。只需要简单配置，即可将日志输出到OSS长期保存
- 同时支持阿里云ECS以及阿里云以外的服务器，对于阿里云以外的服务器，可以将阿里云日志服务作为SaaS来使用

`fluent-bit-aliyun`的项目地址在[https://github.com/kubeup/fluent-bit-aliyun][fluent-bit-aliyun]，欢迎大家试用和反馈。

[elasticsearch]: https://www.elastic.co/products/elasticsearch
[logstash]: https://www.elastic.co/products/logstash
[kibana]: https://www.elastic.co/products/kibana
[fluentd]: http://www.fluentd.org/
[fluent-bit]: http://fluentbit.io/
[fluent-bit-aliyun]: https://github.com/kubeup/fluent-bit-aliyun
[elasticsearch-operator]: https://github.com/upmc-enterprises/elasticsearch-operator
[fluent-bit-aliyun-docker]: https://hub.docker.com/r/kubeup/fluent-bit-aliyun/
[sls-doc]: https://help.aliyun.com/document_detail/48869.html
[aliyun-sis]: https://www.aliyun.com/product/sls
