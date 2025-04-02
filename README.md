### 1、解压文件

把压缩包在本地先执行解压，文件夹结构如下

![image](https://github.com/user-attachments/assets/0d10f3b1-0800-41a2-afb2-2c41bb364cb9)


### 2、配置docker-run

打开docker-run.yml文件

1. 修改数据目录，避免默认目录磁盘空间不够，如果够可以不修改，把引用这个变量的去除掉
    
    把`DOCKER_DATA`变量的值改为自己要存储的路径
    

![image](https://github.com/user-attachments/assets/e171870c-1f71-4803-a1a9-da0676a9a75e)


1. 如果要进行远程使用idea控制docker需要配置TLS证书
    1. `SERVER_IP`：改为本机的ip
    2. `CERT_DIR`：改为自己需要存放tls证书的地址
    
    <img width="637" alt="image" src="https://github.com/user-attachments/assets/4b0bb0c7-4904-47cf-bc5d-5aab949ea9b2" />

    
2. 修改镜像加速地址
    
    ![image](https://github.com/user-attachments/assets/b7b22b9a-dbc2-44bc-b195-4c9d1645e23a)

    

### 3、配置docker-compose.yml文件

修改每一个`service`的`ports`端口映射，改为自己需要的主机端口

注意点：

1. `mysql`初始化数据库
    
    把需要初始化的数据库文件放入到`initdb`文件夹下，尽量不要放入大批量的`INSERT`语句的sql文件，可以等创建好后在执行
    
    ![image.png](attachment:765f41da-d174-47bd-a564-49429a67a008:image.png)
    

1. nginx.conf
    
    ![image](https://github.com/user-attachments/assets/5790e668-79bf-475a-aafc-04c8d4490dc2)

    
    1. nginx.conf配置文件做监听端口需要使用容器的端口，项目地址也是，项目文件地址因为做了文件映射，所以只需要写到html下面就行
        
        ![image](https://github.com/user-attachments/assets/cb601dc9-2448-46dd-bd62-38d845bad82b)

        

### 4、 执行部署

把修改好的docker-deploy文件夹放入服务器

1. 创建docker
    
    进入docker-deploy文件下，执行`sh [docker-run.sh](http://docker-run.sh/)`
    
    出现下面提示代表成功，
    
    ![image](https://github.com/user-attachments/assets/815fe1be-4202-480a-ac34-c86003bffe48)

    
    按照提示编辑`vim /usr/lib/systemd/system/docker.service`文件
    
    ![image](https://github.com/user-attachments/assets/92c87de5-c831-4a5e-a873-9ba01c3f22eb)

    
    把自己返回的内容添加到`ExecStart`后面  
    
    在执行
    
    - 更新配置：`systemctl daemon-reload`
    - 重启docker：`systemctl restart docker`
    - 查看是否启动成功：`systemctl status docker`
    
2. idea配置远程连接（如果不需要远程监控省略）
    1. 下载证书到本地：`key.pem、cert.pem、ca.pem` ，提示里面可以看位于什么目录下
    2. 打开idea进入配置：`Settings>Build>Docker`目录下，
        1. 配置远程服务器的IP，端口(2376加密端口)，
        2. 配置存放下载下来的加密文件的路径
        
        出现`Connection successful`就成功了
        
    
    ![Uploading image.png…]()

