+++
Categories = ["Kubernetes"]
Tags = ["Kubernetes"]
Description = ""
date = "2017-03-24T07:33:00+08:00"
title = "In or Out? Kubernetes一统江湖的野心 - 写在Kubernetes 1.6即将发布之际"

+++
如一切顺利的话，[Kubernetes 1.6将于3月29日发布][k8s-16-release]。虽然比预期延迟了一周，但是赶在了KubeCon之前，
对Kubernetes这个规模的项目来说已经实属不易。为了庆祝1.6版本的发布，撰文一篇讲讲目前Kubernetes生态圈的现状。

自2014年发布以来，Kubernetes发展迅速，从最开始以源自Google最佳实践的容器管理平台亮相，
再与[Docker Swarm][docker-swarm]和[Mesos][mesos]一起争夺容器编排领域的主导位置，到最近开始整合整个容器生态的上下游。
Kubernetes始终保持着小步快跑的节奏，在每个Release当中不断推出新的Feature。
同时Kubernetes背后的组织CNCF还在不断吸收Kubernetes生态圈中的优秀开源项目，解决最终用户在生产部署中所存在的监控、
日志搜集等需求。

如今，Kubernetes已经超越了单纯的容器编排工具，企业选择Kubernetes本质上是拥抱以Kubernetes为核心的云原生最佳实践。
其中包含了网络、存储、计算等运行资源的调度，还涵盖了监控、日志搜集、应用分发、系统架构等研发和运维的操作流程。

{{< figure src="/img/cncf-landscape.jpg" link="/img/cncf-landscape.jpg" >}}

## 容器引擎接口(Container Runtime Interface)

众所周知，[Kubernetes][kubernetes]和[Docker][docker]是既合作又竞争的关系。Kubernetes使用[Docker Engine][docker-engine]作为底层容器引擎，在容器编排领域与[Docker
Swarm][docker-swarm]展开竞争。为了减少对Docker的依赖，同时满足生态中其他容器引擎与Kubernetes集成的需要，Kubernetes制定了[容器引擎接口CRI][cri]。
随后Kubernetes发布了[cri-o项目][cri-o]，开始研发自己的Docker兼容容器引擎。目前已经有Docker，rkt，cri-o三款容器引擎支持CRI接口。
此外支持CRI的还有[Hyper.sh][hyper-sh]主导的[frakti项目][frakti]以及[Mirantis][mirantis]主导的[virtlet项目][virtlet]，
它们为Kubernetes增加了直接管理虚拟机的能力。

CRI的发布将Docker推到了一个非常难受的位置，如果不支持CRI，面临着在Kubernetes体系当中被其他容器引擎所替换的风险。
如果支持CRI，则意味着容器引擎的接口定义被竞争对手所主导，其他容器引擎也可以通过支持CRI来挑战Docker在容器引擎领域的事实标准地位。
最终，为了不被边缘化，Docker只能妥协，选择[将containerd项目捐献给CNCF][containerd-donation]。在同一天，[CoreOS也宣布将rkt项目捐献给CNCF][rkt-donation]。
至此CRI成为了容器引擎接口的统一标准，今后如果有新的容器引擎推出，将首先支持CRI。

## 容器网络接口(Container Network Interface)

因为Kubernetes没有内置容器网络组件，所以每一个Kubernetes用户都需要进行容器网络的选型，给新用户带来了不小的挑战。
从现状来看，不内置网络组件的策略虽然增加了部署的复杂度，但给众多SDN厂商留下了足够的公平竞争空间，从中长期来讲是有利于容器网络领域的良性发展的。

1.0版本的Kubernetes没有设计专门的网络接口，依赖Docker来实现每个Pod拥有独立IP、Pod之间可以不经过NAT互访的网络需要。
随着与Docker的竞争加剧以及Docker主导的[CNM接口][cnm]的推出，Kubernetes也推出了自己的[容器网络接口CNI][cni]。

随着CNI的推出，各家SDN解决方案厂商纷纷表示支持。目前[Flannel][flannel]，[Calico][calico]，[Weave][weave]，[Contiv][contiv]这几款热门项目均已支持CNI，
用户可以根据需要为自己的Kubernetes集群选择适合的网络方案。面对CNI和CNM，主流厂商目前的选择是同时支持，但从中长期来看，
厂商一定会根据各个生态的发展进度来动态配置资源，这时Docker内置的原生网络组件有可能反而会影响和其他网络厂商的协作。

## 容器存储接口(Container Storage Interface)

在统一了容器引擎和容器网络之后，Kubernetes又将触角伸到了存储领域。[目前还在制定过程当中的容器存储接口CSI][csi]有望复制CRI和CNI的成功，
为Kubernetes集群提供可替换的存储解决方案。不论是硬件存储厂商或是软件定义存储解决方案厂商，预计都将积极拥抱CSI。
因为不支持CSI就意味着放弃整个Kubernetes生态圈。

## 软件打包与分发(Packaging and Distribution)

在使用CRI，CNI，CSI解决底层运行环境的抽象以外，Kubernetes还在试图通过[Helm项目][helm]以及[Helm Charts][helm-charts]来统一软件打包与分发的环节。
由于Kubernetes提供了底层的抽象，应用开发者可以利用Kubernetes内置的基础元素将上层应用打包为Chart，用户这时就能使用Helm完成一键安装以及一键升级的操作。

