#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 欢迎界面
clear
echo -e "${BLUE}=============================================================${NC}"
echo -e "${GREEN}       欢迎使用 NewsPush 一键部署脚本 (小白专用版)       ${NC}"
echo -e "${BLUE}=============================================================${NC}"
echo -e "这个脚本将帮助您："
echo -e "1. 自动安装 Docker (如果还没有的话)"
echo -e "2. 部署 60s 新闻 API 服务"
echo -e "3. 设置定时任务，每天早上自动推送到您的飞书"
echo -e ""
echo -e "${YELLOW}您只需要回答几个简单的问题即可完成配置！${NC}"
echo -e "${BLUE}=============================================================${NC}"
echo ""

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}请使用 root 权限运行此脚本！${NC}"
  echo "试试命令：sudo bash $0"
  exit 1
fi

# 1. 基础环境检查与安装
echo -e "${BLUE}[1/5] 检查环境...${NC}"

# 检查 jq (用于处理 JSON)
if ! command -v jq &> /dev/null; then
    echo -e "正在安装必要工具 jq..."
    if [ -f /etc/debian_version ]; then
        apt-get update && apt-get install -y jq
    elif [ -f /etc/redhat-release ]; then
        yum install -y jq
    elif [ -f /etc/alpine-release ]; then
        apk add jq
    fi
fi

echo ""

# 2. 获取用户配置
echo -e "${BLUE}[2/5] 配置您的推送服务${NC}"
echo -e "我们需要知道把新闻推送到哪里。推荐使用 ${GREEN}飞书 (Feishu)${NC}，完全免费且稳定。"
echo -e "如果您还没有飞书 Webhook 地址，请查看教程：https://www.feishu.cn/hc/zh-CN/articles/360024984973"
echo ""

# 交互式获取 Webhook
read -p "请输入您的飞书 Webhook 地址 (直接回车使用默认测试地址): " FEISHU_WEBHOOK
if [ -z "$FEISHU_WEBHOOK" ]; then
    FEISHU_WEBHOOK="https://www.feishu.cn/flow/api/trigger-webhook/e9eb3eb901b500ab55b2f44c50194268"
    echo -e "${YELLOW}已使用默认测试地址 (仅供测试，建议后续修改)${NC}"
fi

# 交互式获取安装目录
echo ""
read -p "请输入安装目录 (默认: /home/newspush): " INSTALL_DIR
if [ -z "$INSTALL_DIR" ]; then
    INSTALL_DIR="/home/newspush"
fi
echo -e "${GREEN}将在 ${INSTALL_DIR} 部署服务${NC}"

# 交互式选择是否使用国内镜像加速
echo ""
echo -e "由于 Docker Hub 在国内访问可能较慢，建议开启镜像加速。"
read -p "是否在中国大陆使用？(y/n) (默认: n): " USE_MIRROR

if [[ "$USE_MIRROR" =~ ^[Yy]$ ]]; then
    # 使用用户指定的加速地址 pull.aitgo.netlib.re
    # 假设该地址支持 Docker Registry 代理
    IMAGE_NAME="pull.aitgo.netlib.re/vikiboss/60s:1.1.18"
    echo -e "${GREEN}已选择加速镜像：${IMAGE_NAME}${NC}"
else
    # 默认使用原作者的官方镜像 (支持多架构，稳定可靠)
    IMAGE_NAME="vikiboss/60s:1.1.18"
    echo -e "${GREEN}已选择官方镜像：${IMAGE_NAME}${NC}"
fi

# 检查 Docker 是否安装
if ! command -v docker &> /dev/null; then
    echo -e "正在安装 Docker..."
    curl -fsSL https://get.docker.com | bash
fi

# 交互式获取推送时间
echo ""
echo -e "您希望每天几点推送新闻？(24小时制)"
echo -e "如果想设置多个时间点，请用逗号分隔 (例如: 8,12,18 代表早8点、午12点、晚6点)"
read -p "请输入小时 (默认: 8): " PUSH_HOUR_INPUT
if [ -z "$PUSH_HOUR_INPUT" ]; then
    PUSH_HOUR_INPUT="8"
fi

# 格式化 crontab 时间
# 将中文逗号替换为英文逗号，去除空格
CRON_HOURS=$(echo "$PUSH_HOUR_INPUT" | sed 's/，/,/g' | tr -d ' ')
echo -e "${GREEN}将在每天 ${CRON_HOURS} 点准时为您推送${NC}"

echo ""
echo -e "${BLUE}[3/5] 开始部署服务...${NC}"

# 创建目录
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR" || exit

# 下载必要文件 (这里模拟下载，实际应该从 GitHub 拉取或直接写入)
# 写入推送脚本逻辑
mkdir -p scripts

