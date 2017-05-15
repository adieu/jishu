+++
title = "基于Kubernetes的分布式压力测试方案"
Categories = ["Kubernetes"]
Tags = ["Kubernetes","tsung"]
Description = ""
date = "2017-05-13T23:53:02+08:00"

+++
压力测试是用来检测系统承载能力的有效手段。在系统规模较小的时候，在一台空闲的服务器上使用[ab]，[wrk]，[siege]
等工具发起一定量的并发请求即可得到一个初步的测试结果。但在系统复杂度逐步提高，特别是引入了负载均衡，
微服务等架构后，单机的压力测试方案不再可用，企业需要搭建分布式测试集群或者付费使用外部供应商提供的压力测试服务。

不管是采取自主搭建或是采用外购的手段，都会面临系统使用率不高以及成本的问题。依赖于Kubernetes的动态资源调度功能，
以及Kubernetes集群的动态伸缩特性，我们可以充分利用集群内的闲置计算资源，在需要进行压力测试时启动测试节点，
在测试结束后释放资源给其他业务，甚至通过集群扩容和缩容临时为压力测试提供更多的计算资源。

支持分布式部署的压力测试工具有多款，今天我们将介绍在Kubernetes集群中使用Tsung进行压力测试的方法。

## Tsung

[Tsung]是一款使用[Erlang]开发的分布式压力测试系统，它支持HTTP，Jabber，MySQL等多种协议，可以用于不同场景的压力测试。
与传统的针对单一测试目标重复请求的压测系统不同，Tsung更侧重于模拟真实使用场景。测试人员指定新用户到访频率，
并设定一系列的模拟操作请求。所有的Slave节点将在Master节点的统一调度下，按照到访频率创建虚拟用户，并发送操作请求。
所有请求的耗时以及错误信息将传回Master节点用于统计和报表。

选择Tsung主要有三方面的考虑：

- 性能优越。Erlang语言天生就是为高并发网络系统设计的。合理配置的Tsung集群可以实现100W以上的并发流量。
- 描述式的配置方法。不论简单还是复杂，Tsung均统一使用XML文件描述整个测试步骤以及各种参数。这样可以在集群架构保持不变时完成各种测试。
- 模拟真实用户的测试理念。在真实场景中，用户会访问系统的各项功能。只有支持模拟真实用户的压力测试系统才能比较准确的反应系统各个部分在压力下的状态，找到瓶颈环节。

由于Tsung采取的工作模式是在配置中注明Slave地址，然后由Master连上Slave完成测试，传统的部署方法是启动多台物理机或者虚拟机，
分别配置它们。在这种工作模式下，会产生大量的运维工作，同时这些计算资源在不进行测试时处于闲置状态，降低了硬件使用率。

## 在Kubernetes中使用容器运行Tsung

利用Kubernetes强大的调度能力，我们可以将Tsung运行在容器当中，动态的启动和删除。当需要提高测试规模时，
我们仅需要使用[Archon]等已有的工具对集群进行扩容，就可以很方便的一键扩容Slave的数量，几乎没有增加任何的运维负担。

以下是具体的操作流程：

### 创建Namespace

{{< highlight console "lineseparator=<br>" >}}
$ kubectl create namespace tsung
{{< /highlight >}}

### 使用StatefulSet部署Tsung Slave

这里不能使用`Deployment`，只有使用`StatefulSet`才能在为每一个`Pod`分配独立的内部域名，供Master连接。

将以下文件保存为`tsung-slave-svc.yaml`

{{< highlight yaml "lineseparator=<br>" >}}
apiVersion: v1
kind: Service
metadata:
  labels:
    run: tsung-slave
  name: tsung-slave
spec:
  clusterIP: None
  selector:
    run: tsung-slave
  ports:
  - port: 22
  type: ClusterIP
{{< /highlight >}}

将以下文件保存为`tsung-slave.yaml`

{{< highlight yaml "lineseparator=<br>" >}}
apiVersion: apps/v1beta1
kind: StatefulSet
metadata:
  name: tsung-slave
spec:
  serviceName: "tsung-slave"
  replicas: 1
  template:
    metadata:
      labels:
        run: tsung-slave
    spec:
      containers:
      - name: tsung
        image: ddragosd/tsung-docker:1.6.0
        env:
        - name: SLAVE
          value: "true"
{{< /highlight >}}

在Kubernetes中创建相应的资源

{{< highlight console "lineseparator=<br>" >}}
$ kubectl create -f tsung-slave-svc.yaml --namespace tsung
$ kubectl create -f tsung-slave.yaml --namespace tsung
{{< /highlight >}}

这里我们设置了`StatefulSet`的`serviceName`字段，这样启动的`Pod`在集群内部就可以通过`tsung-slave-0.tsung-slave.tsung.svc.cluster.local`
这个域名访问到。

### 使用StatefulSet部署Tsung Master

与Slave类似，Master节点也要求可以在集群内部通过域名访问。所以我们依然需要使用`StatefulSet`来运行。

将以下文件保存为`tsung-config.yaml`

