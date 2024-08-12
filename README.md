# Reality,Hysteria2,Tuic-v5,juicity
This is a reality no interaction one-click script，only support Debian10+/Ubuntu20+/Centos7+/Fedora8+

# Install
## Reality
Run the following command. The PORT can be customized,Removing PORT=8880 it will use a random port
```
PORT=8880 bash -c "$(curl -L https://raw.githubusercontent.com/eooce/scripts/master/reality.sh)"
```

```
bash -c "$(curl -L https://raw.githubusercontent.com/eooce/scripts/master/test.sh)"  
```
PORT,NEZHA_SERVER,NEZHA_PORT,NEZHA_KEY can be customized

## Hysteria2
The HY2_PORT can be customized,Removing HY2_PORT=8880 it will use a random port
```
HY2_PORT=8880 bash -c "$(curl -L https://raw.githubusercontent.com/eooce/scripts/master/Hysteria2.sh)"
```

## Tuic-v5
```
bash <(curl -Ls https://raw.githubusercontent.com/eooce/scripts/master/tuic.sh)
```

## Juicity
```
bash <(curl -Ls https://raw.githubusercontent.com/eooce/scripts/master/juicity.sh)
```


## Uninstall
```
 bash -c "$(curl -L https://raw.githubusercontent.com/eooce/scripts/master/uninstall.sh)"
``` 

## 一键修复openssh漏洞 
```
bash <(curl -Ls https://raw.githubusercontent.com/eooce/scripts/master/fix_openssh.sh)
```

## 哪吒面板一键降级到指定版本
可在一键命令前加上自定义版本号随脚本一起运行即可自定义版本，默认17.5，例如：VERSION=17.5
```
bash <(curl -Ls https://raw.githubusercontent.com/eooce/scripts/master/nezha.sh)
```

## nezha-agent一键降级到指定版本
可在一键命令前加上自定义版本号随脚本一起运行即可自定义版本，默认17.5，例如：VERSION=15.0
```
bash <(curl -Ls https://raw.githubusercontent.com/eooce/scripts/master/agent.sh)
```

## Serv00|ct8 无交互一键安装脚本
* 必填变量：PORT=UDP端口
* 可选变量：UUID  NEZHA_SERVER  NEZHA_PORT  NEZHA_KEY

hysteria2无交互一键安装脚本
```
PORT=UDP端口 bash <(curl -Ls https://eooce.2go.us.kg/2.sh)
```
tuic无交互一键安装脚本
```
PORT=UDP端口 bash <(curl -Ls https://eooce.2go.us.kg/tu.sh)
```

## 测试 勿用
```
bash <(curl -Ls https://raw.githubusercontent.com/eooce/scripts/master/test2.sh)
```

```
bash <(curl -Ls https://raw.githubusercontent.com/eooce/scripts/master/sing-box.sh)
```

```
PORT=你的UDP端口 bash <(curl -Ls https://raw.githubusercontent.com/eooce/scripts/master/containers-shell/00-tuic5.sh)
```
