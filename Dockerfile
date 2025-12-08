# 使用更小的基础镜像和多阶段构建来减少最终镜像的大小
FROM node:20-alpine AS builder

# 设置工作目录，避免之后的 RUN 命令中需要不断地 mkdir 和 cd
WORKDIR /app

# 设置 node 环境变量为生产环境，不会安装 devDependencies
ENV NODE_ENV=production

# 复制项目依赖文件，这里优化了复制步骤，可以利用 Docker 缓存
COPY package.json pnpm-lock.yaml* ./

# 适配 ARM32 (玩客云等): 安装构建工具以支持可能需要的本地编译
RUN apk add --no-cache python3 make g++

# 启用 corepack 并预先下载 pnpm 包管理器，减少运行时下载延迟
# 安装项目依赖，移除 --frozen-lockfile 以允许在 lockfile 不匹配时自动更新 (因为我们刚修改了 package.json)
RUN corepack enable && corepack prepare --activate && pnpm install

# 复制项目代码到工作目录
COPY . .

# 运行阶段
FROM node:20-alpine AS runner

# 维护信息
LABEL maintainer="Viki <hi@viki.moe> (https://github.com/vikiboss)"
LABEL description="⏰ 60s API，每天 60 秒读懂世界｜一系列 高质量、开源、可靠 的开放 API 集合"

# 设置工作目录
WORKDIR /app

# 设置 node 环境变量为生产环境，更高效地运行应用，设置时区为上海
ENV NODE_ENV=production TZ=Asia/Shanghai

# 安装 tzdata 以支持时区设置，创建非 root 用户
RUN apk add --no-cache tzdata && \
    addgroup -S nodejs && adduser -S nodejs -G nodejs

# 从构建阶段复制整个 app 目录
COPY --from=builder /app .

# 切换到非 root 用户
USER nodejs

# 指定暴露端口
EXPOSE 4399

# 设置健康检查指令，使用 curl 检查应用是否正常运行
# HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
#   CMD curl --silent --fail http://127.0.0.1:4399/health -H 'User-Agent: Docker Health Check' || exit 1

# 运行应用
CMD ["pnpm", "run", "start"]
