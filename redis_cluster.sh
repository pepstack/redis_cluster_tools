#!/usr/bin/bash
#
# @file: install_redis_cluster.sh
#   redis 集群部署工具(支持 CentOS-7+, Ubuntu-20+)
#
# redis 源码下载: https://download.redis.io/releases/redis-8.2.0.tar.gz
#
# hiredis 源码下载: https://github.com/redis/hiredis
#
# Usage:
#  $prog CLUSTERID ACTION
#
#  CLUSTERID:
#     clusterid
#
#     下面的目录必须存在：
#        redis/conf/cluster.$clusterid
#
#  ACTION:
#     config     生成全部节点配置文件
#     build      编译 redis 源码
#     deploy     在当前节点上部署 redis 集群
#     clean      清理所有中间文件
#
# Examples:
#
#  1) 创建集群: mycluster
#     $ install_redis_cluster.sh mycluster ALL
#
#  2) 删除集群(危险): mycluster
#     $ install_redis_cluster.sh mycluster clean ALL
#
# @author: 350137278@qq.com
#
# @create: 2024-09-18
# @update: 2025-08-10,11
#
########################################################################
_thisdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_thisname=$(basename "${BASH_SOURCE[0]}")
_thisfile="$(cd "$_thisdir" && pwd)/$_thisname"

. $_thisdir/common.sh

# Treat unset variables as an error
set -o nounset

# Treat any error as exit
set -o errexit

# 定义保留id数组
reserved_clusterids=("default" "redis" "config" "deploy" "clean" "all" "build" "standalone" "distributed")

pkgs_dir="$_thisdir/pkgs"
build_dir="$_thisdir/build"
config_dir="$_thisdir/config"

redis_prefix="$_thisdir/redis"
redis_sbin_dir="$redis_prefix/sbin"
redis_conf_dir="$redis_prefix/conf"

# 动作命令
has_config=""
has_build=""
has_deploy=""
has_clean=""

actions=($(echo "$*" | awk -F[,] '{ for(i=1; i<=NF; i++) print $i; }'))

if [[ $(array_find actions "ALL") != -1 ]]; then
    has_config="y";
    has_build="y";
    has_deploy="y";
fi

if [[ $(array_find actions "config") != -1 ]]; then has_config="y"; fi
if [[ $(array_find actions "build") != -1 ]]; then has_build="y"; fi
if [[ $(array_find actions "deploy") != -1 ]]; then has_deploy="y"; fi
if [[ $(array_find actions "clean") != -1 ]]; then has_clean="y"; fi

# 集群id
clusterid="$1"

# 输出目录
cluster_build_dir="$build_dir/$clusterid"
cluster_config_dir="$config_dir/$clusterid"

# 输入目录
cluster_conf_dir="$redis_conf_dir/cluster.$clusterid"
cluster_ini_file="$cluster_conf_dir/redis_cluster.ini"
cluster_nodes_cfg="$cluster_conf_dir/cluster_nodes.cfg"

# 验证规则 1: 必须是小写英文字母开头，只包含小写字母、数字和下划线
if [[ ! "$clusterid" =~ ^[a-z][a-z0-9_]{5,}$ ]]; then
    echoerror "集群ID必须以小写字母开头，只能包含小写字母、数字和下划线，且至少6个字符"
    exit 1
fi

# 验证规则 2: 不能是保留名称
for name in "${reserved_clusterids[@]}"; do
    if [[ "$clusterid" == "$name" ]]; then
        echoerror "不合法的集群ID - 不能使用保留名称 '$clusterid'"
        exit 1
    fi
done

# 验证规则 3: 集群配置文件必须存在
if [[ ! -f "$cluster_ini_file" ]]; then
    echoerror "集群初始化配置文件不存在: $cluster_ini_file"
    exit 1
fi

if [[ ! -f "$cluster_nodes_cfg" ]]; then
    echoerror "集群节点配置文件不存在: $cluster_nodes_cfg"
    exit 1
fi

