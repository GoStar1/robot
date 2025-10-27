# Dockerfile for Laravel Blockchain Robot Application
FROM php:8.2-fpm

# Set working directory
WORKDIR /var/www/html

# Configure apt to be more resilient to network issues
RUN echo 'Acquire::Retries "3";' > /etc/apt/apt.conf.d/80-retries && \
    echo 'Acquire::http::Timeout "120";' >> /etc/apt/apt.conf.d/80-retries && \
    echo 'Acquire::ftp::Timeout "120";' >> /etc/apt/apt.conf.d/80-retries

# Install system dependencies with retry mechanism
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get update --fix-missing && \
    apt-get install -y --no-install-recommends --fix-missing \
    git \
    curl \
    libpng-dev \
    libonig-dev \
    libxml2-dev \
    libzip-dev \
    zip \
    unzip \
    libgmp-dev \
    && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
RUN docker-php-ext-install \
    pdo_mysql \
    mbstring \
    exif \
    pcntl \
    bcmath \
    gd \
    zip \
    gmp

# Install Redis and msgpack extensions with retry mechanism
RUN pecl channel-update pecl.php.net || true \
    && (pecl install msgpack || pecl install msgpack-stable) \
    && docker-php-ext-enable msgpack \
    && (pecl install redis || pecl install redis-5.3.7 || pecl install redis-stable) \
    && docker-php-ext-enable redis

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Copy existing application directory
COPY . /var/www/html

# Create necessary Laravel directories if they don't exist
RUN mkdir -p /var/www/html/storage/framework/cache \
    && mkdir -p /var/www/html/storage/framework/sessions \
    && mkdir -p /var/www/html/storage/framework/views \
    && mkdir -p /var/www/html/storage/logs \
    && mkdir -p /var/www/html/storage/app/public \
    && mkdir -p /var/www/html/bootstrap/cache

# Set permissions
RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 775 /var/www/html/storage \
    && chmod -R 775 /var/www/html/bootstrap/cache

# Install application dependencies
RUN composer install --no-dev --optimize-autoloader --no-interaction

# Expose port 9000 and start php-fpm server
EXPOSE 9000
CMD ["php-fpm"]
