
## 利用 openssl 管理证书及 SSL 编程

Copyright (c) 2024-09-19, mapaware.top

java web 服务器请使用 jkscerts.sh 自动化工具创建证书库和证书！
其他请使用 openssl 工具。

参考：

- 利用openssl创建一个简单的CA
http://www.cppblog.com/flyonok/archive/2010/10/30/131840.html

- Win32平台下OpenSSL编写SSL,TLS程序
http://www.cppblog.com/flyonok/archive/2011/03/24/133100.html


CA（Certification Authority），简称CA证书。CA 也拥有一个证书（内含公钥和私钥）。网上的公众用户通过验证 CA 的签字从而信任 CA ，任何人都可以得到 CA 的证书（含公钥），用以验证它所签发的证书。如果用户想得到一份属于自己的证书，他应先向 CA 提出申请。在 CA 判明申请者的身份后，便为他分配一个公钥，并且 CA 将该公钥与申请者的身份信息绑在一起，并为之签字后，便形成证书发给申请者。

如果一个用户想鉴别另一个证书的真伪，他就用 CA 的公钥对那个证书上的签字进行验证，一旦验证通过，该证书就被认为是有效的。证书实际是由证书签证机关（CA）签发的对用户的公钥的认证。

证书的内容包括：电子签证机关的信息、公钥用户信息、公钥、权威机构的签字和有效期等等。目前，证书的格式和验证方法普遍遵循X.509 国际标准。

CA一般指证书授权机构，比如VeriSign, Startssl。浏览器内嵌了这些公司的公钥证书，这样用户使用由这些公司颁发出来的证书就得到了浏览器的信任，不会提示用户安全问题。

也可以认为CA是得到了浏览器厂商认证的授权证书颁发机构，谁都可以成为CA，但要想得到浏览器厂商认证是非常难的。如果得到了浏览器厂商认证的CA，其颁发的证书都会被浏览器检查通过放行，否则浏览器要提示用户有证书需要安装，让用户自己承担风险，这些提示常常被认为是不愉快的（比如12306.cn）。

如果接受了（无论提示与否），浏览器就安装了这个证书，于是访问网站就在一个安全的隧道中进行，这个隧道称为 SSL（Secure Sockets Layer 安全套接层）及其继任者传输层安全（Transport Layer Security，TLS）。

用商业的CA证书，都是要花钱的，而且不便宜。除非用自己的证书，就涉及到浏览器接受的问题。免费的startssl可以解决一部分问题，烦人的是需要1年1签。

假定我们可以接受这个浏览器提示，或者我们根本就是在写一个ssl程序，那么自己做CA完全没问题。自己做老大的感觉很爽。下面就让我们利用开源openssl软件，在Linux（或UNIX/Cygwin）下创建一个简单的CA。我们可以利用这个CA进行PKI、数字证书相关的测试。比如，在测试用Tomcat或Apache构建HTTPS双向认证时，我们可以利用自己建立的测试CA来为服务器端颁发服务器数字证书，为客户端（浏览器）生成文件形式的数字证书（可以同时利用openssl生成客户端私钥）。

### 1 创建 CA

假定我的公司叫做 mapaware，我的网站叫 mapaware.top（这是我个人使用的域名），我想建立公司的 CA，并且给自己的网站颁发服务器证书，给使用我的网站的用户颁发客户端证书。下面开始创建我的 CA。（用户可以把 mapaware 换成你公司的名字）。该简单的 CA 将建立在用户自己的主目录　$HOME　下，无需超级用户（root）权限。

- 1.1 创建 CA 需要用到的目录和文件

        $ mkdir -p $HOME/ca.mapaware.top/{newcerts,private,conf}
        $ chmod g-rwx,o-rwx $HOME/ca.mapaware.top/private
        $ echo "01" > $HOME/ca.mapaware.top/serial
        $ touch $HOME/ca.mapaware.top/index.txt
    **说明：**

    - $HOME/ca.mapaware.top 为待建的 CA 主目录(以下简称 CA_HOME )。
    - newcerts 目录将存放 CA 签署（颁发）过的数字证书（证书备份目录）。
    - private 目录用于存放 CA 的私钥（mapawarecakey.pem）。
    - conf 目录用于存放一些简化参数用的配置文件。
    - 文件 serial 和 index.txt 分别用于存放下一个证书的序列号和证书信息数据库。
    