cat > scripts/push.cjs << 'EOF'
const http = require('http');
const https = require('https');
const url = require('url');

// 配置
const API_URL = process.env.SOURCE_URL || 'http://api:4399';
const WEBHOOK_URL = process.env.FEISHU_WEBHOOK_URL;

if (!WEBHOOK_URL) {
    console.error('未配置 FEISHU_WEBHOOK_URL');
    process.exit(1);
}

// 辅助函数：请求 API
function fetchJson(endpoint) {
    return new Promise((resolve, reject) => {
        http.get(`${API_URL}${endpoint}`, (res) => {
            let data = '';
            res.on('data', (chunk) => data += chunk);
            res.on('end', () => {
                try {
                    const json = JSON.parse(data);
                    resolve(json.code === 200 ? json.data : null);
                } catch (e) {
                    console.error(`解析 ${endpoint} 失败`, e);
                    console.error('原始数据:', data); // 打印原始数据以便调试
                    resolve(null);
                }
            });
        }).on('error', (e) => {
            console.error(`请求 ${endpoint} 失败`, e.message);
            console.error(`完整地址: ${API_URL}${endpoint}`); // 打印完整地址
            resolve(null);
        });
    });
}

// 辅助函数：发送 Webhook
function sendWebhook(content) {
    const webhookUrl = new url.URL(WEBHOOK_URL);
    const options = {
        hostname: webhookUrl.hostname,
        path: webhookUrl.pathname + webhookUrl.search,
        method: 'POST',
        headers: { 'Content-Type': 'application/json' }
    };

    const req = https.request(options, (res) => {
        res.on('data', () => {}); // 消耗响应流
        if (res.statusCode === 200) {
            console.log('✅ 推送成功！');
        } else {
            console.error(`❌ 推送失败，状态码: ${res.statusCode}`);
        }
    });

    req.on('error', (e) => console.error('❌ 推送请求错误', e));
    req.write(JSON.stringify({
        msg_type: 'text',
        content: { text: content }
    }));
    req.end();
}

async function main() {
    console.log('正在获取新闻数据...');
    const [news60s, baidu, toutiao, zhihu] = await Promise.all([
        fetchJson('/v2/60s'),
        fetchJson('/v2/baidu/hot'),
        fetchJson('/v2/toutiao'),
        fetchJson('/v2/zhihu')
    ]);

    let message = '';
    const separator = '='.repeat(50);

    // 1. 60秒读懂世界
    if (news60s) {
        message += `【每日新闻】${news60s.date} ${news60s.day_of_week}\n${separator}\n\n`;
        if (news60s.tip) message += `💡 ${news60s.tip}\n\n`;
        if (Array.isArray(news60s.news)) {
            news60s.news.forEach((n, i) => message += `${i + 1}. ${n}\n\n`);
        }
        if (news60s.link) message += `🔗 原文: ${news60s.link}\n\n`;
    }

    // 2. 热点新闻
    const appendHot = (title, list) => {
        if (!list || list.length === 0) return;
        message += `【${title}热榜】\n${separator}\n`;
        list.slice(0, 10).forEach((item, i) => { // 只取前10条
             const text = item.title || item.keyword || item.name;
             const link = item.url || item.link;
             if (text) {
                 message += `${i + 1}. ${text}\n`;
                 if (link) message += `   🔗 ${link}\n`;
             }
        });
        message += '\n';
    };

    appendHot('百度', baidu);
    appendHot('头条', toutiao);
    appendHot('知乎', zhihu);

    if (!message) {
        console.log('未获取到任何数据，取消推送');
        return;
    }

    message += `${separator}\n来源: NewsPush (基于 60s-api)`;
    
    console.log('正在推送至飞书...');
    sendWebhook(message);
}

main();
EOF

# 4. 启动服务
echo -e "${BLUE}[4/5] 启动服务容器...${NC}"

# 创建专用网络
# 移除 2>/dev/null 以便看到潜在错误
docker network create newspush-network || true

# 清理旧容器
echo -e "正在清理旧容器..."
docker rm -f newspush-api newspush-pusher 2>/dev/null || true

# 启动 API 服务
echo -e "正在启动 API 服务..."
# 强制拉取最新镜像，防止本地缓存了错误的旧镜像
if ! docker pull "$IMAGE_NAME"; then
    echo -e "${YELLOW}镜像 $IMAGE_NAME 拉取失败，尝试切换回官方源 (vikiboss/60s:1.1.18)...${NC}"
    IMAGE_NAME="vikiboss/60s:1.1.18"
    if ! docker pull "$IMAGE_NAME"; then
         echo -e "${RED}错误：无法拉取 API 镜像，请检查网络连接。${NC}"
         exit 1
    fi
fi

