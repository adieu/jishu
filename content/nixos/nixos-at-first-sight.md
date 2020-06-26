---
Categories: ["NixOS"]
Tags: ["Nix", "NixOS", "Linux"]
Description: ""
title: "Nix(OS)挖坑笔记 - (1)初识"
date: 2020-06-16T13:34:04+08:00
---

最近得空体验了一下[Nix(OS)][nixos]，折腾过程中解决了一些遇到的问题，同时挖了更多的坑。做下笔记记录下整个过程。希望将来有机会把坑给填上。

使用Nix(OS)这一写法的原因是Nix和NixOS是相关联的不同的项目，为了方便起见我们先把它们作为一个整体来理解，将来再逐步厘清它们各自的功能和定位。

由于是从零开始慢慢摸索，难免出错，欢迎大家指正。本文定位于个人主观角度的经验分享，仅供大家参考。

## 初识

最开始接触Nix(OS)是在[SHLUG][shlug]的[Yu老师][yuchangyuan]安利之下去翻了下它的[官网和文档][nixos]。第一感觉是不明觉厉，为了使用Nix这个包管理工具，竟然要学习一门新的函数式编程语言，而NixOS这个Linux发行版看上去跟以往接触的任何一个发行版都不同，整体来看像是一个面向Geek和Power User的项目。

## 问题

每当我接触一个全新的项目，在投入时间去弄清楚各种技术细节之前，有两个最基本的问题是我想先弄明白的：1) 这个项目有哪些独特的功能和价值点 2) 在哪些场景下会需要利用这些功能和价值点来解决遇到的问题

## 特性

要回答这两个问题，我打算从特性入手。官网上列出了多条Nix(OS)的特性，其中有几项吸引了我的注意。虽然暂时还没法完全读懂Nix(OS)的文档和代码，但是在文档的介绍下，结合在其他项目上积累的经验，我试着来理解Nix(OS)的设计思路。

### 申明式 (Declarative)

理解Declarative特性可以借鉴[Kubernetes][kubernetes]的设计思路。在Kubernetes中，用户用`yaml`文件来描述`Pod`，`Service`等集群的状态，将这些描述文件提交给Kubernetes后，控制器程序会负责具体的集群变更。对应的，在Nix中用户的主要职责是使用声明式的方法来定义自己使用的软件包以及各软件包的参数。声明所使用的语言是名为Nix的语言。将源文件交给名为Nix的包管理工具后，程序会按照用户的要求安装相应的软件包，并更新用户环境。当用户修改描述文件后再次运行Nix，程序会根据当前的描述安装和激活新的软件包，或者取消激活老的软件包，使得当前用户环境满足用户声明。而NixOS则更进一步，用户可以直接用Nix语言描述整个操作系统。需要指出的是，就像Kubernetes中`Deployment`版本升级导致的`Pod`滚动升级一样，Nix并不会在老的软件包上进行修改得到新的软件包，而是完全新安装新的软件包。这里用到了Immutable这一特性，接下来我们来具体分析一下。

### 不可变 (Immutable)

Immutable并不是指系统一旦安装完成就变为只读不允许修改，而是指一个软件包以及它全部的依赖在其存续期间不变。让我们用[Git][git]作为参照物来理解Nix(OS)的Immutable特性，当我们修改一个被Git管理的文件时，修改后的版本会在新创建的`commit`中被引用，而老版本并不会被清除，用户可以通过老的`commit`哈希找到老版本。Nix(OS)中每一个软件包可以声明自己所依赖的软件包，这些间接被引入的上游软件包也会一同被安装。所有的软件包在一起构成由软件包为节点构成的依赖树。由于每个软件包在自己独立的目录中，不同版本，不同参数的同一个软件包可以并存，分别被依赖它的不同下游软件包所使用。当安装新的软件包，或者更新已有软件包时，会在原依赖树的基础上派生出新的依赖树，而原依赖树的软件包并没有被清除，只是暂时没有被使用罢了。用户可以通过切换当前版本的方式切换到不同的依赖树，就像`git checkout`一样。基于这一特性，Nix(OS)实现了一键回退，同一软件包多版本并存等黑科技

