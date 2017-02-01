+++
date = "2017-01-29T21:33:29+08:00"
title = "也许您的Kubernetes集群并不需要SDN"
Categories = ["Kubernetes"]
Tags = ["Kubernetes","flannel", "SDN", "hostroutes", "kubenet"]
Description = ""

+++

[SDN]是`Software-defined networking`的缩写。在许多介绍Kubernetes的文档，特别是安装文档中，
当介绍到Kubernetes所需的容器网络时常常会提到这个缩写，告知用户需要使用某种SDN技术用以解决“每个Pod有独立IP，
Pod之间可以不经过NAT直接互访”这一Kubernetes集群最基本的技术要求。

大多数非网络工程师背景的技术人员对SDN这个概念会比较陌生，当读到这个段落时，往往会选择把它当作Kubernetes的底层依赖，
照着文档所推荐的流程安装一款SDN工具，比如[Flannel]，[Calico]，[Weave]等。由于不了解这些工具的原理，同时缺乏实际的使用经验，
当出现文档以外的异常情况时，整个安装流程就卡住了。SDN俨然成为了Kubernetes大规模普及的拦路虎。

那些按照文档顺利搭建起来的集群当中，还有不少使用了并不适合该集群所处环境的SDN技术，造成了额外的运维负担以及潜在的安全风险。
让我们不得不思考一个问题，怎样才是正确的在Kubernetes集群中使用SDN技术的方法？

今天我们来详细聊聊这个话题。

## 结论先行

在大多数的Kubernetes集群中，都不需要使用SDN技术，Kubernetes的容器网络要求可以使用更加简单易懂的技术来实现，
只有当企业有特定的安全或者配置要求时，才需要使用SDN技术。SDN应当作为一个附加选项，用以解决特定的技术问题。

## 理解Kubernetes的容器网络

下图是一张Kubernetes容器网络的示意图

{{< figure src="/img/kubernetes-networking.png" link="/img/kubernetes-networking.png" >}}

可以看到在图中，每台服务器上的容器有自己独立的IP段，各个服务器之间的容器可以根据目标容器的IP地址进行访问。

为了实现这一目标，重点解决以下这两点：

 - 各台服务器上的容器IP段不能重叠，所以需要有某种IP段分配机制，为各台服务器分配独立的IP段
 - 从某个Pod发出的流量到达其所在服务器时，服务器网络层应当具备根据目标IP地址将流量转发到该IP所属IP段所对应的目标服务器的能力。

总结起来，实现Kubernetes的容器网络重点需要关注两方面，分配和路由。

## Flannel的工作方式

这里我们以比较常见的Flannel为例子，看看SDN系统是如何解决分配和路由的问题的。

下图是Flannel的架构示意图

{{< figure src="/img/flannel-networking.jpg" link="/img/flannel-networking.jpg" >}}

可以看到Flannel依赖etcd实现了统一的配置管理机制。当一台服务器上的Flannel启动时，它会连接所配置的etcd集群，
从中取到当前的网络配置以及其他已有服务器已经分配的IP段，并从未分配的IP段中选取其中之一作为自己的IP段。
当它将自己的分配记录写入etcd之后，其他的服务器会收到这条新记录，并更新本地的IP段映射表。

Flannel的IP段分配发生在各台服务器上，由`flannel`进程将结果写入到etcd中。路由也由Flannel完成，网络流量先进入Flannel控制的Tunnel中，
由Flannel根据当前的IP段映射表转发到对应的服务器上。

需要指出的是Flannel有多种backend，另外新增的`kube-subnet-mgr`参数会导致Flannel的工作方式有所不同，在这里就不详细展开了。
有兴趣的朋友可以去查阅Flannel的文档以及源代码了解更多的细节。

## 更见简化的网络配置方法

Flannel的工作方式有2点是需要注意的。一是所有服务器上运行的Flannel均需要etcd的读写权限，不利于权限的隔离和安全防护。
二是许多教程中所使用的默认backend类型为vxlan，虽然它使用了内核中的vxlan模块，造成的性能损失并不大，
但是在常见的二层网络的环境中，其实并不需要使用Tunnel技术，直接利用路由就可以实现流量的转发，
这时使用hostgw模式就可以达成目标。

