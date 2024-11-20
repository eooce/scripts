#!/bin/bash
# (crontab -l 2>/dev/null; echo "0 3 * * 0 bash /root/uplod_r2.sh > /root/uplod.log 2>&1") | crontab -    
# 复制以上命令回车自动添加crontab定时任务，每周日凌晨3点执行,如果只想上传一次，只需运行此shell文件一次即可

export R2_REGION="APAC"       # 存储桶区域 (APAC为亚太，WNAM为美西，ENAM为美东，EEUR为东欧，WEUR为西欧)
export CLOUDFLARE_API_TOKEN="abcdefghijkendfdvsdfdbdvdsfsadsasasadsa-"  # Cloudflare API key
export CLOUDFLARE_ACCOUNT_ID="8b9724080e54370370fb74287922vj5677"       # Cloudflare 账户 ID

set -e  # 出错时退出脚本
set -u  # 使用未定义变量时报错
set -o pipefail  # 捕获管道中的错误

# 架构列表和映射
ARCHS=("amd64" "arm64")
declare -A ARCH_MAP=(
    ["amd64"]="64"
    ["arm64"]="arm64-v8a"
)

# 获取 sing-box 最新版本号
sb_latest_version=$(curl -s "https://api.github.com/repos/SagerNet/sing-box/releases" | jq -r '[.[] | select(.prerelease==false)][0].tag_name | sub("^v"; "")')
# 下载 URL 定义
declare -A DOWNLOAD_URLS=(
    ["xray"]="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux"
    ["nezha-agent"]="https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux"
    ["sing-box"]="https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-${sb_latest_version}-linux"
    ["cloudflared"]="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux"
)

# 安装依赖工具
install_dependencies() {
    echo "检查并安装依赖..."
    if ! command -v wrangler &>/dev/null; then
        echo "安装 wrangler CLI..."
        npm install -g wrangler
    fi
    
    apt-get install -y upx-ucl unzip wget tar curl jq
}

# 自动登录到 Cloudflare R2
login_to_cloudflare() {
    echo "使用 API Token 验证..."
    if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
        echo "错误：CLOUDFLARE_API_TOKEN 未设置"
        exit 1
    fi
    
    if CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN" wrangler whoami &>/dev/null; then
        echo "API Token 验证成功。"
    else
        echo "API Token 验证失败，请检查 Token 是否正确。"
        exit 1
    fi
}

# 检查并创建存储桶
check_or_create_bucket() {
    local bucket_name="$1"
    echo "检查存储桶是否存在：$bucket_name"
    
    local response
    response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT_ID/r2/buckets" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json")
    
    if echo "$response" | jq -e ".result.buckets[] | select(.name == \"$bucket_name\")" > /dev/null 2>&1; then
        echo "存储桶 $bucket_name 已存在，继续执行..."
        return 0
    else
        echo "存储桶 $bucket_name 不存在，正在创建..."
        CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN" wrangler r2 bucket create "$bucket_name"
        echo "存储桶创建成功。"
        return 0
    fi
}

# 上传文件到存储桶
upload_to_r2() {
    local file_path="$1"
    local bucket_name="$2"
    local dest_key="$3"
    local content_type="$4"

    echo "上传文件 $file_path 到存储桶 $bucket_name/$dest_key"

    if [ -n "$content_type" ]; then
        CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN" wrangler r2 object put "$bucket_name/$dest_key" --file="$file_path" --content-type="$content_type"
    else
        CLOUDFLARE_API_TOKEN="$CLOUDFLARE_API_TOKEN" wrangler r2 object put "$bucket_name/$dest_key" --file="$file_path"
    fi
}

# 下载和处理文件
process_files() {
    local arch="$1"
    local xray_arch="${ARCH_MAP[$arch]}"
    echo "下载和处理 $arch 架构的文件..."
    
    # nezha-agent
    echo "处理 nezha-agent..."
    wget "${DOWNLOAD_URLS["nezha-agent"]}_${arch}.zip" -O nezha-agent.zip
    unzip -o nezha-agent.zip
    chmod +x nezha-agent
    
    # xray
    echo "处理 xray..."
    wget "${DOWNLOAD_URLS["xray"]}-${xray_arch}.zip" -O xray.zip
    unzip -o xray.zip
    chmod +x ./xray
    
    # cloudflared
    echo "处理 cloudflared..."
    wget "${DOWNLOAD_URLS["cloudflared"]}-${arch}" -O cloudflared
    chmod +x cloudflared
    
    # sing-box
    echo "处理 sing-box..."
    wget "${DOWNLOAD_URLS["sing-box"]}-${arch}.tar.gz" -O sing-box.tar.gz
    tar xzf sing-box.tar.gz
    mv sing-box-*/sing-box ./sing-box
    chmod +x sing-box

    echo "压缩文件..."
    # 验证文件存在
    for file in nezha-agent xray cloudflared sing-box; do
        if [ ! -f "./$file" ]; then
            echo "错误：$file 文件不存在！"
            ls -la
            return 1
        fi
    done

    # 压缩文件
    upx -9 ./nezha-agent -o npm
    upx -9 ./xray -o web
    upx -9 ./cloudflared -o bot
    upx -9 ./sing-box -o sbx
}

# 验证文件
validate_files() {
    echo "验证压缩后的文件..."
    for file in npm web bot sbx; do
        if [ ! -f "$file" ]; then
            echo "错误：$file 未找到"
            return 1
        fi

        size=$(stat --format="%s" "$file")
        if [ "$size" -lt 5000000 ]; then  # 小于 5MB
            echo "错误：$file 文件大小异常 ($size bytes)"
            return 1
        fi
    done
    return 0
}

# 主程序
main() {
    # 安装依赖
    install_dependencies

    # 登录 Cloudflare
    login_to_cloudflare

    # 循环处理每个架构
    for arch in "${ARCHS[@]}"; do
        BUCKET_NAME="${arch}"
        check_or_create_bucket "$BUCKET_NAME"

        echo "正在处理架构：$arch"
        
        # 创建工作目录
        rm -rf "$arch" && mkdir -p "$arch"
        cd "$arch"

        # 下载和处理文件
        if process_files "$arch"; then
            # 验证文件
            if validate_files; then
                echo "上传到存储桶：$BUCKET_NAME"
                upload_to_r2 "npm" "$BUCKET_NAME" "npm" "application/x-elf"
                upload_to_r2 "web" "$BUCKET_NAME" "web" "application/x-elf"
                upload_to_r2 "bot" "$BUCKET_NAME" "bot" "application/x-elf"
                upload_to_r2 "sbx" "$BUCKET_NAME" "sbx" "application/x-elf"
            else
                echo "文件验证失败，跳过上传..."
            fi
        else
            echo "文件处理失败，跳过验证和上传..."
        fi
    done

    echo "所有文件处理和上传完成！"
    rm -rf amd64
}

main