docker run -d \
    --name newspush-api \
    --network newspush-network \
    -p 4399:4399 \
    --restart unless-stopped \
    "$IMAGE_NAME"

# 等待服务就绪
echo -e "等待服务就绪..."
TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if docker logs newspush-api 2>&1 | grep -q "service is running"; then
        echo -e "${GREEN}API 服务已启动！${NC}"
        sleep 5 # 额外等待 5 秒确保端口完全就绪
        break
    fi
    # 增加对原作者镜像成功启动日志的兼容 (如果不同)
    if docker logs newspush-api 2>&1 | grep -q "Server running at"; then
        echo -e "${GREEN}API 服务已启动！${NC}"
        sleep 5
        break
    fi
    # 再次增加兼容性：只要不报错退出，且过了 10 秒，我们就认为它可能好了
    if [ $ELAPSED -gt 10 ] && docker ps | grep -q "newspush-api"; then
         # 这里不 break，继续等待以确保更稳，但可以输出个提示
         echo -n "."
    fi
    sleep 1
    ELAPSED=$((ELAPSED+1))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo -e "${YELLOW}警告：服务启动尚未完成，但这可能是正常的（取决于机器性能）。${NC}"
    echo -e "${RED}=== 自动捕获 API 日志 (最后 50 行) ===${NC}"
    docker logs --tail 50 newspush-api
    echo -e "${RED}=======================================${NC}"
    echo -e "${YELLOW}如果上方日志显示报错，请截图反馈。${NC}"
fi

# 启动推送服务 (作为常驻容器，用于执行定时任务)
# 使用 Sidecar 模式：共享 API 容器的网络栈，直接通过 localhost 访问，避免 DNS 问题
# 这里我们使用一个极小的 alpine 镜像来运行我们的 nodejs 推送脚本
# 因为原作者的镜像可能没有包含我们的推送脚本需要的环境，或者为了解耦
# 我们使用 node:alpine 作为推送服务的镜像，挂载脚本运行
# 尝试预拉取 node 镜像，失败则重试
echo -e "正在准备推送服务镜像..."
if ! docker pull node:20-alpine; then
    echo -e "${YELLOW}从 Docker Hub 拉取 node:20-alpine 失败，尝试使用加速源...${NC}"
    docker pull pull.aitgo.netlib.re/library/node:20-alpine
    docker tag pull.aitgo.netlib.re/library/node:20-alpine node:20-alpine
fi

echo -e "正在启动推送服务..."
docker run -d \
    --name newspush-pusher \
    --network container:newspush-api \
    --restart unless-stopped \
    -v "$INSTALL_DIR/scripts:/app/scripts" \
    -e FEISHU_WEBHOOK_URL="$FEISHU_WEBHOOK" \
    -e SOURCE_URL="http://127.0.0.1:4399" \
    --entrypoint tail \
    node:20-alpine \
    -f /dev/null

if [ $? -ne 0 ]; then
    echo -e "${RED}服务启动失败！请检查 Docker 日志。${NC}"
    exit 1
fi

echo -e "${GREEN}服务已在后台运行！${NC}"

# 5. 设置定时任务
echo -e "${BLUE}[5/5] 设置定时任务...${NC}"

# 创建一个 helper 脚本方便用户手动推送
cat > push_now.sh << EOF
#!/bin/bash
echo "正在触发推送..."
docker exec newspush-pusher node /app/scripts/push.cjs
EOF
chmod +x push_now.sh

# 添加 crontab
# 移除旧的相同任务
crontab -l | grep -v "$INSTALL_DIR/push_now.sh" | crontab -

# 添加新任务
(crontab -l 2>/dev/null; echo "0 $CRON_HOURS * * * $INSTALL_DIR/push_now.sh >> $INSTALL_DIR/push.log 2>&1") | crontab -

echo -e "${GREEN}定时任务已设置：每天 ${CRON_HOURS} 点自动执行${NC}"
echo ""
echo -e "${BLUE}=============================================================${NC}"
echo -e "${GREEN}🎉 恭喜！部署已完成！${NC}"
echo -e "${BLUE}=============================================================${NC}"
echo -e "您可以随时执行以下命令："
echo -e "1. 手动立即推送一次："
echo -e "   ${YELLOW}bash $INSTALL_DIR/push_now.sh${NC}"
echo -e ""
echo -e "2. 查看运行日志："
echo -e "   ${YELLOW}docker logs newspush-api${NC}"
echo -e ""
echo -e "3. 修改配置："
echo -e "   重新运行此安装脚本即可修改配置"
echo -e "${BLUE}=============================================================${NC}"
echo ""

# 询问是否立即测试
read -p "是否现在立即测试推送一次？(y/n): " RUN_NOW
if [[ "$RUN_NOW" =~ ^[Yy]$ ]]; then
    bash push_now.sh
fi