# 引入配置环境变量
. "$cluster_ini_file"

# 集群安装目录: /opt/redis_cluster/testcluster
cluster_home_dir="$cluster_parent_dir/$clusterid"

# 验证规则 4: redis 安装包必须存在，版本不能低于 7
redis_name=$(echo "${redis_pkg%.tar.gz*}" | awk -F '[-]' '{print $1}')
if [[ "$redis_name" != "redis" ]]; then
    echoerror "不是 redis 安装包: $redis_pkg"
    exit 1
fi
redis_verno=$(echo "${redis_pkg%.tar.gz*}" | awk -F '[-]' '{print $2}')  # 7.4.0
major_verno=$(verno_major_id "$redis_verno") # 版本不能低于 7
if [[ ${major_verno} -lt 7 ]]; then
    echoerror "redis 版本必须大于等于 7"
    exit 1
fi

# 验证规则 5: hiredis 安装包必须存在，版本不能低于 1
hiredis_name=$(echo "${hiredis_pkg%.tar.gz*}" | awk -F '[-]' '{print $1}')
if [[ "$hiredis_name" != "hiredis" ]]; then
    echoerror "不是 hiredis 安装包: $hiredis_pkg"
    exit 1
fi
hiredis_verno=$(echo "${hiredis_pkg%.tar.gz*}" | awk -F '[-]' '{print $2}') # 1.3.0
major_verno=$(verno_major_id "$hiredis_verno")
if [[ ${major_verno} -lt 1 ]]; then
    echoerror "hiredis 版本必须大于等于 1"
    exit 1
fi

redis_build_dir="$cluster_build_dir/$redis_name-$redis_verno"
hiredis_build_dir="$cluster_build_dir/$hiredis_name-$hiredis_verno"

# TLS/SSL CA 证书路径: /opt/redis_cluster/testcluster/certs
tls_cacert_dir="$cluster_home_dir/$tls_cacertdir"

echoinfo "集群ID名称: $clusterid"
echoinfo "集群配置目录: $cluster_conf_dir"
echoinfo "集群初始化配置文件: $cluster_ini_file"
echoinfo "集群节点配置文件: $cluster_nodes_cfg"
echoinfo "集群编译输出目录: $cluster_build_dir"
echoinfo "集群配置输出目录: $cluster_config_dir"
echoinfo "集群安装部署目录: $cluster_home_dir"

###############################################################

function clean() {
    # 删除集群编译输出目录（需要确认）
    if [ $has_build ]; then
        if [[ -d "$cluster_build_dir" ]]; then
            echowarn "($FUNCNAME) 删除集群编译输出目录: $cluster_build_dir"
            read -p "($FUNCNAME) 确认删除？请输入 yes 或 no: " confirm
            if [[ "$confirm" == [Yy][Ee][Ss] || "$confirm" == [Yy] ]]; then
                rm -rf "$cluster_build_dir"
                echoinfo "($FUNCNAME) 已删除编译输出目录: $cluster_build_dir"
            else
                echowarn "($FUNCNAME) 取消删除编译输出目录: $cluster_build_dir"
            fi
        else
            echoerror "($FUNCNAME) 不存在目录: $cluster_build_dir"
        fi
    fi

    # 删除集群配置输出目录（需要确认）
    if [ $has_config ]; then
        if [[ -d "$cluster_config_dir" ]]; then
            echowarn "($FUNCNAME) 删除集群配置输出目录: $cluster_config_dir"
            read -p "($FUNCNAME) 确认删除？请输入 yes 或 no: " confirm
            if [[ "$confirm" == [Yy][Ee][Ss] || "$confirm" == [Yy] ]]; then
                rm -rf "$cluster_config_dir"
                echoinfo "($FUNCNAME) 已删除配置输出目录: $cluster_config_dir"
            else
                echowarn "($FUNCNAME) 取消删除配置输出目录: $cluster_config_dir"
            fi
        else
            echoerror "($FUNCNAME) 不存在目录: $cluster_config_dir"
        fi
    fi

    # 删除集群部署目录（需要确认）- 高风险操作
    if [[ -d "$cluster_home_dir" ]]; then
        if [ $has_deploy ]; then
            echowarn "($FUNCNAME) 警告：删除集群部署目录将清除集群所有数据: $cluster_home_dir"
            read -p "($FUNCNAME) 确认删除集群所有数据？请输入 yes 或 no: " confirm
            if [[ "$confirm" == [Yy][Ee][Ss] || "$confirm" == [Yy] ]]; then
                rm -rf "$cluster_home_dir"
                echoinfo "($FUNCNAME) 已删除集群部署目录及所有数据: $cluster_home_dir"
            else
                echowarn "($FUNCNAME) 取消删除集群部署目录: $cluster_home_dir"
            fi
        fi
    else
        echoerror "($FUNCNAME) 不存在目录: $cluster_home_dir"
    fi
}


