#!/bin/bash

##############################################################################
# 生产环境部署脚本
# 用途：在生产服务器上部署和启动 Docker 容器
##############################################################################

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}开始部署生产环境${NC}"
echo -e "${GREEN}========================================${NC}"

# 1. 检查 .env 文件
echo -e "\n${YELLOW}[1/8] 检查环境配置...${NC}"
if [ ! -f .env ]; then
    echo -e "${RED}错误：.env 文件不存在！${NC}"
    echo -e "${YELLOW}请先复制 .env.production.example 并配置：${NC}"
    echo -e "  cp .env.production.example .env"
    echo -e "  nano .env"
    exit 1
fi

# 检查必要的环境变量
if grep -q "YOUR_STRONG.*PASSWORD_HERE" .env; then
    echo -e "${RED}错误：请先修改 .env 中的密码！${NC}"
    exit 1
fi

if grep -q "APP_URL=http://localhost" .env || grep -q "APP_URL=https://localhost" .env; then
    echo -e "${YELLOW}警告：APP_URL 还是 localhost，请修改为实际域名！${NC}"
    read -p "是否继续？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo -e "${GREEN}✓ 环境配置检查通过${NC}"

# 2. 停止现有容器
echo -e "\n${YELLOW}[2/8] 停止现有容器...${NC}"
docker-compose -f docker-compose.prod.yml down || true
echo -e "${GREEN}✓ 容器已停止${NC}"

# 3. 拉取最新代码（如果使用 Git）
echo -e "\n${YELLOW}[3/8] 检查代码更新...${NC}"
if [ -d .git ]; then
    echo "拉取最新代码..."
    git pull || echo "Git pull 失败，跳过..."
else
    echo "非 Git 仓库，跳过代码更新"
fi

# 4. 安装/更新依赖
echo -e "\n${YELLOW}[4/8] 更新 Composer 依赖...${NC}"
if command -v composer &> /dev/null; then
    composer install --no-dev --optimize-autoloader --no-interaction
    echo -e "${GREEN}✓ 依赖更新完成${NC}"
else
    echo -e "${YELLOW}本地未安装 Composer，将在容器中安装依赖${NC}"
fi

# 5. 构建并启动容器
echo -e "\n${YELLOW}[5/8] 构建并启动 Docker 容器...${NC}"
docker-compose -f docker-compose.prod.yml up -d --build
echo -e "${GREEN}✓ 容器启动成功${NC}"

# 6. 等待服务就绪
echo -e "\n${YELLOW}[6/8] 等待服务启动...${NC}"
sleep 10
echo -e "${GREEN}✓ 服务已启动${NC}"

# 7. 执行数据库迁移
echo -e "\n${YELLOW}[7/8] 执行数据库迁移...${NC}"
read -p "是否需要运行数据库迁移？(y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker exec robot_app php artisan migrate --force
    echo -e "${GREEN}✓ 数据库迁移完成${NC}"
else
    echo "跳过数据库迁移"
fi

# 8. 优化应用
echo -e "\n${YELLOW}[8/8] 优化应用...${NC}"
docker exec robot_app php artisan config:cache
docker exec robot_app php artisan route:cache
docker exec robot_app php artisan view:cache
echo -e "${GREEN}✓ 应用优化完成${NC}"

# 显示运行状态
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}部署完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n当前运行的容器："
docker-compose -f docker-compose.prod.yml ps

echo -e "\n${YELLOW}重要提醒：${NC}"
echo -e "1. 请确保防火墙已配置，只开放 80 和 443 端口"
echo -e "2. 如果配置了 SSL，请确保证书文件正确挂载"
echo -e "3. 定期备份数据库数据卷"
echo -e "4. 查看日志：docker-compose -f docker-compose.prod.yml logs -f"

echo -e "\n${GREEN}部署脚本执行完毕！${NC}"
