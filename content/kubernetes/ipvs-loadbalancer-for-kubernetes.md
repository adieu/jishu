+++
Description = ""
date = "2017-04-25T00:04:28+08:00"
title = "使用IPVS实现Kubernetes入口流量负载均衡"
Categories = ["Kubernetes"]
Tags = ["Kubernetes","ipvs", "loadbalancer"]

+++
新搭建的Kubernetes集群如何承接外部访问的流量，是刚上手Kubernetes时常常会遇到的问题。
在公有云上，官方给出了比较直接的答案，使用`LoadBalancer`类型的Service，利用公有云提供的负载均衡服务来承接流量，
同时在多台服务器之间进行负载均衡。而在私有环境中，如何正确的将外部流量引入到集群内部，却暂时没有标准的做法。
本文将介绍一种基于IPVS来承接流量并实现负载均衡的方法，供大家参考。

## IPVS

[IPVS]是[LVS]项目的一部分，是一款运行在Linux kernel当中的4层负载均衡器，性能异常优秀。
根据[这篇文章][ipvs-performance]的介绍，使用调优后的内核，可以轻松处理每秒10万次以上的转发请求。目前在中大型互联网项目中，
IPVS被广泛的使用，用于承接网站入口处的流量。

## Kubernetes Service

[Service][kubernetes-service]是Kubernetes的基础概念之一，它将一组Pod抽象成为一项服务，统一的对外提供服务，在各个Pod之间实现负载均衡。
Service有多种类型，最基本的`ClusterIP`类型解决了集群内部访问服务的需求，`NodePort`类型通过Node节点的端口暴露服务，
再配合上`LoadBalancer`类型所定义的负载均衡器，实现了流量经过前端负载均衡器分发到各个Node节点暴露出的端口，
再通过`iptables`进行一次负载均衡，最终分发到实际的Pod上这个过程。

在Service的Spec中，`externalIPs`字段平常鲜有人提到，当把IP地址填入这个字段后，`kube-proxy`会增加对应的`iptables`规则，
当有以对应IP为目标的流量发送到Node节点时，`iptables`将进行NAT，将流量转发到对应的服务上。一般情况下，
很少会遇到服务器接受非自身绑定IP流量的情况，所以`externalIPs`不常被使用，但配合网络层的其他工具，它可以实现给Service绑定外部IP的效果。

今天我们将使用`externalIPs`配合IPVS的DR(Direct Routing)模式实现将外部流量引入到集群内部，同时实现负载均衡。

## 环境搭建

为了演示，我们搭建了4台服务器组成的集群。一台服务器运行IPVS，扮演负载均衡器的作用，一台服务器运行Kubernetes Master组件，
其他两台服务器作为Node加入到Kubernetes集群当中。搭建过程这里不详细介绍，大家可以参考相关的文档。

所有服务器在`172.17.8.0/24`这个网段中。服务的VIP我们设定为`172.17.8.201`。整体架构如下图所示：

{{< figure src="/img/ipvs-kubernetes.png" link="/img/ipvs-kubernetes.png" >}}

接下来让我们来配置IPVS和Kubernetes。

## 使用externalIPs暴露Kubernetes Service

首先在集群内部运行2个nginx Pod用作演示。

{{< highlight console "lineseparator=<br>" >}}
$ kubectl run nginx --image=nginx --replicas=2
{{< /highlight >}}

再将它暴露为Service，同时设定`externalIPs`字段

{{< highlight console "lineseparator=<br>" >}}
$ kubectl expose deployment nginx --port 80 --external-ip 172.17.8.201
{{< /highlight >}}

查看`iptables`配置，确认对应的`iptables`规则已经被加入。

{{< highlight console "lineseparator=<br>" >}}
$ sudo iptables -t nat -L KUBE-SERVICES -n
Chain KUBE-SERVICES (2 references)
target     prot opt source               destination
KUBE-SVC-4N57TFCL4MD7ZTDA  tcp  --  0.0.0.0/0            10.3.0.156           /* default/nginx: cluster IP */ tcp dpt:80
KUBE-MARK-MASQ  tcp  --  0.0.0.0/0            172.17.8.201         /* default/nginx: external IP */ tcp dpt:80
KUBE-SVC-4N57TFCL4MD7ZTDA  tcp  --  0.0.0.0/0            172.17.8.201         /* default/nginx: external IP */ tcp dpt:80 PHYSDEV match ! --physdev-is-in ADDRTYPE match src-type !LOCAL
KUBE-SVC-4N57TFCL4MD7ZTDA  tcp  --  0.0.0.0/0            172.17.8.201         /* default/nginx: external IP */ tcp dpt:80 ADDRTYPE match dst-type LOCAL
KUBE-SVC-NPX46M4PTMTKRN6Y  tcp  --  0.0.0.0/0            10.3.0.1             /* default/kubernetes:https cluster IP */ tcp dpt:443
KUBE-NODEPORTS  all  --  0.0.0.0/0            0.0.0.0/0            /* kubernetes service nodeports; NOTE: this must be the last rule in this chain */ ADDRTYPE match dst-type LOCAL
{{< /highlight >}}

## 配置IPVS实现流量转发

首先在IPVS服务器上，打开`ipv4_forward`。

{{< highlight console "lineseparator=<br>" >}}
$ sudo sysctl -w net.ipv4.ip_forward=1
{{< /highlight >}}

接下来加载IPVS内核模块。

{{< highlight console "lineseparator=<br>" >}}
$ sudo modprobe ip_vs
{{< /highlight >}}

将VIP绑定在网卡上。