function build() {
    if [[ -f "$cluster_build_dir/BUILD_SUCCESS" ]]; then
        echowarn "($FUNCNAME) 编译目录已经存在: $cluster_build_dir"
        exit 1
    fi

    mkdir -p "$cluster_build_dir"

    # 检查 redis 包文件是否存在
    if [[ ! -f "$pkgs_dir/$redis_pkg" ]]; then
        echoerror "($FUNCNAME) redis 安装包不存在: $pkgs_dir/$redis_pkg"
        exit 1
    fi

    # 检查 hiredis 包文件是否存在
    if [[ ! -f "$pkgs_dir/$hiredis_pkg" ]]; then
        echoerror "($FUNCNAME) hiredis 安装包不存在: $pkgs_dir/$hiredis_pkg"
        exit 1
    fi

    # 检查 redis 输出目录
    if [[ -d "$redis_build_dir" ]]; then
        echoerror "($FUNCNAME) 目录已经存在: $redis_build_dir"
        exit 1
    fi

    # 检查 hiredis 输出目录
    if [[ -d "$hiredis_build_dir" ]]; then
        echoerror "($FUNCNAME) 目录已经存在: $hiredis_build_dir"
        exit 1
    fi

    echoinfo "($FUNCNAME) 解压 redis 安装包: $pkgs_dir/$redis_pkg => $redis_build_dir"
    tar -xzf "$pkgs_dir/$redis_pkg" -C "$cluster_build_dir"

    echoinfo "($FUNCNAME) 解压 hiredis 安装包: $pkgs_dir/$hiredis_pkg => $hiredis_build_dir"
    tar -xzf "$pkgs_dir/$hiredis_pkg" -C "$cluster_build_dir"

    echoinfo "($FUNCNAME) 编译: $redis_name-$redis_verno"
    cd "$redis_build_dir" && make BUILD_WITH_MODULES=$build_with_modules BUILD_TLS="$build_tls_mode"

    echoinfo "($FUNCNAME) 编译: $hiredis_name-$hiredis_verno"
    cd "$hiredis_build_dir" && make USE_SSL=1

    echo "BUILD_SUCCESS" > "$cluster_build_dir/BUILD_SUCCESS"
}


