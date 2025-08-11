
## redis 集群安装和使用说明

2024-09-20, first create by maparare.top

2025-08-10,11, update by maparare.top

**免责声明：使用本项目脚本给您造成的任何后果，本作者都不负任何责任。强烈建议您在虚拟机上执行本项目脚本。**

redis 集群安装管理 shell 脚本。支持 CentOS/RHEL7+ 和 Ubuntu/Debian20+，其他未测试。

redis 集群是指多个 redis-server 实例（服务进程）运行一台或多台服务器上，全部 redis-server 服务实例构成一个集群（通过创建脚本创建集群：create_cluster.sh）。

每个 redis-server 实例都要占用一个通讯端口（port），并且使用独有的配置文件启动。为保证高可用，一般选择至少 3 台服务器，每台机器 3 个实例的模式。参考: redis/conf/cluster.distributed

测试环境也可以采用在一台机器上伪装 3 个节点的方式。参考: redis/conf/cluster.standalone

### 1. 准备工作

以下要求每个节点服务器(单服务器测试可以忽略)都要执行:

- 设置时区

  $ unlink /etc/localtime

  $ ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

  $ timedatectl

- 设置时间

  $ date -s "2024-09-18 11:51:00"

  $ echo $(date +"%Y-%m-%d %H:%M:%S") | hwclock -w

  $ hwclock

- 节点服务器时钟同步

  (略)

