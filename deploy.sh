#!/bin/bash

# Laravel Blockchain Robot - Docker Deployment Script
# 快速部署脚本

set -e

echo "========================================="
echo "Laravel Blockchain Robot 部署脚本"
echo "========================================="
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查 Docker 是否安装
if ! command -v docker &> /dev/null; then
    echo -e "${RED}错误: Docker 未安装${NC}"
    echo "请先安装 Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

# 检测 Docker Compose 命令（支持 V1 和 V2）
DOCKER_COMPOSE_CMD=""
if docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
    COMPOSE_VERSION=$(docker compose version --short)
    echo -e "${GREEN}✓ 检测到 Docker Compose V2: $COMPOSE_VERSION${NC}"
elif command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
    COMPOSE_VERSION=$(docker-compose version --short)
    echo -e "${GREEN}✓ 检测到 Docker Compose V1: $COMPOSE_VERSION${NC}"
else
    echo -e "${RED}错误: Docker Compose 未安装${NC}"
    echo "请先安装 Docker Compose"
    exit 1
fi

echo -e "${GREEN}✓ Docker 环境检查通过${NC}"
echo ""

# 检查 .env 文件
if [ ! -f .env ]; then
    echo -e "${YELLOW}未找到 .env 文件，从 .env.docker 复制...${NC}"
    cp .env.docker .env
    echo -e "${GREEN}✓ .env 文件已创建${NC}"
    echo -e "${YELLOW}警告: 请编辑 .env 文件，修改数据库密码和应用配置！${NC}"
    echo ""
    read -p "是否现在编辑 .env 文件? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        ${EDITOR:-nano} .env
    fi
else
    echo -e "${GREEN}✓ .env 文件已存在${NC}"
fi

echo ""

# 读取 .env 文件中的配置
if [ -f .env ]; then
    export $(grep -v '^#' .env | grep -E '^(DB_ROOT_PASSWORD|DB_DATABASE)=' | xargs)
    echo -e "${GREEN}✓ 已加载 .env 配置${NC}"
else
    echo -e "${YELLOW}警告: .env 文件不存在，使用默认值${NC}"
fi

echo ""
echo "开始部署..."
echo ""

# 停止现有容器
echo "1. 停止现有容器..."
$DOCKER_COMPOSE_CMD down 2>/dev/null || true
echo -e "${GREEN}✓ 完成${NC}"
echo ""

# 构建镜像（移除 --no-cache 以加快构建速度）
echo "2. 构建 Docker 镜像..."
echo -e "${YELLOW}提示: 如需完全重建，请手动运行: $DOCKER_COMPOSE_CMD build --no-cache${NC}"
$DOCKER_COMPOSE_CMD build
echo -e "${GREEN}✓ 完成${NC}"
echo ""

# 启动容器
echo "3. 启动容器..."
$DOCKER_COMPOSE_CMD up -d
echo -e "${GREEN}✓ 完成${NC}"
echo ""

# 等待 MySQL 就绪
echo "4. 等待 MySQL 启动并初始化..."
echo -e "${YELLOW}提示: 首次部署需要等待 MySQL 初始化数据库，可能需要 30-60 秒${NC}"
sleep 10

# 第一步：等待 MySQL 进程启动
echo "   检查 MySQL 进程..."
MAX_TRIES=30
TRIES=0
until $DOCKER_COMPOSE_CMD exec -T mysql mysqladmin ping -h localhost --silent 2>/dev/null; do
    TRIES=$((TRIES+1))
    if [ $TRIES -ge $MAX_TRIES ]; then
        echo -e "${RED}错误: MySQL 进程启动超时${NC}"
        echo "请检查日志: $DOCKER_COMPOSE_CMD logs mysql"
        exit 1
    fi
    echo "   等待 MySQL 进程启动... ($TRIES/$MAX_TRIES)"
    sleep 2
done
echo -e "${GREEN}   ✓ MySQL 进程已启动${NC}"

# 第二步：等待数据库完全初始化并可以连接
echo "   检查数据库连接..."
sleep 5
TRIES=0
MAX_TRIES=30
until $DOCKER_COMPOSE_CMD exec -T mysql mysql -uroot -p${DB_ROOT_PASSWORD:-root_password} -e "SELECT 1" >/dev/null 2>&1; do
    TRIES=$((TRIES+1))
    if [ $TRIES -ge $MAX_TRIES ]; then
        echo -e "${RED}错误: 无法连接到 MySQL 数据库${NC}"
        echo "请检查日志: $DOCKER_COMPOSE_CMD logs mysql"
        echo "请检查 .env 文件中的 DB_ROOT_PASSWORD 配置"
        exit 1
    fi
    echo "   等待数据库初始化完成... ($TRIES/$MAX_TRIES)"
    sleep 3