function config() {
    if [[ -f "$cluster_config_dir/CONFIG_SUCCESS" ]]; then
        echowarn "($FUNCNAME) 配置目录已经存在: $cluster_config_dir"
        exit 1
    fi

    # 创建配置输出目录
    mkdir -p "$cluster_config_dir"

    # redis auth 密码
    redis_auth_pass=$(cat "$cluster_conf_dir/$redis_authpass_file")

    # 集群安装目录: /opt/redis_cluster/testcluster
    RedisClusterHome=$(echo "$cluster_home_dir" | sed 's/\//\\\//g')

    # TLS/SSL 配置
    TlsCacertDir=$(echo "$tls_cacert_dir" | sed 's/\//\\\//g')

    if [ "$tls_enabled" = "yes" ]; then
        TlsStatus="TLS enabled"
        tls_enabled=1
        HashTag=""
    else
        TlsStatus="TLS disabled"
        tls_enabled=0
        HashTag="#!"
    fi

    # 生成 redis 集群初始创建脚本: 包含集群全部节点
    > "$cluster_config_dir/CLUSTER_ALL_NODES"

    # 根据节点配置文件模板动态对每个服务器生成实例的配置文件:
    #  每个服务器节点运行多个 redis-server 实例;
    #  每个 redis-server 实例使用专有的配置文件 redis-NODEID-PORT.conf 启动
    nodes=$(read_cfg "$cluster_nodes_cfg" "redis_cluster" "nodes")
    nodeslist=($(echo "$nodes" | awk -F[,] '{ for(i=1; i<=NF; i++) print $i; }'))

    numnodes=${#nodeslist[@]}
    for (( n=0; n<${numnodes}; n++ ));
    do
        nodeid="${nodeslist[n]}"

        # 节点配置文件存放目录
        nodeconfdir="$cluster_config_dir/$nodeid"
        mkdir -p "$nodeconfdir"

        # 节点配置文件模板: 用于生成实际的实例配置文件
        node_conf0_file="$cluster_conf_dir""/"$(read_cfg "$cluster_nodes_cfg" "$nodeid" "conf")

        # 实例配置文件
        host=$(read_cfg "$cluster_nodes_cfg" "$nodeid" "host")
    
        addrs=$(read_cfg "$cluster_nodes_cfg" "$nodeid" "addrs")
        addrslist=($(echo "$addrs" | awk -F[,] '{ for(i=1; i<=NF; i++) print $i; }'))
        addrstr="${addrslist[@]}"

        ports=$(read_cfg "$cluster_nodes_cfg" "$nodeid" "ports")
        portslist=($(echo "$ports" | awk -F[,] '{ for(i=1; i<=NF; i++) print $i; }'))
        numports=${#portslist[@]}

        echoinfo "($FUNCNAME) [$nodeid] $TlsStatus (host=$host, addrs=$addrstr)"

        if [ "$tls_enabled" == "yes" ]; then
            tlsports=$(read_cfg "$cluster_nodes_cfg" "$nodeid" "tlsports")
            tlsportslist=($(echo "$tlsports" | awk -F[,] '{ for(i=1; i<=NF; i++) print $i; }'))

            if [ "$numports" != "${#tlsportslist[@]}" ]; then
                echoerror "($FUNCNAME) number of ports differs from tls ports"
                exit 1
            fi

            tlscertfile="$tls_cacert_dir"/$(read_cfg "$cluster_nodes_cfg" "$nodeid" "tlscertfile")
            tlskeyfile="$tls_cacert_dir"/$(read_cfg "$cluster_nodes_cfg" "$nodeid" "tlskeyfile")
            tlsdhfile="$tls_cacert_dir"/$(read_cfg "$cluster_nodes_cfg" "$nodeid" "tlsdhfile")

            TlsCertFile=$(echo "$tlscertfile" | sed 's/\//\\\//g')
            TlsKeyFile=$(echo "$tlskeyfile" | sed 's/\//\\\//g')
            TlsDhFile=$(echo "$tlsdhfile" | sed 's/\//\\\//g')
        fi

        for (( p=0; p<${numports}; p++ ));
        do
            port="${portslist[p]}"

            node_conf_file="$nodeconfdir/redis-$nodeid-$port.conf"

            echo "$host:$port" >> "$cluster_config_dir/CLUSTER_ALL_NODES"

            if [ "$tls_enabled" == "yes" ]; then
                tlsport="${tlsportslist[p]}"
                echo "$host:$tlsport" >> "$cluster_config_dir/CLUSTER_TLS_NODES"
            fi

            echoinfo "($FUNCNAME) create conf: $node_conf_file"

            if [ "$tls_enabled" == "yes" ]; then
                cat "$node_conf0_file" | \
                    sed 's/'"{"CLUSTER_HOME_DIR"}"'/'"$RedisClusterHome"'/g' | \
                    sed 's/'"{"CLUSTERID"}"'/'"$clusterid"'/g' | \
                    sed 's/'"{"NODEID"}"'/'"$nodeid"'/g' | \
                    sed 's/'"{"RDB_DIR"}"'/'"$rdb_dir_name"'/g' | \
                    sed 's/'"{"HOST"}"'/'"$host"'/g' | \
                    sed 's/'"{"PORT"}"'/'"$port"'/g' | \
                    sed 's/'"{"ADDRS"}"'/'"$addrstr"'/g' | \
                    sed 's/'"{"PASSWORD"}"'/'"$redis_auth_pass"'/g' | \
                    sed 's/'"{"TLS_HASHTAG"}"'/'"$HashTag"'/g' | \
                    sed 's/'"{"TLS_PORT"}"'/'"$tlsport"'/g' | \
                    sed 's/'"{"TLS_CERTFILE"}"'/'"$TlsCertFile"'/g' | \
                    sed 's/'"{"TLS_KEYFILE"}"'/'"$TlsKeyFile"'/g' | \
                    sed 's/'"{"TLS_DHFILE"}"'/'"$TlsDhFile"'/g' | \
                    sed 's/'"{"TLS_CACERT"}"'/'"$tls_cacert"'/g' | \
                    sed 's/'"{"TLS_CACERTDIR"}"'/'"$TlsCacertDir"'/g' \
                > "$node_conf_file"
            else
                # no-ssl
                cat "$node_conf0_file" | \
                    sed 's/'"{"CLUSTER_HOME_DIR"}"'/'"$RedisClusterHome"'/g' | \
                    sed 's/'"{"CLUSTERID"}"'/'"$clusterid"'/g' | \
                    sed 's/'"{"NODEID"}"'/'"$nodeid"'/g' | \
                    sed 's/'"{"RDB_DIR"}"'/'"$rdb_dir_name"'/g' | \
                    sed 's/'"{"HOST"}"'/'"$host"'/g' | \
                    sed 's/'"{"PORT"}"'/'"$port"'/g' | \
                    sed 's/'"{"ADDRS"}"'/'"$addrstr"'/g' | \
                    sed 's/'"{"PASSWORD"}"'/'"$redis_auth_pass"'/g' | \
                    sed 's/'"{"TLS_HASHTAG"}"'/'"$HashTag"'/g' \
                > "$node_conf_file"
            fi
        done

        cp "$cluster_conf_dir/$redis_authpass_file" "$cluster_config_dir/CLUSTER_AUTH_PASS"

        # 节点启动脚本: 启动节点的全部服务实例
        cat "$redis_sbin_dir/start_redis.sh.0" | \
                sed 's/'"{"NODEID"}"'/'"$nodeid"'/g' | \
                sed 's/'"{"NODEHOST"}"'/'"$host"'/g' | \
                sed 's/'"{"PORTS"}"'/'"${portslist[*]}"'/g' \
            > "$nodeconfdir/start_redis.sh"

        # 节点关闭脚本: 保存并关闭节点全部服务实例
        cat "$redis_sbin_dir/shutdown_redis.sh.0" | \
                sed 's/'"{"NODEID"}"'/'"$nodeid"'/g' | \
                sed 's/'"{"NODEHOST"}"'/'"$host"'/g' | \
                sed 's/'"{"PORTS"}"'/'"${portslist[*]}"'/g' \
            > "$nodeconfdir/shutdown_redis.sh"

        # TCP 连接集群脚本
        cat "$redis_sbin_dir/connect_redis.sh.0" | \
                sed 's/'"{"NODEID"}"'/'"$nodeid"'/g' | \
                sed 's/'"{"NODEHOST"}"'/'"$host"'/g' | \
                sed 's/'"{"PORT"}"'/'"${portslist[0]}"'/g' \
            > "$nodeconfdir/connect_redis.sh"

        if [ "$tls_enabled" == "yes" ]; then
            # TLS 连接集群脚本
            cat "$redis_sbin_dir/tlsconnect_redis.sh.0" | \
                    sed 's/'"{"NODEID"}"'/'"$nodeid"'/g' | \
                    sed 's/'"{"NODEHOST"}"'/'"$host"'/g' | \
                    sed 's/'"{"TLS_PORT"}"'/'"${tlsportslist[0]}"'/g' | \
                    sed 's/'"{"TLS_CERTFILE"}"'/'"$TlsCertFile"'/g' | \
                    sed 's/'"{"TLS_KEYFILE"}"'/'"$TlsKeyFile"'/g' | \
                    sed 's/'"{"TLS_CACERT"}"'/'"$tls_cacert"'/g' \
                > "$nodeconfdir/tlsconnect_redis.sh"
        fi
    done

    cat "$redis_sbin_dir/cluster_env.sh.0" | \
        sed 's/'"{"CLUSTERID"}"'/'"$clusterid"'/g' | \
        sed 's/'"{"CLUSTERHOME"}"'/'"$RedisClusterHome"'/g' | \
        sed 's/'"{"CACERTDIR"}"'/'"$tls_cacertdir"'/g' | \
        sed 's/'"{"CLUSTERREPLICAS"}"'/'"$redis_cluster_replicas"'/g' \
    > "$cluster_config_dir/cluster_env.sh"

    # 生成 redis 集群初始创建脚本
    cat "$redis_sbin_dir/create_cluster.sh.0" > "$cluster_config_dir/create_cluster.sh"

    echo "CONFIG_SUCCESS" > "$cluster_config_dir/CONFIG_SUCCESS"
}


function deploy() {
    echoinfo "部署集群: $clusterid 到目录: $cluster_home_dir"

    if [[ ! -f "$cluster_build_dir/BUILD_SUCCESS" ]]; then
        echoerror "($FUNCNAME) 编译错误！请删除目录后重新编译(build): $cluster_build_dir"
        exit 1
    fi

    if [[ ! -f "$cluster_config_dir/CONFIG_SUCCESS" ]]; then
        echoerror "($FUNCNAME) 配置错误！请删除目录后重新配置(config): $cluster_config_dir"
        exit 1
    fi

    if [[ -f "$cluster_home_dir/CLUSTER_ALL_NODES" ]]; then
        echoerror "($FUNCNAME) 不能重复部署。目录已存在: $cluster_home_dir"
        exit 1
    fi

    echoinfo "($FUNCNAME) 集群部署目录: $cluster_home_dir"
    mkdir -p "$cluster_home_dir"/{"$rdb_dir_name",conf,log,run,modules}

    # 获取本机host和所有IPv4地址
    local current_host=$(hostname -s)
    local current_ips=$(hostname -I)

    # 每个 redis-server 实例使用专有的配置文件 redis-NODEID-PORT.conf 启动
    local nodes=$(read_cfg "$cluster_nodes_cfg" "redis_cluster" "nodes")
    local nodeslist=($(echo "$nodes" | awk -F[,] '{ for(i=1; i<=NF; i++) print $i; }'))

    local numnodes=${#nodeslist[@]}
    for (( n=0; n<${numnodes}; n++ ));
    do
        local nodeid="${nodeslist[n]}"

        # 节点配置文件存放目录
        local nodeconfdir="$cluster_config_dir/$nodeid"

        # 配置的 ip 地址
        local addrs=$(read_cfg "$cluster_nodes_cfg" "$nodeid" "addrs")
        local addrslist=($(echo "$addrs" | awk -F[,] '{ for(i=1; i<=NF; i++) print $i; }'))
        local addrstr="${addrslist[@]}"

        # 得到配置的机器名
        local host=$(read_cfg "$cluster_nodes_cfg" "$nodeid" "host")

        # 与本机的 ip 地址 current_ips 比较, 确定是否是本机
        local is_current=0

        # 检查主机名匹配
        if [[ "$host" == "$current_host" ]]; then
            is_current=1 # 是本机
        fi

        # 如果主机名未匹配，再检查IP地址
        if [ $is_current -eq 0 ]; then
            for nodeip in "${addrslist[@]}"; do
                # 检查节点IP是否在本机IP列表中（注意：current_ips是一个字符串，包含本机所有IP，空格分隔）
                # 使用grep -w 确保精确匹配整个单词（避免部分匹配，例如192.168.1.1匹配192.168.1.10）
                if echo "$current_ips" | grep -qw "$nodeip"; then
                    is_current=1  # 是本机
                    break # 匹配到一个即可退出循环
                fi
            done
        fi

        # 如果不是本机，则跳过后续处理
        if [ $is_current -eq 0 ]; then
            continue
        fi

        # 仅在本机节点部署配置文件
        local ports=$(read_cfg "$cluster_nodes_cfg" "$nodeid" "ports")
        local portslist=($(echo "$ports" | awk -F[,] '{ for(i=1; i<=NF; i++) print $i; }'))
        local numports=${#portslist[@]}

        for (( p=0; p<${numports}; p++ ));
        do
            local port="${portslist[p]}"
            local node_conf_file="$nodeconfdir/redis-$nodeid-$port.conf"

            echoinfo "($FUNCNAME) node conf: $cluster_home_dir/conf/redis-$nodeid-$port.conf"
            cp "$node_conf_file" "$cluster_home_dir/conf/"
        done

        # 部署集群初始创建脚本
        cp "$cluster_config_dir/create_cluster.sh" "$cluster_home_dir/"
        cp "$nodeconfdir/start_redis.sh" "$cluster_home_dir/start_redis-$nodeid.sh"
        cp "$nodeconfdir/shutdown_redis.sh" "$cluster_home_dir/shutdown_redis-$nodeid.sh"
        cp "$nodeconfdir/connect_redis.sh" "$cluster_home_dir/connect_redis-$nodeid.sh"

        chmod +x "$cluster_home_dir/create_cluster.sh"
        chmod +x "$cluster_home_dir/start_redis-$nodeid.sh"
        chmod +x "$cluster_home_dir/shutdown_redis-$nodeid.sh"
        chmod +x "$cluster_home_dir/connect_redis-$nodeid.sh"

        if [[ -f "$cluster_config_dir/CLUSTER_TLS_NODES" ]]; then
            cp "$nodeconfdir/tlsconnect_redis.sh" "$cluster_home_dir/tlsconnect_redis-$nodeid.sh"
            chmod +x "$cluster_home_dir/tlsconnect_redis-$nodeid.sh"
        fi
    done

    echoinfo "($FUNCNAME) 部署 redis 和 hiredis ..."
    cd "$redis_build_dir" && make install PREFIX="$cluster_home_dir"
    cd "$hiredis_build_dir" && make USE_SSL=1 PREFIX="$cluster_home_dir" install

    if [[ -f "$cluster_config_dir/CLUSTER_TLS_NODES" ]]; then
        ##rm -rf "$tls_cacert_dir"
        cp -r "$cluster_config_dir/$tls_cacertdir" "$tls_cacert_dir"
        cp "$cluster_config_dir/CLUSTER_TLS_NODES" "$cluster_home_dir/"
    fi

    cp "$cluster_config_dir/cluster_env.sh" "$cluster_home_dir/"
    cp "$cluster_config_dir/CLUSTER_AUTH_PASS" "$cluster_home_dir/"
    cp "$cluster_config_dir/CLUSTER_ALL_NODES" "$cluster_home_dir/"

    echoinfo "($FUNCNAME) 集群部署成功: $cluster_home_dir"
}

###############################################################
if [ $has_clean ]; then
    clean;
else
    if [ $has_build ]; then build; fi;
    if [ $has_config ]; then config; fi;
    if [ $has_deploy ]; then deploy; fi;
fi

# 测试是否是 root 用户
loguser=`id -un`
echoinfo "当前登录为：$loguser"
#chk_root