{{< highlight yaml "lineseparator=<br>" >}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: tsung-config
data:
  config.xml: |
    <?xml version="1.0" encoding="utf-8"?>
    <!DOCTYPE tsung SYSTEM "/usr/share/tsung/tsung-1.0.dtd" []>
    <tsung loglevel="warning">
      <clients>
        <client host="tsung-slave-0.tsung-slave.tsung.svc.cluster.local" />
      </clients>
      <servers>
        <server host="target" port="8000" type="tcp"/>
      </servers>
      <load>
        <arrivalphase phase="1" duration="1" unit="minute">
          <users arrivalrate="100" unit="second"/>
        </arrivalphase>
      </load>
    <sessions>
      <session name="es_load" weight="1" type="ts_http">
        <for from="1" to="10" incr="1" var="counter">
          <request> <http url="/" method="GET" version="1.1"></http> </request>
        </for>
      </session>
    </sessions>
    </tsung>
{{< /highlight >}}

将以下文件保存为`tsung-master-svc.yaml`

{{< highlight yaml "lineseparator=<br>" >}}
apiVersion: v1
kind: Service
metadata:
  labels:
    run: tsung-master
  name: tsung-master
spec:
  clusterIP: None
  selector:
    run: tsung-master
  ports:
  - port: 8091
  sessionAffinity: None
  type: ClusterIP
{{< /highlight >}}

将以下文件保存为`tsung-master.yaml`

{{< highlight yaml "lineseparator=<br>" >}}
apiVersion: apps/v1beta1
kind: StatefulSet
metadata:
  name: tsung-master
spec:
  serviceName: "tsung-master"
  replicas: 1
  template:
    metadata:
      labels:
        run: tsung-master
    spec:
      containers:
      - name: tsung
        image: ddragosd/tsung-docker:1.6.0
        env:
        - name: ERL_SSH_PORT
          value: "22"
        args:
        - -k
        - -f
        - /tsung/config.xml
        - -F
        - start
        volumeMounts:
        - mountPath: /tsung
          name: config-volume
      volumes:
      - configMap:
          name: tsung-config
        name: config-volume
{{< /highlight >}}

在Kubernetes中创建相应的资源

{{< highlight console "lineseparator=<br>" >}}
$ kubectl create -f tsung-config.yaml --namespace tsung
$ kubectl create -f tsung-master-svc.yaml --namespace tsung
$ kubectl create -f tsung-master.yaml --namespace tsung
{{< /highlight >}}

当Tsung Master的容器被启动后，它会自动开始运行压力测试。在上面的列子中，Tsung将向`http://target:8000`发起为期1分钟的压力测试，
在测试期间，每秒钟产生100个模拟用户，每个用户访问10次目标地址。

我们将Tsung的配置文件用`ConfigMap`注入到了Master容器当中，这样用户仅需要修改`tsung-config.yaml`的内容，
就可以方便的定义符合自己要求的测试。在实际使用过程中，用户可以自主调整测试持续时间，虚拟用户产生速度，
目标地址等参数。用户还可以通过修改`tsung-slave.yaml`中`replicas`的数值，并将更多的Slave地址加入到`tsung-config.yaml`当中，
来获得更多的测试资源，进一步增加负载量。

在Master的运行参数中，我们使用的`-k`参数将保持Master在测试完成后仍处于运行状态，这样用户可以通过`8091`端口访问到测试结果。

{{< highlight console "lineseparator=<br>" >}}
$ kubectl port-forward tsung-master-0 -n tsung 8091:8091
{{< /highlight >}}

之后在本地通过浏览器访问`http://localhost:8091`即可打开Tsung内置的报表界面。如下图所示：

{{< figure src="/img/tsung-report.png" link="/img/tsung-report.png" >}}

另外`-F`参数让Master使用`FQDN`地址访问Slave节点，这项参数非常关键，缺少它将导致Master无法正常连接上Slave。

### 资源回收

测试结束后，用户可以使用报表界面查看和保存结果。当所有结果被保存下来之后，可以直接删除`Namespace`完成资源回收。

{{< highlight console "lineseparator=<br>" >}}
$ kubectl delete namespace tsung
{{< /highlight >}}

这样所有的Tsung相关配置和容器均会被删除。当下次需要测试时，可以从一个全新的状态开始新一次测试。

## 总结

本文主要介绍了在Kubernetes中部署Tsung这款分布式压力测试系统的方法。其中使用`StatefulSet`配合`-F`参数的方法，
使得Master和Slave可以顺利的使用域名找到对方，成功的解决了在容器中运行Tsung会遇到的访问问题。

原本需要专业的运维工程师投入不少时间才能搭建起来的Tsung测试集群，在Kubernetes中几乎可以毫不费力的启动起来，
完成测试。这种使用调度器充分利用集群空闲资源，使用后及时释放供其他系统使用的方法，也充分体现了Kubernetes的优越性。

在下一篇分享中，我们将使用本文所描述的测试系统，对主流的Python WSGI服务器进行压力测试，用以对比各个服务器的性能指标。
希望通过这种实战演示的方式，帮助大家深入了解Tsung以及Kubernetes。敬请期待。

[ab]: https://httpd.apache.org/docs/2.4/programs/ab.html
[wrk]: https://github.com/wg/wrk
[siege]: https://github.com/JoeDog/siege
[Tsung]: http://tsung.erlang-projects.org/
[Erlang]: https://www.erlang.org/
[Archon]: https://github.com/kubeup/archon