- CentOS 使用 aliyum repo (如果需要)

  $ cd /etc/yum.repos.d/ && mkdir old_repos && mv ./*.repo old_repos

  $ wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo

  $ yum clean all && yum makecache

  $ yum list && update

- 必要软件开发库安装

  - CentOS/RHEL:

    $ sudo yum groupinstall -y "Development Tools"

    $ sudo yum install -y pkgconfig openssl-devel tcl-devel cmake valgrind

  - Ubuntu/Debian:

    $ sudo apt install -y build-essential pkg-config libssl-dev tcl-dev cmake valgrind

- jemalloc 编译安装(好像并无必要)

  $ cd pkgs

  $ tar -zxf jemalloc-5.2.1.tar.gz

  $ cd jemalloc-5.2.1

  $ ./autogen.sh --with-jemalloc-prefix=je_ --prefix=/usr/local

  $ make && sudo make install

- 下载 redis 到 pkgs 目录

  根据版本选择下载源码包（pkgs 目录下已经包含下面的包）：

  - https://download.redis.io/releases/redis-7.4.0.tar.gz
  - https://download.redis.io/releases/redis-8.2.0.tar.gz

- 下载 hiredis 到 pkgs 目录（pkgs 目录下已经包含下面的包）：

  - https://github.com/redis/hiredis

  需要压缩为 tar 包，如：hiredis-1.30.tar.gz

### 2. 创建集群配置文件

假设这里的集群ID为: samplecl ($CLUSTERID=samplecl)

- 多服务器真分布式

  **集群模板**: redis/conf/cluster.distributed

- 单服务器伪分布式

  **集群模板**: redis/conf/cluster.standalone

根据需要复制**集群模板**为你的集群目录（cluster.samplecl）：

    $ cd redis/conf/

    $ cp -r cluster.standalone cluster.samplecl

然后手动配置 redis/conf/cluster.samplecl 目录下的配置文件（文件名不可更改）：

  - redis_cluster.ini

    集群安装的基本信息

  - cluster_nodes.cfg

    集群节点的配置

  - REDIS-AUTH-PASS

    集群密码

如果启用 TLS 证书，还需要生成服务器和客户端证书。参考 sslcerts。

### 3. 创建集群

集群父目录（例如：/opt/redis_cluster） 必须设置当前用户（假如：root1）的权限。

  $ cd /opt/
  $ sudo chown root1:root1 redis_cluster

使用 redis_cluster.sh 脚本管理集群。redis_cluster.sh 的第1个参数必须时候 $CLUSTERID，本例是 samplecl。以下是常用命令：

- 从源码编译

  $ redis_cluster.sh samplecl build

  只需执行一次即可！

- 配置集群

  $ redis_cluster.sh samplecl clean config

  clean （可选）表示删除上次的配置。

  如果发现配置错误，可以修改集群配置文件（redis/conf/cluster.samplecl）后再次执行上面的命令

- 部署集群

  $ redis_cluster.sh samplecl deploy

  如果集群部署目录已经存在，则无法部署同名集群。必须删除后重新部署。

- 删除部署的集群

  $ redis_cluster.sh samplecl clean deploy

  **危险**：这个命令会彻底删除部署的集群。

- 编译、配置、部署集群

  $ redis_cluster.sh samplecl ALL

  这个命令一键完成创建集群。

- 删除集群全部内容（必须确保没有正在运行的 redis-server 进程）

  $ redis_cluster.sh samplecl clean ALL

### 4. 初始化集群启动

当集群部署成功，分布进入每个服务器的集群部署目录（本例默认在：/opt/redis_cluster/samplecl），启动 redis-server 进程：

    $ cd /opt/redis_cluster/samplecl/

运行全部带有类似下面格式的脚本：

    $ ./start_redis-$nodeid.sh

（本例为伪分布式，在服务器上运行的脚本如下：）

    $ ./start_redis-node1.sh

    $ ./start_redis-node2.sh

    $ ./start_redis-node3.sh
  

当全部服务器节点的全部 start_redis-$nodeid.sh 启动完成，在其中任一台服务器上执行：

  $ cd /opt/redis_cluster/samplecl/

  $ ./create_cluster.sh

然后连接到集群：

    $ /opt/redis_cluster/samplecl$ ./connect_redis-node1.sh

    [redis://redis_ubuntu@samplecl] Client TCP connecting to: node1:6377 ...
    redis_ubuntu:6377> cluster info
    cluster_state:ok
    cluster_slots_assigned:16384
    cluster_slots_ok:16384
    cluster_slots_pfail:0
    cluster_slots_fail:0
    cluster_known_nodes:9
    cluster_size:4
    cluster_current_epoch:9
    cluster_my_epoch:1
    cluster_stats_messages_ping_sent:64
    cluster_stats_messages_pong_sent:69
    cluster_stats_messages_sent:133
    cluster_stats_messages_ping_received:61
    cluster_stats_messages_pong_received:64
    cluster_stats_messages_meet_received:8
    cluster_stats_messages_received:133
    total_cluster_links_buffer_limit_exceeded:0
    redis_ubuntu:6377>

  出现上面的输出，表示集群成功运行。
  
### 5. 安全停止集群运行

分布进入每个服务器的集群部署目录（本例默认在：/opt/redis_cluster/samplecl），运行全部带有类似下面格式的脚本：

    $ ./shutdown_redis-$nodeid.sh

（本例为伪分布式，在服务器上运行的脚本如下：）

    $ ./shutdown_redis-node1.sh

    $ ./shutdown_redis-node2.sh

    $ ./shutdown_redis-node3.sh

### 6. 配置集群使用 TLS/SSL 证书

集群完全支持 tls 证书。参考配置：redis/conf/cluster.distributed。

  “certs” 是 redis 自带的测试工具生成的。当 build 好集群源码，执行 "build/redis-8.2.0/utils/gen-test-certs.sh" 如下：

      $ cd build/redis-8.2.0/

      $ rm -rf tests/tls

      $ utils/gen-test-certs.sh

  然后将 tests/tls 复制为 redis/conf/cluster.distributed/certs

配置文件 redis_cluster.ini 中设置 (tls_enabled=yes)，集群就启用了证书支持。redis_cluster.sh 会自动将 “certs” 目录复制到集群部署目录下。集群所有节点必须使用同一个 certs，部署到每个服务器。如果客户端通过证书连接集群，使用:

    tlsconnect_redis-$nodeid.sh。

** 启用 tls 与 tcp 不矛盾。其实应该同时启用，服务器之间的主从备份使用 tcp，客户端可以使用 tls 连接 redis 集群服务。**

### 7. TODO

- hiredis 和 hiredis ssl 开发示例