在系统架构越来越复杂的今天，能够方便的将复杂的分布式系统运行起来，无疑为Kubernetes的推广增加了不少亮点。
目前一些常见的开源系统，比如Redis，ElasticSearch等已经可以通过使用官方的Charts进行部署。相信未来会有更多的开源项目加入这个清单。

看到这一块商机的公司，比如CoreOS，[已经推出了自己的软件仓库服务][app-registry-release]。由于这块离最终用户最近，相信未来在这一领域的竞争将会非常激烈。

## 云原生计算基金会(Cloud Native Computing Foundation)

前面列举的案例主要偏重技术解决方案，Kubernetes最有潜力的其实是在幕后团结容器生态中各方力量的[CNCF组织][cncf]。
与同期建立的Docker主导的[OCI组织][oci]相比，当前CNCF不论是在项目数量，会员数量，会员质量等多个方面都明显领先。
可以说CNCF是事实上在推动整个容器生态向前发展的核心力量。

人的力量是最根本的也是最强大的，只有团结到尽可能多的玩家，才能制定出各方都能接受的标准。面对这么多的会员企业，要平衡各方的诉求实在不是容易的事情。
目前CNCF做的还不错，中立的基金会形式似乎更加容易被各方所接受。[最近正在进行决策小组选举的讨论][cncf-election]，有兴趣的朋友可以自行围观。

## 总结

有两句经常听到的话在Kubernetes身上得到了很好的体现，一是没有什么是不能通过增加一个抽象层解决的，二是一流的企业做标准，二流的企业做品牌，三流的企业做产品。
Kubernetes通过在具体实现上增加抽象层，试图为整个容器生态圈建立统一的标准。当标准逐步建立，用户开始依照标准选择解决方案，
将进一步强化Kubernetes位于整个容器生态核心的地位。这时容器生态的上下游将不得不面对，要么选择In拥抱Kubernetes所提出的标准，
要么选择Out被整个生态圈孤立的情况。面对这种选择，想必大部分厂商都将选择In，而更多的厂商加入将进一步强化标准的力量。

可以预见Kubernetes构建的组织、标准、开源项目三层体系，将有望统一容器生态圈的各方力量，而这种统一对最终用户是有益的。
在容器生态中的各个领域，开源的解决方案将与商业解决方案直接竞争，甚至开源解决方案之间也将展开竞争。这种竞争将促进整个容器生态的发展，
由于大家都遵守相同的标准，不论你在最初建设时选择的是哪一套解决方案，将来也可以用更新更好的方案来替换，
规避了商家绑定的风险。希望捐献给CNCF的项目将会越来越多，因为进入CNCF就意味着比其他相同功能的开源项目更加容易获得Kubernetes生态圈的认可。

最后插播一条小广告，为了解决Kubernetes与各个云平台之间的对接问题，我们开源了一款基于Kubernetes对底层云平台进行自动化运维的系统。项目叫做[Archon][archon]，地址在
[https://github.com/kubeup/archon][archon] 。希望Archon可以帮助Kubernetes统一对底层云平台的管理和操作方法，使得用户不论使用哪一家云平台均可以使用相同的方法进行运维和管理，
以便用户可以在多个云平台之间自由的迁移。有兴趣的朋友可以试用并给我们反馈，帮助我们完善。

3月29日，将在德国柏林举办[CloudNativeCon + KubeCon Europe][kubecon]，届时会带来更多关于Kubernetes 1.6的介绍，
对Kubernetes感兴趣的同学可以关注，更多激动人心的消息在等着大家。

[k8s-16-release]: https://groups.google.com/forum/#!msg/kubernetes-dev/u6JfEThKUyY/xmfNtBXtCQAJ
[docker-swarm]: https://docs.docker.com/engine/swarm/
[mesos]: http://mesos.apache.org/
[kubernetes]: https://kubernetes.io/
[docker]: https://www.docker.com/
[docker-engine]: https://docs.docker.com/engine/
[cri]: http://blog.kubernetes.io/2016/12/container-runtime-interface-cri-in-kubernetes.html
[cri-o]: https://github.com/kubernetes-incubator/cri-o
[hyper-sh]: https://hyper.sh/
[frakti]: https://github.com/kubernetes/frakti
[mirantis]: https://www.mirantis.com/
[virtlet]: https://github.com/Mirantis/virtlet
[containerd-donation]: https://blog.docker.com/2017/03/docker-donates-containerd-to-cncf/
[rkt-donation]: https://coreos.com/blog/rkt-container-runtime-to-the-cncf.html
[cnm]: https://github.com/docker/libnetwork/blob/master/docs/design.md
[cni]: https://github.com/containernetworking/cni
[flannel]: https://github.com/coreos/flannel
[calico]: https://www.projectcalico.org/
[weave]: https://github.com/weaveworks/weave
[contiv]: http://contiv.github.io/
[csi]: https://docs.google.com/document/d/1JMNVNP-ZHz8cGlnqckOnpJmHF-DNY7IYP-Di7iuVhQI/edit
[helm]: https://github.com/kubernetes/helm
[helm-charts]: https://github.com/kubernetes/charts
[app-registry-release]: https://coreos.com/blog/quay-application-registry-for-kubernetes.html
[cncf]: https://www.cncf.io/
[oci]: https://www.opencontainers.org/
[cncf-election]: https://groups.google.com/forum/#!msg/kubernetes-dev/4e8WOnMvZC0/eZIvrFYlCAAJ
[archon]: https://github.com/kubeup/archon
[kubecon]: http://events.linuxfoundation.org/events/cloudnativecon-and-kubecon-europe