- 1.2 生成 CA 的私钥和自签名证书（即根证书 mapawarecacert.pem）

    - 创建配置文件（$HOME/ca.mapaware.top/conf/genmapawareca.conf）：
        ```
        [req]
        default_keyfile=$ENV::HOME/ca.mapaware.top/private/mapawarecakey.pem
        default_md=md5
        prompt=no
        distinguished_name=ca_distinguished_name
        x509_extensions=ca_extensions

        [ca_distinguished_name]
        organizationName=mapaware.top
        organizationalUnitName=ca.mapaware.top
        commonName=mapawareca
        emailAddress=master@mapaware.top

        [ca_extensions]
        basicConstraints=CA:true
        ```

    - 生成 CA 根证书:
  
          $ CA_HOME=$HOME/ca.mapaware.top
          $ cd $CA_HOME
          $ openssl req -x509 -newkey rsa:2048 -out mapawarecacert.pem -outform PEM -days 3650 -config $CA_HOME/conf/genmapawareca.conf

        **警告：执行过程中需要2次输入 CA 私钥的保护密码（Enter PEM pass phrase: ?），万万不可泄露，这里假设是：123456**

        可以用命令查看一下 CA 根证书的内容：

            $ openssl x509 -in mapawarecacert.pem -text -noout

- 1.3 为后续 CA 日常操作中使用，创建一个配置文件（$CA_HOME/conf/mapawareca.conf）：
    ```
    [ca]
    # The default ca section
    default_ca=mapawareca

    [mapawareca]
    # top dir
    dir=$ENV::HOME/ca.mapaware.top

    # index file
    database=$dir/index.txt

    # new certs dir
    new_certs_dir=$dir/newcerts

    # The CA cert
    certificate=$dir/mapawarecacert.pem

    # serial no file
    serial=$dir/serial

    # CA private key
    private_key=$dir/private/mapawarecakey.pem

    # random number file
    RANDFILE=$dir/private/.rand

    # how long to certify for
    default_days=365

    # how long before next CRL
    default_crl_days=30

    # message digest method to use
    default_md=md5

    # Set to 'no' to allow creation of several ctificates with same subject
    unique_subject=no

    # default policy
    policy=policy_any

    [policy_any]
    countryName=optional
    stateOrProvinceName=optional
    localityName=optional
    organizationName=optional
    organizationalUnitName=optional
    commonName=supplied
    emailAddress=optional
    ```

### 2 CA 签发数字证书

现在我们已经是 CA 了，如果我们的根证书（公钥）能被浏览器厂商接受，嵌入到火狐浏览器中，那么我们就可以用这个 CA 给某个网站（如 a.com）签发证书，当用户用火狐访问https://a.com，ssl(tls) 就起作用了，往来信息被证书加密和解密，就能因此建立起端到端的信任机制：用户信任网站 a.com 的确是 a.com（不是被中途拦截篡改后的 a.com）；a.com 可以信任访问它的用户（不是中途被拦截篡改后的用户）。

下面演示如何用 CA 给网站 mapaware.top（相当于上面的 a.com）签发一个证书。

#### 2.1 创建一个证书请求

假设 a.com 要建立 https 的网站，于是请求我们（CA 颁发机构）给他们网站签发一个证书，首先要创建一个证书请求：

    $ mkdir $CA_HOME/newcerts/a.com
    $ cd $CA_HOME/newcerts/a.com
    $ openssl req -newkey rsa:1024 -keyout acomkey.pem -keyform PEM -out acomreq.pem -outform PEM -subj "/O=a.com/OU=ou.a.com/CN=a.com"
   
    执行过程中需要设置私钥的保护密码（Enter PEM pass phrase:?），设为密码： 888888。执行成功，acomkey.pem 即为私钥，而 acomreq.pem 即为证书请求。查看证书请求的内容：
    
    $ openssl req -in acomreq.pem -text -noout

    使用 acomkey.pem 私钥需要指定密码（888888），很不方便，下面去除这个密码：

    $ openssl rsa -in acomkey.pem -out acomkey_nopass.pem

    生成的文件 acomkey_nopass.pem 就是不包含密码的私钥。