done
echo -e "${GREEN}   ✓ 数据库连接成功${NC}"

# 第三步：确认目标数据库已创建
echo "   验证应用数据库..."
DB_NAME=${DB_DATABASE:-robot}
if $DOCKER_COMPOSE_CMD exec -T mysql mysql -uroot -p${DB_ROOT_PASSWORD:-root_password} -e "USE ${DB_NAME}; SELECT 1" >/dev/null 2>&1; then
    echo -e "${GREEN}   ✓ 数据库 ${DB_NAME} 已准备就绪${NC}"
else
    echo -e "${YELLOW}   警告: 数据库 ${DB_NAME} 可能还未完全初始化${NC}"
    echo "   等待额外 10 秒..."
    sleep 10
fi

echo -e "${GREEN}✓ MySQL 完全就绪${NC}"
echo ""

# 安装 Composer 依赖
echo "5. 安装 Composer 依赖..."
$DOCKER_COMPOSE_CMD exec -T app composer install --no-dev --optimize-autoloader --no-interaction
echo -e "${GREEN}✓ 完成${NC}"
echo ""

# 生成应用密钥
echo "6. 生成应用密钥..."
$DOCKER_COMPOSE_CMD exec -T app php artisan key:generate --force
echo -e "${GREEN}✓ 完成${NC}"
echo ""

# 运行数据库迁移
echo "7. 运行数据库迁移..."
$DOCKER_COMPOSE_CMD exec -T app php artisan migrate --force
echo -e "${GREEN}✓ 完成${NC}"
echo ""

# 创建存储链接
echo "8. 创建存储链接..."
$DOCKER_COMPOSE_CMD exec -T app php artisan storage:link || echo -e "${YELLOW}警告: 存储链接可能已存在${NC}"
echo -e "${GREEN}✓ 完成${NC}"
echo ""

# 设置权限
echo "9. 设置目录权限..."
$DOCKER_COMPOSE_CMD exec -T app chown -R www-data:www-data /var/www/html/storage
$DOCKER_COMPOSE_CMD exec -T app chown -R www-data:www-data /var/www/html/bootstrap/cache
$DOCKER_COMPOSE_CMD exec -T app chmod -R 775 /var/www/html/storage
$DOCKER_COMPOSE_CMD exec -T app chmod -R 775 /var/www/html/bootstrap/cache
echo -e "${GREEN}✓ 完成${NC}"
echo ""

# 清除和缓存配置
echo "10. 优化应用..."
$DOCKER_COMPOSE_CMD exec -T app php artisan config:cache
$DOCKER_COMPOSE_CMD exec -T app php artisan route:cache
$DOCKER_COMPOSE_CMD exec -T app php artisan view:cache
echo -e "${GREEN}✓ 完成${NC}"
echo ""

# 显示容器状态
echo "========================================="
echo "部署完成！"
echo "========================================="
echo ""
$DOCKER_COMPOSE_CMD ps
echo ""

# 获取服务器 IP
SERVER_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")

echo "========================================="
echo "访问信息："
echo "========================================="
echo -e "应用主页:       ${GREEN}http://${SERVER_IP}${NC}"
echo -e "phpMyAdmin:     ${GREEN}http://${SERVER_IP}:8081${NC}"
echo ""
echo "phpMyAdmin 登录信息："
echo "  服务器: mysql"
echo "  用户名: root"
echo "  密码: 请查看 .env 文件中的 DB_ROOT_PASSWORD"
echo ""
echo "========================================="
echo "常用命令："
echo "========================================="
echo "查看日志:       $DOCKER_COMPOSE_CMD logs -f app"
echo "查看容器状态:   $DOCKER_COMPOSE_CMD ps"
echo "停止服务:       $DOCKER_COMPOSE_CMD down"
echo "重启服务:       $DOCKER_COMPOSE_CMD restart"
echo "进入容器:       $DOCKER_COMPOSE_CMD exec app bash"
echo ""
echo "区块链命令:"
echo "执行任务:       $DOCKER_COMPOSE_CMD exec app php artisan blockchain:task"
echo "RPC 心跳:       $DOCKER_COMPOSE_CMD exec app php artisan blockchain:rpc-heartbeat"
echo ""
echo -e "${YELLOW}注意事项：${NC}"
echo "1. 生产环境建议关闭 MySQL(3306)、Redis(6379) 和 phpMyAdmin(8081) 的端口映射"
echo "2. 请修改 .env 中的默认密码"
echo "3. 建议配置 SSL 证书并启用 HTTPS"
echo ""
echo -e "${GREEN}部署成功！${NC}"