大部分的Kubernetes集群服务器数量并不会超过100台，不论是在物理机房当中或是利用IaaS提供的VPC技术，我们会把这些服务器均放在同一个网段，
这时我们可以去掉Flannel这一层，直接使用Kubernetes内置的`kubenet`功能，配合上我们为Kubernetes定制的`hostroutes`工具，
即可实现容器网络的要求。

### kubenet

[kubenet]是`kubelet`内置的网络插件中的一个，它非常的简单，会根据当前服务器对应的Node资源上的`PodCIDR`字段所设的IP段，配置一个本地的网络接口`cbr0`，
在新的Pod启动时，从IP段中分配一个空闲的IP，用它创建容器的网络接口，再将控制权交还给`kubelet`，完成后续的Pod创建流程。

由于`kubenet`会自己管理容器网络接口，所以使用`kubenet`时，不需要修改任何的Docker配置，仅需要在启动`kubelet`时，传入`--network-plugin=kubenet`
参数即可。

### allocate-node-cidrs

`allocate-node-cidrs`是[controller-manager]的一个参数，当它和`cluster-cidr`参数共同使用的时候，`controller-manager`会为所有的Node资源分配容器IP段，
并将结果写入到PodCIDR字段。

### hostroutes

[hostroutes]是我们为`kubenet`开发的一个配套小工具，它也非常的简单，它会watch所有的Node资源的变化，用所有Node资源的`PodCIDR`字段来配置服务器本地路由表。
这时所有Pod发出的流量将通过Linux自带的路由功能进行转发，性能优异。Linux的路由功能也是大部分技术人员已经掌握的技能，理解维护起来没有任何负担。

在这一简化的模式下，`controller-manager`负责分配容器IP段，`kubenet`负责本地网络接口的控制，`hostroutes`负责路由。
我们最大程度使用了Kubernetes已有的功能，并且用`hostroutes`来解决`kubenet`只管网络接口不管路由的问题。整个方案中，
需要写入权限的仅有部署在master节点的`controller-manager`，运行在Node节点上的`kubenet`和`hostroutes`均只需要读取权限即可，增强了安全性。
另外此方案将Kubernetes作为唯一的配置来源，去除了对etcd的依赖，简化了配置，降低了运维负担和安全风险。

不同的技术方案虽说实现细节不同，但是只要围绕着分配和路由这两个关键点进行比较，我们就可以更加明确的在不同方案之间进行选择。

## 容器网络技术方案选型推荐

任何的技术方案都离不开场景，在这里我们根据不同的场景给大家推荐几种技术方案：

 - 单服务器：不需要网络组件，使用Docker自带的网络即可
 - 小规模集群：使用`kubenet` + `hostroutes`，简单、易配合管理
 - 云环境中的小规模集群：使用`kubenet` + master组件上运行的网络控制器，充分利用IaaS所提供的VPC环境中的路由功能，简化网络配置
 - 服务器不在一个网段的集群：使用Flannel提供的vxlan或者其他类似的Tunnel技术
 - 安全要求高的集群：使用Calico或者[Open vSwitch]等支持Policy的SDN技术

## 总结

在本篇文章中，我们探讨了Kubernetes的容器网络的工具方式，并以Flannel为案例分析了已有的SDN解决方案，并提出了适合小规模集群的`kubenet`
+ `hostroutes`的解决方案。希望可以帮助读者理清在Kubernetes集群搭建过程中容器网络这一部分的思路，不再因为容器网络影响了Kubernetes的整体使用。

在实际工作中，各个企业对集群的要求都有自己的特点，技术人员需要根据企业的需要，充分比较现有的各种方案的优劣，选择最适合的方案。
直接照抄教程的搭建方式会为将来的运行埋下隐患，应当尽可能的避免。

[SDN]: https://en.wikipedia.org/wiki/Software-defined_networking
[Flannel]: https://github.com/coreos/flannel
[Calico]: https://www.projectcalico.org/
[Weave]: https://github.com/weaveworks/weave
[kubenet]: https://kubernetes.io/docs/admin/network-plugins/#kubenet
[controller-manager]: https://kubernetes.io/docs/admin/kube-controller-manager/
[hostroutes]: https://github.com/kubeup/hostroutes
[Open vSwitch]: http://openvswitch.org/
