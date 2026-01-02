#!/bin/bash

#==============================================================================
# R-Panel Installation Script
# Author: Generated for Mochammad Rizki Romdoni
# Description: Complete installation script for R-Panel hosting control panel
#==============================================================================

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Script ini harus dijalankan sebagai root"
        exit 1
    fi
}

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        log_info "Detected OS: $PRETTY_NAME"
    else
        log_error "Cannot detect OS"
        exit 1
    fi

    # Check if OS is supported
    if [[ "$OS" != "ubuntu" ]] && [[ "$OS" != "debian" ]]; then
        log_error "OS tidak didukung. Hanya Ubuntu dan Debian yang didukung."
        exit 1
    fi
}

# Update system
update_system() {
    log_info "Updating system packages..."
    apt-get update -y
    apt-get upgrade -y
    log_success "System updated successfully"
}

# Install basic utilities
install_utilities() {
    log_info "Installing basic utilities..."
    apt-get install -y \
        software-properties-common \
        curl \
        wget \
        git \
        unzip \
        zip \
        htop \
        nano \
        vim \
        net-tools \
        ufw \
        fail2ban \
        certbot \
        openssl \
        ca-certificates \
        gnupg \
        lsb-release
    log_success "Basic utilities installed"
}

# Install Nginx
install_nginx() {
    log_info "Installing Nginx..."
    
    apt-get install -y nginx
    
    # Enable and start Nginx
    systemctl enable nginx
    systemctl start nginx
    
    # Create default directories
    mkdir -p /var/www/html
    mkdir -p /etc/nginx/sites-available
    mkdir -p /etc/nginx/sites-enabled
    mkdir -p /etc/nginx/conf.d
    
    log_success "Nginx installed successfully"
}

# Install PHP and PHP-FPM
install_php() {
    log_info "Installing PHP and PHP-FPM..."
    
    # Add PHP repository for latest version
    if [[ "$OS" == "ubuntu" ]]; then
        add-apt-repository -y ppa:ondrej/php
        apt-get update -y
    fi
    
    # Install PHP 8.2 (you can change version as needed)
    PHP_VERSION="8.2"
    
    apt-get install -y \
        php${PHP_VERSION} \
        php${PHP_VERSION}-fpm \
        php${PHP_VERSION}-cli \
        php${PHP_VERSION}-common \
        php${PHP_VERSION}-mysql \
        php${PHP_VERSION}-zip \
        php${PHP_VERSION}-gd \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-xml \
        php${PHP_VERSION}-bcmath \
        php${PHP_VERSION}-json \
        php${PHP_VERSION}-intl \
        php${PHP_VERSION}-soap \
        php${PHP_VERSION}-imap \
        php${PHP_VERSION}-opcache \
        php${PHP_VERSION}-readline
    
    # Enable and start PHP-FPM
    systemctl enable php${PHP_VERSION}-fpm
    systemctl start php${PHP_VERSION}-fpm
    
    log_success "PHP ${PHP_VERSION} installed successfully"
}

# Install MariaDB
install_mariadb() {
    log_info "Installing MariaDB..."
    
    apt-get install -y mariadb-server mariadb-client
    
    # Enable and start MariaDB
    systemctl enable mariadb
    systemctl start mariadb
    
    log_success "MariaDB installed successfully"
    log_warning "Jangan lupa jalankan: mysql_secure_installation"
}

# Install Redis (optional but recommended for caching)
install_redis() {
    log_info "Installing Redis..."
    
    apt-get install -y redis-server
    
    # Enable and start Redis
    systemctl enable redis-server
    systemctl start redis-server
    
    log_success "Redis installed successfully"
}

# Install Node.js and npm (for frontend assets)
install_nodejs() {
    log_info "Installing Node.js and npm..."
    
    # Install NodeSource repository for latest LTS
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
    apt-get install -y nodejs
    
    # Install Yarn
    npm install -g yarn
    
    log_success "Node.js $(node -v) and npm $(npm -v) installed successfully"
}

# Install Composer (PHP package manager)
install_composer() {
    log_info "Installing Composer..."
    
    EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

    if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
        log_error "Invalid Composer installer checksum"
        rm composer-setup.php
        exit 1
    fi

    php composer-setup.php --quiet --install-dir=/usr/local/bin --filename=composer
    rm composer-setup.php
    
    log_success "Composer installed successfully"
}

# Configure firewall
configure_firewall() {
    log_info "Configuring UFW firewall..."
    
    # Allow SSH, HTTP, HTTPS
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 3306/tcp  # MySQL (optional, for remote access)
    
    # Enable firewall
    echo "y" | ufw enable
    
    log_success "Firewall configured successfully"
}

# Configure Fail2Ban
configure_fail2ban() {
    log_info "Configuring Fail2Ban..."
    
    # Create local jail configuration
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port = 22
logpath = /var/log/auth.log

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/error.log

[nginx-noscript]
enabled = true
port = http,https
logpath = /var/log/nginx/access.log
EOF

    systemctl enable fail2ban
    systemctl restart fail2ban
    
    log_success "Fail2Ban configured successfully"
}

