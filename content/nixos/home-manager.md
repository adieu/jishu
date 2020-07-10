---
Description: ""
Categories: ["NixOS"]
Tags: ["Nix", "NixOS", "Linux", "home-manager"]
title: "Nix(OS)挖坑笔记(2) - home-manager"
date: 2020-07-10T13:34:04+08:00
---
## 再会

在[前一篇][nixos-at-first-sight]中说到我在大致了解了[Nix(OS)][nixos]的特性之后，由于没有找到合适的使用场景，并没有实际安装和使用它，但作为一项有潜力的技术，我并没有停止对它的关注。直到有一天，看到[一篇帖子][nix-home]分享了使用Nix来管理用户环境和[dotfiles][dotfiles]的经验时，情况发生了变化。

## 目标

使用申明式语言来管理本地开发环境，并在多个Linux环境中同步。

## 问题

管理本地开发环境的需求一直存在，在8年前[我曾尝试过dotfiles管理模式][adieu-dotfiles]但很快就放弃了。现在回想起来，大致有以下原因：

- dotfiles只管理了Home目录下的配置文件，而软件本身还是需要用`apt`或者`yum`进行安装。所以在全新环境中初始化以及在各个环境中保持一致需要引入其他的方案
- 有不少辅助工具可选，但是试用过几款之后均不是非常满意，特别是在管理变更这方面
- [Ansible][ansible]等配置工具可以某种程度上实现申明式的开发环境管理，但是对于个人使用来说还是太重了
- 在服务器上配置个人环境会需要`root`权限安装全局软件包，一来使得服务器环境变脏，而且多人使用的时候还会出现包冲突的问题
- 如果想要统一Mac和Linux环境以及多个不同Linux发行版的环境并不容易，需要付出很多额外的努力

我们需要一款能同时管理软件包和它的配置文件的工具，它能够在用户的个人目录中完成全部的工作使得各个用户的环境完全独立互不干扰，并且它应当是申明式的，用户只需要告诉工具他期望的状态，具体的配置和变更则由工具自己决定，用户无需关注。此外，它最好使用起来简单易懂，方便用户上手。

问题是，这样的工具存在吗？

## home-manager

Nix的一些特性非常适合用在这个场景下，比如：

- Nix可以独立于原发行版运行。不论是在[Redhat][redhat]系还是[Debian][debian]系的发行版中，它都可以建立单独的环境，安装自己的包，而这些包并不会和原发行版冲突。
- Nix天生是申明式的，无需再引入额外的工具将申明式的定义转换为命令式的指令
- Nix的强大变更管理功能，使得用户在进行修改时更加有信心。如果变更失败可以随时一键回退到上一个版本

[home-manager][home-manager]是Nix(OS)生态中用于管理用户开发环境的工具。它可以结合NixOS使用，在NixOS中对整个系统进行定义，在home-manager中对用户自己的环境进行更加个性化的定义。它也可以独立于NixOS单独使用，在其他非NixOS发行版环境中，使用Nix构建用户自己独立的开发环境。

独立使用home-manager非常适合我这种暂时不打算折腾NixOS的用户，一方面可以在实战中提升对Nix(OS)的理解，另一方面它仅仅管理我的个人环境，不影响底层系统的稳定。

接下来实际上手把它用起来。

## 安装Nix

home-manager是构建在Nix之上的工具，所以需要先安装Nix。

