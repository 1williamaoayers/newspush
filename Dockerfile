# 使用 Debian slim 镜像代替 Alpine，解决 ARMv7 架构下的构建兼容性问题
FROM node:20-slim AS builder

# 设置工作目录
WORKDIR /app

# 设置 node 环境变量为 production，确保不安装 devDependencies (特别是 wrangler/workerd，它不支持 ARMv7)
ENV NODE_ENV=production

# 复制项目依赖文件，包括 .npmrc
COPY package.json pnpm-lock.yaml* .npmrc ./

# 安装构建工具 (Debian 方式)
RUN apt-get update && apt-get install -y python3 make g++ && rm -rf /var/lib/apt/lists/*

# 安装生产依赖
# tsx 已在 dependencies 中,会自动安装
# 使用 --omit=dev 跳过 devDependencies (避免安装 workerd 等不支持 ARM32 的包)
RUN npm install --omit=dev

# 复制项目代码
COPY . .

# 运行阶段
FROM node:20-slim AS runner

# 维护信息
LABEL maintainer="Viki <hi@viki.moe> (https://github.com/vikiboss)"
LABEL description="⏰ 60s API，每天 60 秒读懂世界｜一系列 高质量、开源、可靠 的开放 API 集合"

# 设置工作目录
WORKDIR /app

# 设置环境变量 (保持 production)
ENV NODE_ENV=production TZ=Asia/Shanghai

# 安装 tzdata (Debian 方式)
RUN apt-get update && apt-get install -y tzdata && rm -rf /var/lib/apt/lists/* && \
    groupadd -r nodejs && useradd -r -g nodejs nodejs

# 从构建阶段复制整个 app 目录
COPY --from=builder /app .

# 切换到非 root 用户
USER nodejs

# 指定暴露端口
EXPOSE 4399

# 运行应用
CMD ["npm", "run", "start"]
