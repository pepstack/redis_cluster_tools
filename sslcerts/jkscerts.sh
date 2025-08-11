#!/bin/bash
#   jkscerts.sh - 自动生成 Java-8+ 证书库的脚本
#
# 制作 Java SSL 双向证书, 必须用 jdk 下面的 keytool:
#   $JAVA_HOME/bin/keytool
#
# 参考:
#   https://www.cnblogs.com/littleatp/p/5922362.html
#   https://blog.csdn.net/weixin_41917987/article/details/80988197
#
# 2024-09-19
#####################################################################
_name_=$(basename "$0")
_cdir_=$(cd "$(dirname "$0")" && pwd)
_file_=""${_cdir}"/"${_name}""
_ver_="0.1.0"

. $_cdir_/common.sh

# Set characters encodeing
#   LANG=en_US.UTF-8;export LANG
LANG=zh_CN.UTF-8;export LANG

# Treat unset variables as an error
set -o nounset

# Treat any error as exit
set -o errexit

if [ $# -eq 0 ]; then
    echoerror "没有指定证书配置文件"
    exit -1
fi

# 配置文件
config_path=$(cd "$(dirname "$1")" && pwd)
config_file=$(basename "$1")

. "$config_path/$config_file"

if [ "$serverkeypass" = "$clientkeypass" ]; then
    echoerror "客户端密码不能与服务器相同!"
    exit -1
fi

genkeys_path="$config_path/$GENKEYS_DIR"

KLOGFILE="$genkeys_path/keytool-secret.log"
SBSSLCFG="$genkeys_path/springboot-ssl.config"

if [ -d "$genkeys_path" ]; then
    echoerror "不能输出到已经存在的证书目录: $genkeys_path"
    exit -1
fi

echoinfo "Java 证书工具: "$JAVA_KEYTOOL
echoinfo "生成证书使用的配置文件: $config_path/$config_file"
echoinfo "生成的证书保存的目录: $genkeys_path"
echoinfo "证书有效期: $VALID_DAYS 天"

echoinfo "服务器 DN: "$serverdname
echoinfo "客户端 DN: "$clientdname

echoinfo "服务器证书库(JKS)名称: "$serverkeystore
echoinfo "服务器证书库别名: "$serverkeystorealias

echoinfo "服务器信任证书库名称: "$servertrustkeystore
echoinfo "服务器信任证书库别名: "$servertrustkeystorealias

echoinfo "客户端证书库名称: "$clientkeystore
echoinfo "客户端证书库别名: "$clientkeystorealias

echoinfo "客户端信任证书库名称: "$clienttrustkeystore
echoinfo "客户端信任证书库别名: "$clienttrustkeystorealias

echowarn "服务器证书库密码: "$serverstorepass
echowarn "   服务器key密码: "$serverkeypass

echowarn "客户端证书库密码: "$clientstorepass
echowarn "   客户端key密码: "$clientkeypass

echoinfo "开始创建证书库和证书..."
echoinfo "创建证书输出目录: "$genkeys_path
mkdir "$genkeys_path"

echowarn "(绝密) 证书密钥日志文件: $KLOGFILE"
echowarn "(绝密) springboot 配置文件: $SBSSLCFG"

echo "$(date +'%Y-%m-%d %H:%M:%S')" > "$KLOGFILE"
echo "此文件绝密, 不可泄漏! $(date +'%Y-%m-%d %H:%M:%S')" >> "$KLOGFILE"
echo "服务器证书库密码: $serverstorepass" >> "$KLOGFILE"
echo "服务器key密码: $serverkeypass" >> "$KLOGFILE"

echo "客户端证书库密码: $clientstorepass" >> "$KLOGFILE"
echo "客户端key密码: $clientkeypass" >> "$KLOGFILE"

echo "Java证书工具: "$JAVA_KEYTOOL >> "$KLOGFILE"
echo "证书创建时间: $(date +'%Y-%m-%d')" >> "$KLOGFILE"
echo "证书有效期天: $VALID_DAYS" >> "$KLOGFILE"

echo "服务器 DN: $serverdname" >> "$KLOGFILE"
echo "客户端 DN: $clientdname" >> "$KLOGFILE"

echo "服务器证书库(JKS)名称: $serverkeystore" >> "$KLOGFILE"
echo "服务器证书库别名: $serverkeystorealias" >> "$KLOGFILE"

echo "服务器信任证书库名称: $servertrustkeystore" >> "$KLOGFILE"
echo "服务器信任证书库别名: $servertrustkeystorealias" >> "$KLOGFILE"

echo "客户端证书库名称: $clientkeystore" >> "$KLOGFILE"
echo "客户端证书库别名: $clientkeystorealias" >> "$KLOGFILE"

echo "客户端信任证书库名称: $clienttrustkeystore" >> "$KLOGFILE"
echo "客户端信任证书库别名: $clienttrustkeystorealias" >> "$KLOGFILE"

# 此证书包含私钥可以给 php 客户端使用, 但是不能用于浏览器!
echo "客户端 PEM 证书库: $clientkeystore.pem" >> "$KLOGFILE"

echo "服务器公钥证书: server_pub.cer" >> "$KLOGFILE"
echo "客户端公钥证书: client_pub.cer" >> "$KLOGFILE"

###########################################################
echoinfo "[1] 创建服务器JKS证书库: $genkeys_path/$serverkeystore"

$JAVA_KEYTOOL -genkeypair -storetype JKS \
    -alias "$serverkeystorealias" \
    -keypass "$serverkeypass" \
    -storepass "$serverstorepass" \
    -dname "$serverdname" \
    -keyalg RSA -keysize 2048 \
    -validity "$VALID_DAYS" \
    -keystore "$genkeys_path/$serverkeystore"

echoinfo "[1] 从服务器证书库导出服务器公钥证书: server_pub.cer"
$JAVA_KEYTOOL -exportcert \
    -keystore "$genkeys_path/$serverkeystore" \
    -file "$genkeys_path/server_pub.cer" \
    -alias "$serverkeystorealias" \
    -storepass "$serverstorepass"


###########################################################
# 为了能将证书顺利导入至IE和Firefox，证书格式应该是PKCS12
echoinfo "[2] 创建客户端 PKCS12 证书库(可以导入火狐浏览器等客户端): "
$JAVA_KEYTOOL -genkeypair -storetype PKCS12 \
    -alias "$clientkeystorealias" \
    -keypass "$clientkeypass" \
    -storepass "$clientstorepass" \
    -dname "$clientdname" \
    -keyalg RSA -keysize 2048 \
    -validity "$VALID_DAYS" \
    -keystore "$genkeys_path/$clientkeystore"

echoinfo "[2] 导出客户端公钥证书: client_pub.cer"
$JAVA_KEYTOOL -exportcert \
    -keystore "$genkeys_path/$clientkeystore" \
    -file "$genkeys_path/client_pub.cer" \
    -alias "$clientkeystorealias" \
    -storepass "$clientstorepass"


###########################################################
if [ "$serverkeystore" = "$servertrustkeystore" ]; then
    echoinfo "[3] 将客户端公钥证书 client_pub.cer 导入服务器证书库: "$serverkeystore

    $JAVA_KEYTOOL -import -v -file "$genkeys_path/client_pub.cer" -keystore "$genkeys_path/$serverkeystore"
else
    echoinfo "[3] 将客户端公钥证书导入服务器信任(客户端)证书库: "$servertrustkeystore

    $JAVA_KEYTOOL -importcert -storetype JKS \
    -keystore "$genkeys_path/$servertrustkeystore" \
    -file "$genkeys_path/client_pub.cer" \
    -alias "$servertrustkeystorealias" \
    -storepass "$serverstorepass" \
    -noprompt
fi


###########################################################
if [ "$clientkeystore" = "$clienttrustkeystore" ]; then
    echoinfo "[4] 将服务器公钥证书 server_pub.cer 导入客户端证书库: "$clientkeystore
    $JAVA_KEYTOOL -import -v -file $genkeys_path/server_pub.cer -keystore $genkeys_path/$clienttrustkeystore
else
    echoinfo "[4] 将服务器公钥证书导入客户端信任(服务器)证书库: "$clienttrustkeystore

    $JAVA_KEYTOOL -importcert -storetype PKCS12 \
    -keystore "$genkeys_path/$clienttrustkeystore" \
    -file "$genkeys_path/server_pub.cer" \
    -alias "$clienttrustkeystorealias" \
    -storepass "$clientstorepass" \
    -noprompt
fi


###########################################################
echoinfo "打印服务器公钥证书: "$genkeys_path/server_pub.cer
$JAVA_KEYTOOL -printcert -file "$genkeys_path/server_pub.cer"

echoinfo "打印客户端公钥证书: "$genkeys_path/client_pub.cer
$JAVA_KEYTOOL -printcert -file "$genkeys_path/client_pub.cer"


###########################################################
echoinfo "[5] 客户端 pkcs12 证书转换到 pem: ""$genkeys_path/$clientkeystore.pem"
openssl pkcs12 -in "$genkeys_path/$clientkeystore" -out "$genkeys_path/$clientkeystore".pem -nodes -passin pass:"$clientstorepass"

###########################################################
echoinfo "[6] 服务器 jks 证书转换到 pem: ""$genkeys_path/$serverkeystore.pem"

$JAVA_KEYTOOL -importkeystore \
    -srckeystore "$genkeys_path/$serverkeystore" \
    -srcstoretype JKS \
    -srcstorepass "$serverstorepass" \
    -srcalias "$serverkeystorealias" \
    -srckeypass "$serverkeypass" \
    -destkeystore "$genkeys_path/$serverkeystore".p12 \
    -deststoretype PKCS12 \
    -deststorepass "$serverstorepass" \
    -destalias "$serverkeystorealias" \
    -destkeypass "$serverkeypass" \
    -noprompt

openssl pkcs12 -in "$genkeys_path/$serverkeystore".p12 -out "$genkeys_path/$serverkeystore".pem -nodes -passin pass:"$serverstorepass"

###########################################################
echo "#---------------------------------------------------" > "$SBSSLCFG"
echo "# springboot ssl config: application.properties" >> "$SBSSLCFG"
echo "#-----------------BEGIN-----------------------------" >> "$SBSSLCFG"
echo "# SSL config" >> "$SBSSLCFG"
echo "#  http://archive.mozilla.org/pub/firefox/releases/" >> "$SBSSLCFG"
echo "server.ssl.enabled=true" >> "$SBSSLCFG"
echo "" >> "$SBSSLCFG"
echo "# 如果服务端需要认证客户端, 下面一句一定要加上！" >> "$SBSSLCFG"
echo "server.ssl.client-auth=need" >> "$SBSSLCFG"
echo "" >> "$SBSSLCFG"
echo "server.ssl.key-store=classpath:$serverkeystore" >> "$SBSSLCFG"
echo "server.ssl.key-store-password=$serverstorepass" >> "$SBSSLCFG"
echo "server.ssl.key-alias=$serverkeystorealias" >> "$SBSSLCFG"
echo "server.ssl.keyAlias=$serverkeystorealias" >> "$SBSSLCFG"
echo "server.ssl.key-store-type=JKS" >> "$SBSSLCFG"
echo "server.ssl.keyStoreType=JKS" >> "$SBSSLCFG"
echo "" >> "$SBSSLCFG"
echo "server.ssl.trust-store=classpath:$servertrustkeystore" >> "$SBSSLCFG"
echo "server.ssl.trust-store-password=$serverstorepass" >> "$SBSSLCFG"
echo "server.ssl.trust-store-type=JKS" >> "$SBSSLCFG"
echo "server.ssl.trust-store-provider=SUN" >> "$SBSSLCFG"
echo "#-------------------END-----------------------------" >> "$SBSSLCFG"
###########################################################

exit 0