{{< highlight bash "lineseparator=<br>" >}}
$ sh <(curl -L https://nixos.org/nix/install)
{{< /highlight >}}

经典的一行代码搞定安装。虽然不是特别优雅，但所有的组件都会安装到新创建的`/nix`目录下，并不会污染我原生的系统。

在安装完成后，多了几个`nix`开头的可执行文件，比如`nix-env`, `nix-build`可以用，之后有时间再来研究它们的功能，现在先把home-manager用起来再说。

## 安装home-manager

详细的流程在home-manager的[README][home-manager-readme]中有介绍，这里简单记录一下

{{< highlight bash "lineseparator=<br>" >}}
$ nix-channel --add https://github.com/rycee/home-manager/archive/master.tar.gz home-manager
$ nix-channel --update
$ nix-shell '<home-manager>' -A install
{{< /highlight >}}

现在的我其实并不太理解每条指令的作用，大概是新增加了一个软件仓库，并且安装了这个软件仓库中的home-manager这款软件的意思。

继续跳过`nix-channel`和`nix-shell`的学习，跟着README接着往下走。

## 申明式安装软件包

home-manager已经装好，现在我们开始试着来描述我们的开发环境。在`~/.config/nixpkgs/home.nix`创建以下文件

{{< highlight nix "lineseparator=<br>" >}}
{ pkgs, ... }:

{
  home.packages = [
    pkgs.go
  ];
}
{{< /highlight >}}

再运行`home-manager switch`让我们的描述生效。可以看到home-manager开始干活，结束之后我们来验证一下

{{< highlight bash "lineseparator=<br>" >}}
$ go version
go version go1.14.4 linux/amd64
$ /usr/local/go/bin/go version
go version go1.12.5 linux/amd64
{{< /highlight >}}

最新版的Go已经安装成功，而我系统中的Go并没有受影响。`which go`可以看到go被安装到了`~/.nix-profile/bin/go`，而它其实是指向`/nix/store/ipfzw3gm3vsdn4j0qz42n9438vcikzmb-home-manager-path/bin/go`的 symlink

所以本质上所有的软件包还是安装在`/nix/store`下，只是在我的Home目录下通过symlink将可执行文件暴露了出来。由于Nix在安装时会将`~/.nix-profile/bin`加入`PATH`，我可以直接使用已经安装后的可执行文件。

接下来再继续多安装几个包，将配置文件改为

{{< highlight nix "lineseparator=<br>" >}}
{ pkgs, ... }:

{
  home.packages = [
    pkgs.go
    pkgs.bazel
    pkgs.hugo
  ];
}
{{< /highlight >}}

再次运行`home-manager switch`，可以看到`bazel`和`hugo`已经安装完毕，非常方便。

配置文件使用的是Nix语言，一款函数式编程语言。就目前而言，我只知道往`home.packages`中增加更多的软件包的名称，就可以让home-manager安装更多的软件包。而删除某一软件包名称后再运行`home-manager switch`则会让home-manager从我个人环境中移除指向这一软件包的symlink，如果其他用户有安装这一软件包则他的环境不受影响。

至此，我可以在配置文件中声明我的开发环境所需要安装的软件包，利用home-manager实现软件包管理。

## 申明式管理配置文件

接下来看看如何实现配置文件的管理，修改配置文件为

{{< highlight nix "lineseparator=<br>" >}}
{ pkgs, ... }:

{
  home.packages = [
    pkgs.go
    pkgs.bazel
    pkgs.hugo
    pkgs.git
  ];
  home.file.".gitconfig".text = ''
    [user]
            email = adieu@adieu.me
            name = Adieu
  '';
}
{{< /highlight >}}

再次`home-manager switch`时会提示`.gitconfig`已经存在，这是一个防止误操作的保护。重命名后再次尝试配置成功

除了以纯文本方式进行配置以外，为了方便用户使用，home-manager还提供了多个模块，方便用户以结构化方式配置常用的软件包。将配置文件改为以下内容：

{{< highlight nix "lineseparator=<br>" >}}
{ pkgs, ... }:

{
  home.packages = [
    pkgs.go
    pkgs.bazel
    pkgs.hugo
  ];
  programs.git = {
    enable = true;
    userEmail = "adieu@adieu.me";
    userName = "Adieu";
  };
}
{{< /highlight >}}

这里，`programs.git`这个配置项会安装`git`软件包并同时将配置文件写入`~/.config/git/config`中，比直接用`home.file`进行配置又更加简化了一些。完整的配置项清单可以参考home-manager的[用户手册][home-manager-manual]。

利用封装好的模块或者直接配置文件的形式，我已经具备了将现有的配置文件逐步迁移到home-manager中进行管理的能力，剩下的就是体力活了。

## 一个更加复杂的配置案例

接下来试一下用home-manager来安装[VS Code][vscode]并管理它的配置以及插件。将配置文件改为以下内容

{{< highlight nix "lineseparator=<br>" >}}
{ pkgs, ... }:

{
  home.packages = [
    pkgs.go
    pkgs.bazel
    pkgs.hugo
  ];
  programs.git = {
    enable = true;
    userEmail = "adieu@adieu.me";
    userName = "Adieu";
  };
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [ (self: super: {
    vscode-extensions = with self.vscode-utils; super.vscode-extensions // {
        golang.Go = extensionFromVscodeMarketplace {
              name = "Go";
              publisher = "golang";
              version = "0.14.4";
              sha256 = "1rid3vxm4j64kixlm65jibwgm4gimi9mry04lrgv0pa96q5ya4pi";
          };
    };
  ) ];
  programs.vscode = {
    enable = true;
    package = pkgs.vscode;
    userSettings = {
      "telemetry.enableTelemetry" = false;
      "go.useLanguageServer" = true;
      "window.zoomLevel" = 0;
      "workbench.statusBar.feedback.visible" = false;
    };
    extensions = with pkgs.vscode-extensions; [
      golang.Go
    ];
  };
}
{{< /highlight >}}

这里我遇到了一个问题，VS Code最近将Go插件的维护移交给了Go团队，所以原来已有的`ms-vscode.Go`插件变得不可用。我在这里用了overlay的办法，动态patch了软件仓库，增加了`golang.Go`插件，并启用了它。

overlay是Nix非常重要的特性，它可以让你方便的定制整个软件仓库，今后会专门进行讲解。

另外此时我运行VS Code会发现之前工作正常的硬件加速并没有正常工作，导致卡顿明显。解决过程也是一波三折，也留到之后再做分享了。

至于在多个环境中同步，仅需要将配置文件加入版本管理，在其他环境中拉取最新的配置文件，并执行`home-manager switch`即可。

## 答案

到目前为止，我对home-manager的表现非常满意。统一的软件包和配置文件管理体验，申明式的配置方法，相对简洁的配置语言都符合我的要求。

虽然Nix的语法现在看上去还有点奇怪，但并不影响我所需要的一些基本操作。

## 结论

使用home-manager，我圆满完成了最初设定的目标。对于Nix的安装和Nix语言也有了最初步的体验。在前一篇中所列举的种种Nix的优点，在使用home-manager的过程中有了最直接的感受。

但现在只是把Nix当作一个黑盒来使用，还谈不上已经入门Nix，只能勉强算是会使用home-manager这款工具。接下来还需要在实战中学习Nix语法以及理解底层的运作机制。

如果您也对现有的本地开发环境和dotfiles管理方案不满意，或者是打算折腾一下Nix，欢迎也实际上手体验一下home-manager。大家共同交流和分享经验。

[nixos-at-first-sight]: https://jishu.io/nixos/nixos-at-first-sight/
[nixos]: http://nixos.org/
[nix-home]: https://hugoreeves.com/posts/2019/nix-home/
[dotfiles]: https://en.wikipedia.org/wiki/dotfile
[adieu-dotfiles]: https://github.com/adieu/dotfiles
[ansible]: https://www.ansible.com
[redhat]: https://www.redhat.com/en/technologies/linux-platforms/enterprise-linux
[debian]: https://www.debian.org
[home-manager]: https://github.com/rycee/home-manager
[home-manager-readme]: https://github.com/rycee/home-manager/blob/master/README.md
[home-manager-manual]: https://rycee.gitlab.io/home-manager/options.html
[vscode]: https://github.com/microsoft/vscode