{{< highlight console "lineseparator=<br>" >}}
$ sudo ifconfig eth0:0 172.17.8.201 netmask 255.255.255.0 broadcast 172.17.8.255
{{< /highlight >}}

再使用`ipvsadm`来配置IPVS，这里我们直接使用Docker镜像，避免和特定发行版绑定。

{{< highlight console "lineseparator=<br>" >}}
$ docker run --privileged -it --rm --net host luizbafilho/ipvsadm
/ # ipvsadm
IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
/ # ipvsadm -A -t 172.17.8.201:80
/ # ipvsadm -a -t 172.17.8.201:80 -r 172.17.8.11:80 -g
/ # ipvsadm -a -t 172.17.8.201:80 -r 172.17.8.12:80 -g
/ # ipvsadm
IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
TCP  172.17.8.201:http wlc
  -> 172.17.8.11:http             Route   1      0          0
  -> 172.17.8.12:http             Route   1      0          0
{{< /highlight >}}

可以看到，我们成功建立了从VIP到后端服务器的转发。

## 验证转发效果

首先使用`curl`来测试是否能够正常访问nginx服务。

{{< highlight console "lineseparator=<br>" >}}
$ curl http://172.17.8.201
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
    body {
        width: 35em;
        margin: 0 auto;
        font-family: Tahoma, Verdana, Arial, sans-serif;
    }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
{{< /highlight >}}

接下来在`172.17.8.11`上抓包来确认IPVS的工作情况。

{{< highlight console "lineseparator=<br>" >}}
$ sudo tcpdump -i any port 80
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on any, link-type LINUX_SLL (Linux cooked), capture size 262144 bytes
04:09:07.503858 IP 172.17.8.1.51921 > 172.17.8.201.http: Flags [S], seq 2747628840, win 65535, options [mss 1460,nop,wscale 5,nop,nop,TS val 1332071005 ecr 0,sackOK,eol], length 0
04:09:07.504241 IP 10.2.0.1.51921 > 10.2.0.3.http: Flags [S], seq 2747628840, win 65535, options [mss 1460,nop,wscale 5,nop,nop,TS val 1332071005 ecr 0,sackOK,eol], length 0
04:09:07.504498 IP 10.2.0.1.51921 > 10.2.0.3.http: Flags [S], seq 2747628840, win 65535, options [mss 1460,nop,wscale 5,nop,nop,TS val 1332071005 ecr 0,sackOK,eol], length 0
04:09:07.504827 IP 10.2.0.3.http > 10.2.0.1.51921: Flags [S.], seq 3762638044, ack 2747628841, win 28960, options [mss 1460,sackOK,TS val 153786592 ecr 1332071005,nop,wscale 7], length 0
04:09:07.504827 IP 10.2.0.3.http > 172.17.8.1.51921: Flags [S.], seq 3762638044, ack 2747628841, win 28960, options [mss 1460,sackOK,TS val 153786592 ecr 1332071005,nop,wscale 7], length 0
04:09:07.504888 IP 172.17.8.201.http > 172.17.8.1.51921: Flags [S.], seq 3762638044, ack 2747628841, win 28960, options [mss 1460,sackOK,TS val 153786592 ecr 1332071005,nop,wscale 7], length 0
04:09:07.505599 IP 172.17.8.1.51921 > 172.17.8.201.http: Flags [.], ack 1, win 4117, options [nop,nop,TS val 1332071007 ecr 153786592], length 0
{{< /highlight >}}

可以看到，由客户端`172.17.8.1`发送给`172.17.8.201`的封包，经过IPVS的中转发送给了`172.17.8.11`这台服务器，
并经过NAT后发送给了`10.2.0.3`这个Pod。返回的封包不经过IPVS服务器直接从`172.17.8.11`发送给了`172.17.8.1`。
说明IPVS的DR模式工作正常。重复多次测试可以看到流量分别从`172.17.8.11`和`172.17.8.12`进入，再分发给不同的Pod，
说明负载均衡工作正常。

与传统的IPVS DR模式配置不同的是，我们并未在承接流量的服务器上执行绑定VIP，再关闭ARP的操作。
那是因为对VIP的处理直接发生在iptables上，我们无需在服务器上运行程序来承接流量，iptables会将流量转发到对应的Pod上。

使用这种方法来承接流量，仅需要配置`externalIPs`为VIP即可，无需对服务器做任何特殊的设置，使用起来相当方便。

## 总结

在本文中演示了使用IPVS配合externalIPs实现将外部流量导入到Kubernetes集群中，并实现负载均衡的方法。
希望可以帮助大家理解IPVS和externalIPs的工作原理，以便在恰当的场景下合理使用这两项技术解决问题。
实际部署时，还需要考虑后台服务器可用性检查，IPVS节点主从备份，水平扩展等问题。在这里就不详细介绍了。

在Kubernetes中还有许多与externalIPs类似的非常用功能，有些甚至是使用Annotation来进行配置，将来有机会再进一步分享。

最后插播下广告，为了实现私有环境下的Kubernetes集群自动化部署和运维，我们为[Archon系统][archon]增加了PXE管理物理机的支持，
相应的配置案例在[这里][matchbox-example]。如果使用过程中有任何问题，欢迎跟我们联系。

[IPVS]: http://www.linuxvirtualserver.org/software/ipvs.html
[LVS]: http://www.linuxvirtualserver.org
[kubernetes-service]: https://kubernetes.io/docs/concepts/services-networking/service/
[ipvs-performance]: https://www.lvtao.net/server/taobao-linux-kernel.html
[archon]: https://github.com/kubeup/archon
[matchbox-example]: https://github.com/kubeup/archon/tree/master/example/k8s-matchbox