# Create R-Panel directory structure
create_rpanel_structure() {
    log_info "Creating R-Panel directory structure..."
    
    # Main directories
    mkdir -p /opt/r-panel
    mkdir -p /opt/r-panel/bin
    mkdir -p /opt/r-panel/config
    mkdir -p /opt/r-panel/logs
    mkdir -p /opt/r-panel/temp
    mkdir -p /opt/r-panel/backups
    
    # Web directories
    mkdir -p /var/www/r-panel
    mkdir -p /var/www/r-panel/public
    mkdir -p /var/www/r-panel/storage
    
    # User websites directory
    mkdir -p /var/www/vhosts
    
    # Set permissions
    chown -R www-data:www-data /var/www
    chmod -R 755 /var/www
    
    log_success "R-Panel directory structure created"
}

# Create basic Nginx configuration for R-Panel
create_nginx_config() {
    log_info "Creating Nginx configuration for R-Panel..."
    
    cat > /etc/nginx/sites-available/r-panel.conf <<'EOF'
server {
    listen 80;
    server_name _;
    
    root /var/www/r-panel/public;
    index index.php index.html index.htm;
    
    access_log /opt/r-panel/logs/access.log;
    error_log /opt/r-panel/logs/error.log;
    
    client_max_body_size 100M;
    
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }
    
    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
    
    location ~ /\.ht {
        deny all;
    }
}
EOF

    # Enable the site
    ln -sf /etc/nginx/sites-available/r-panel.conf /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Test and reload Nginx
    nginx -t && systemctl reload nginx
    
    log_success "Nginx configuration created"
}

# Optimize PHP-FPM configuration
optimize_php_fpm() {
    log_info "Optimizing PHP-FPM configuration..."
    
    PHP_VERSION="8.2"
    PHP_FPM_CONF="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"
    
    # Backup original config
    cp $PHP_FPM_CONF ${PHP_FPM_CONF}.backup
    
    # Update PHP-FPM pool settings
    sed -i 's/pm = dynamic/pm = ondemand/' $PHP_FPM_CONF
    sed -i 's/pm.max_children = .*/pm.max_children = 50/' $PHP_FPM_CONF
    sed -i 's/pm.start_servers = .*/pm.start_servers = 5/' $PHP_FPM_CONF
    sed -i 's/pm.min_spare_servers = .*/pm.min_spare_servers = 5/' $PHP_FPM_CONF
    sed -i 's/pm.max_spare_servers = .*/pm.max_spare_servers = 10/' $PHP_FPM_CONF
    
    # Restart PHP-FPM
    systemctl restart php${PHP_VERSION}-fpm
    
    log_success "PHP-FPM optimized"
}

# Create swap if not exists (untuk mencegah memory issues seperti yang pernah dialami)
create_swap() {
    log_info "Checking swap memory..."
    
    if [ $(swapon --show | wc -l) -eq 0 ]; then
        log_warning "No swap detected. Creating 2GB swap file..."
        
        fallocate -l 2G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        
        # Make it permanent
        echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
        
        log_success "Swap file created successfully"
    else
        log_info "Swap already exists"
    fi
}

# Display system information
display_info() {
    echo ""
    echo "=============================================="
    echo "  R-Panel Installation Summary"
    echo "=============================================="
    echo ""
    echo "Installed Components:"
    echo "  ✓ Nginx: $(nginx -v 2>&1 | cut -d'/' -f2)"
    echo "  ✓ PHP: $(php -v | head -n 1 | cut -d' ' -f2)"
    echo "  ✓ MariaDB: $(mysql --version | cut -d' ' -f6 | cut -d'-' -f1)"
    echo "  ✓ Redis: $(redis-server --version | cut -d'=' -f2 | cut -d' ' -f1)"
    echo "  ✓ Node.js: $(node -v)"
    echo "  ✓ Composer: $(composer --version | cut -d' ' -f3)"
    echo ""
    echo "Directories Created:"
    echo "  • /opt/r-panel (panel files)"
    echo "  • /var/www/r-panel (web files)"
    echo "  • /var/www/vhosts (user websites)"
    echo ""
    echo "Next Steps:"
    echo "  1. Run: mysql_secure_installation"
    echo "  2. Upload R-Panel source code to /var/www/r-panel"
    echo "  3. Configure database in /opt/r-panel/config"
    echo "  4. Set up SSL certificate with certbot"
    echo ""
    echo "Useful Commands:"
    echo "  • Check services: systemctl status nginx php8.2-fpm mariadb"
    echo "  • View logs: tail -f /opt/r-panel/logs/*.log"
    echo "  • Nginx test: nginx -t"
    echo ""
    echo "=============================================="
    echo ""
}

# Main installation flow
main() {
    clear
    echo "=============================================="
    echo "  R-Panel Installation Script"
    echo "  Installing all required components..."
    echo "=============================================="
    echo ""
    
    check_root
    detect_os
    
    # Installation steps
    update_system
    install_utilities
    install_nginx
    install_php
    install_mariadb
    install_redis
    install_nodejs
    install_composer
    
    # Configuration steps
    configure_firewall
    configure_fail2ban
    create_rpanel_structure
    create_nginx_config
    optimize_php_fpm
    create_swap
    
    # Display summary
    display_info
    
    log_success "Installation completed successfully!"
    echo ""
    log_warning "PENTING: Reboot server untuk memastikan semua konfigurasi aktif"
    echo ""
}

# Run main installation
main
