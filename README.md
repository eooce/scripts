# xray-reality
This is a reality no interaction one-click script，only support Debian10+/Ubuntu20+/Centos7+/Fedora8+
#
## Install
Run the following command. The PORT can be customized
```
 PORT=8880 bash -c "$(curl -L https://raw.githubusercontent.com/eooce/xray-reality/master/reality.sh)"
```
Hysteria2
```
bash -c "$(curl -L https://raw.githubusercontent.com/eooce/xray-reality/master/Hysteria2.sh)"
```
## Uninstall
```
 bash -c "$(curl -L https://raw.githubusercontent.com/eooce/xray-reality/master/uninstall.sh)"
``` 

## Installation Guide with Docker 

0. install docker 
``` bash
curl -fsSL https://get.docker.com | sh
```
1. clone this project 
``` bash
git clone https://github.com/eooce/xray-reality && cd xray-reality
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
