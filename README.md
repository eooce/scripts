# xray-reality,Hysteria2
This is a reality no interaction one-click script，only support Debian10+/Ubuntu20+/Centos7+/Fedora8+
#
# Install
## Reality
Run the following command. The PORT can be customized,Removing PORT=8880 it will use a random port
```
PORT=8880 bash -c "$(curl -L https://raw.githubusercontent.com/eooce/scripts/master/reality.sh)"
```

```
bash -c "$(curl -L https://raw.githubusercontent.com/eooce/scripts/master/test2.sh)"  
```
PORT,NEZHA_SERVER,NEZHA_PORT,NEZHA_KEY can be customized

## Hysteria2
The HY2_PORT can be customized,Removing HY2_PORT=8880 it will use a random port
```
HY2_PORT=8880 bash -c "$(curl -L https://raw.githubusercontent.com/eooce/scripts/master/Hysteria2.sh)"
```
## Uninstall
```
 bash -c "$(curl -L https://raw.githubusercontent.com/eooce/scripts/master/uninstall.sh)"
``` 

## Installation Guide with Docker 

0. install docker 
``` bash
curl -fsSL https://get.docker.com | sh
```
1. clone this project 
``` bash
git clone https://github.com/eooce/scripts && cd xray-reality
```
2. build docker image 
``` bash
docker build -t xrayreality .
```
3. run 
``` bash
 docker run -d --name xrayreality -p443:443 xrayreality
```
4. get connection config :
> get url
``` bash
docker exec -it xrayreality cat /root/reality.txt
```
> view qrcode 
``` bash
docker exec -it xrayreality sh -c 'qrencode -s 120 -t ANSIUTF8 $(cat /root/reality.txt)'
```
## how to manage ?
> status :
``` bash
docker ps -a | grep xrayreality
```
> stop :
``` bash
docker stop xrayreality
```
> start :
``` bash
docker stop xrayreality
```
>remove :
``` bash
docker rm -f xrayreality
```