### 高度可定制 (Highly Customizable)

将Nix的包管理系统与其他包管理系统横向比较可以发现其灵活与高度可定制的特性。与使用广泛的`yum`和`apt`这类基于编译后的二进制文件的包管理系统不同，Nix的包管理设计逻辑更接近于[Arch][arch]或[Gentoo][gentoo]这类基于源代码的包管理系统，使得用户可以对软件包的参数甚至软件包本身进行定制。这种可定制性足够底层，使得用户可以按照自己的需要打造独一无二的运行环境。此外Nix在设计中还巧妙的引入了缓存，当用户安装软件包时使用的参数与官方一致时，可以直接从缓存中下载编译后的结果，加快软件包安装速度。

除去以上三条，Nix(OS)还有更多有意思的特性，由于篇幅原因就不一一列举了。着重强调这三条的原因是将NixOS与[Debian][debian]或[Red Hat][redhat]等传统Linux发行版相比较，这三条特性正对应了使用传统发行版会遇到的几大痛点。

* 传统发行版均为命令式的设计，系统管理员通过一系列的命令来配置系统。虽然有通过引入多一层的抽象，使用[Ansible][ansible]/[Chef][chef]等工具提供描述式的系统配置手段，但是额外的复杂度和学习成本以及各种底层发行版带来的局限性，并没有为用户提供完美的解决方案
* 传统发行版是基于软件包分发来设计的。软件包之间的依赖关系使得升级软件包变成了高风险的操作，运气不好就会出现软件包之间不兼容，或是不同软件包依赖同一个软件包的不同版本的情况。虽然容器的普及从一定程度上缓解了这一问题，但是无风险的升级和回退始终是系统管理员渴求的功能
* 传统发行版的软件包普遍采用二进制文件分发的方式来提升软件包的安装体验，但是这意味着用户仅能够通过配置文件来设定软件运行模式，而无法对程序本身进行修改。虽然许多软件包也提供打包源文件，用户可以构建自己定制版的软件包，但操作的复杂程度以及维护的成本让许多用户望而却步

## 答案

由于自身能力的局限以及Nix(OS)的实际使用经验为零，对其特性的理解还停留在粗浅的阶段，但这并不妨碍我从感性角度去体会Nix(OS)的价值点。就我主观看来，通过创新性的使用Declarative和Immutable等特性，Nix(OS)优雅的解决了在传统发行版中困扰系统管理员的变更管理这项挑战是其最大的突破和价值点。

对于想使用声明式的方法来管理Linux操作系统，以及需要频繁维护和变更系统的用户来讲，Nix(OS)都是不错的选择。个人桌面和大规模服务器集群都能够找到适合它的使用场景。Nix(OS)并不适合推荐给Linux新人，过高的门槛和缺乏横向对比导致的价值点模糊导致劝退属性拉满。它适合有一定Linux管理和运维经验，不满足于传统发行版的局限性，试图想要改进现状并且有一定折腾能力的Power User。

## 结局

尽管有种种优点，我在现实中却暂时没找到它的用武之地。在服务器端线上生产环境已经有了一整套的自动化服务器管理流程，在没有吃透NixOS之前贸然进行改造出现问题多半搞不定。在桌面端我本地的[Chrome OS][chromeos] + [Crostini][crostini]环境也很难把它用起来。

所以在初略看过一眼之后，我就放弃了进一步的学习，把Nix(OS)定位为也许某一天会派上用场的技术，希望将来有空了再来深入了解。

[nixos]: https://nixos.org
[shlug]: http://www.shlug.org
[yuchangyuan]: https://github.com/yuchangyuan
[kubernetes]: https://kubernetes.io
[git]: https://git-scm.com
[arch]: https://www.archlinux.org
[gentoo]: https://www.gentoo.org
[debian]: https://www.debian.org
[redhat]: https://www.redhat.com/en/technologies/linux-platforms/enterprise-linux
[ansible]: https://www.ansible.com
[chef]: https://www.chef.io
[chromeos]: https://www.chromium.org/chromium-os
[crostini]: https://chromium.googlesource.com/chromiumos/docs/+/master/containers_and_vms.md