#### 2.2 CA 为网站 a.com 签发证书

    $ openssl ca -in acomreq.pem -out acomcert.pem -config $HOME/ca.mapaware.top/conf/mapawareca.conf

执行过程中需要输入 CA 的密钥保护密码（这里是：123456），并且最后询问是否要给该用户签发证书时要选 y。执行成功后用命令查看证书内容：
    $ openssl x509 -in acomcert.pem -text -noout

#### 2.3 制作个人数字证书（PKCS12 格式的文档）

本节 “个人数字证书” 意为包含私钥和证书的实体，而不是单指只保护公钥的数字证书。我们制作的这个 PKCS#12 文件将包含密钥、证书和颁发该证书的 CA（根证书）。该证书文件可以直接用于服务器数字证书或个人数字证书。把前几步生成的密钥和证书制作成一个 pkcs12 文件mapawaretopcert.p12：

  $ openssl pkcs12 -export -in acomcert.pem -inkey acomkey.pem -out acom.p12 -name a.com -chain -CAfile $HOME/ca.mapaware.top/mapawarecacert.pem

执行过程中需要输入 a.com 密钥的保护密码（888888），以及设置新的保护 pkcs12 文件的密码，如：666666。acom.p12 即为 pkcs12 文件，你可以直接将其拷贝到 Windows 下，作为个人数字证书，双击导入 IE 后就可以使用了（需要输入密码：666666）。该文件也可以直接用于服务器证书使用。例如网站：a.com 使用了 java jetty 服务，就可以将证书配置为 jetty 使用以保护网站。

查看 acom.p12 的内容可以用命令:
  $ openssl pkcs12 -in acom.p12 -nodes
    Enter Import Password: 666666

PKCS12 证书（包含密钥、证书和颁发该证书的 CA 证书） 转为 PEM 格式:

  $ openssl pkcs12 -in acom.p12 -out acom_p12.pem -password pass:"666666" -nodes


参考：https://stackoverflow.com/questions/40399690/enter-pem-pass-phrase-when-converting-pkcs12-certificate-into-pem

### 3 CA的日常操作

3.1. 根据证书申请请求签发证书

假设收到一个证书请求文件名为 myreq.pem，文件格式应该是PKCS#10格式（标准证书请求格式）。首先可以查看一下证书请求的内容，执行命令：

    $ openssl req -in myreq.pem -text -noout

将看到证书请求的内容，包括请求者唯一的名字（DN）、公钥信息（可能还有一组扩展的可选属性）。执行签发命令：

    $ openssl ca -in myreq.pem -out mycert.pem -config $HOME/ca.mapaware.top/conf/mapawareca.conf

执行过程中会要求输入访问 CA 的私钥密码（123456）。完成上一步后，签发好的证书就是 mycert.pem，另外 “$HOME/ca.mapaware.top/newcerts/” 里也会有一个相同的证书副本（文件名为证书序列号, 如: 01.pem）。执行以下语句查看生成的证书的内容：

    $ openssl x509 -in mycert.pem -text -noout

3.2. 吊销证书（作废证书）

一般由于用户私钥泄露等情况才需要吊销一个未过期的证书。（当然我们用本测试 CA 时其时很少用到该命令，除非专门用于测试吊销证书的情况）。假设需要被吊销的证书文件为 cert.pem，则执行以下命令吊销证书：
  
    $ openssl ca -revoke cert.pem -config $HOME/ca.mapaware.top/conf/mapawareca.conf

3.3. 生成证书吊销列表文件（CRL）

准备公开被吊销的证书列表时，可以生成证书吊销列表（CRL），执行命令如下：
  
    $ openssl ca -gencrl -out mapawareca.crl -config $HOME/ca.mapaware.top/conf/mapawareca.conf

还可以添加-crldays和-crlhours参数来说明下一个吊销列表将在多少天后（或多少小时候）发布。用以下命令检查 mapawareca.crl 的内容：

    $ openssl crl -in mapawareca.crl -text -noout
