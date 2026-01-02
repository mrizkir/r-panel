#!/bin/bash

#==============================================================================
# R-Panel Installation Script
# Description: Complete installation script for R-Panel hosting control panel
# For international users
#
# Usage:
#   ./install.sh           # Quiet mode with progress bar (default)
#   ./install.sh --verbose # Show all installation output
#   ./install.sh --quiet   # Same as default, quiet with progress
#==============================================================================

# Auto re-execute with bash if not running with bash
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

set -e  # Exit on error

# Error handler
error_exit() {
    local line_no=$1
    echo ""
    log_error "Installation failed at line $line_no"
    log_error "Check log file for details: $LOG_FILE"
    log_error "Last 20 lines of log:"
    tail -20 "$LOG_FILE" 2>/dev/null || echo "Log file not found"
    exit 1
}

# Set error trap
trap 'error_exit $LINENO' ERR

# Set non-interactive mode to prevent dialog prompts
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1
export COMPOSER_ALLOW_SUPERUSER=1

# Parse arguments
VERBOSE_MODE=false
for arg in "$@"; do
    case $arg in
        --verbose|-v)
            VERBOSE_MODE=true
            shift
            ;;
        --quiet|-q)
            VERBOSE_MODE=false
            shift
            ;;
    esac
done

# Installation log file
LOG_FILE="/tmp/r-panel-install-$(date +%Y%m%d_%H%M%S).log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Progress tracking
TOTAL_STEPS=15
CURRENT_STEP=0

# Progress bar function
show_progress() {
    if [ "$VERBOSE_MODE" = true ]; then
        return
    fi
    
    local percent=$((CURRENT_STEP * 100 / TOTAL_STEPS))
    local filled=$((CURRENT_STEP * 50 / TOTAL_STEPS))
    local empty=$((50 - filled))
    
    # Build progress bar
    local bar="["
    for ((i=0; i<filled; i++)); do bar+="="; done
    if [ $filled -lt 50 ]; then bar+=">"; fi
    for ((i=0; i<empty-1; i++)); do bar+=" "; done
    bar+="]"
    
    # Print progress bar with carriage return
    printf "\r${CYAN}Progress:${NC} %s ${GREEN}%3d%%${NC} - %s" "$bar" "$percent" "$1"
    
    # Flush output
    if command -v sync &> /dev/null; then
        sync
    fi
    
    if [ "$CURRENT_STEP" -eq "$TOTAL_STEPS" ]; then
        echo ""
    fi
}

# Execute command based on verbose mode
execute() {
    local description="$1"
    shift
    
    ((CURRENT_STEP++))
    show_progress "$description"
    
    if [ "$VERBOSE_MODE" = true ]; then
        echo ""
        log_info "$description"
        if ! "$@" 2>&1 | tee -a "$LOG_FILE"; then
            log_error "Failed: $description"
            return 1
        fi
    else
        if ! "$@" >> "$LOG_FILE" 2>&1; then
            echo ""
            log_error "Failed: $description"
            log_error "Check log: $LOG_FILE"
            return 1
        fi
    fi
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
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
    if [ "$OS" != "ubuntu" ] && [ "$OS" != "debian" ]; then
        log_error "Unsupported OS. Only Ubuntu and Debian are supported."
        exit 1
    fi
}

# Disable interactive prompts
disable_prompts() {
    if [ "$VERBOSE_MODE" = false ]; then
        echo "Configuring non-interactive mode..." >> "$LOG_FILE"
    elif [ "$VERBOSE_MODE" = true ]; then
        log_info "Configuring non-interactive mode..."
    fi
    
    # Configure needrestart to automatically restart services
    if [ -f /etc/needrestart/needrestart.conf ]; then
        sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf 2>> "$LOG_FILE"
    fi
    
    # Create needrestart config if not exists
    mkdir -p /etc/needrestart >> "$LOG_FILE" 2>&1
    cat > /etc/needrestart/conf.d/no-prompt.conf <<'EOF'
# Restart services automatically without asking
$nrconf{restart} = 'a';
EOF
    
    # Configure debconf for non-interactive mode
    echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections >> "$LOG_FILE" 2>&1
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_success "Non-interactive mode configured"
    else
        echo "Non-interactive mode configured" >> "$LOG_FILE"
    fi
}

# Update system
update_system() {
    # Configure apt to not ask questions
    echo 'libc6 libraries/restart-without-asking boolean true' | debconf-set-selections >> "$LOG_FILE" 2>&1
    
    execute "Updating system packages" apt-get update -y
    execute "Upgrading system packages" apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    execute "Upgrading distribution packages" apt-get dist-upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_success "System updated successfully"
    fi
}

# Install basic utilities
install_utilities() {
    execute "Installing basic utilities" apt-get install -y \
        debconf-utils \
        apt-transport-https \
        software-properties-common \
        curl \
        wget \
        git \
        unzip \
        zip \
        rsync \
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
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_success "Basic utilities installed"
    fi
}

# Install Nginx
install_nginx() {
    execute "Installing Nginx" apt-get install -y nginx
    
    # Enable and start Nginx
    systemctl enable nginx >> "$LOG_FILE" 2>&1
    systemctl start nginx >> "$LOG_FILE" 2>&1
    
    # Create default directories
    mkdir -p /var/www/html >> "$LOG_FILE" 2>&1
    mkdir -p /etc/nginx/sites-available >> "$LOG_FILE" 2>&1
    mkdir -p /etc/nginx/sites-enabled >> "$LOG_FILE" 2>&1
    mkdir -p /etc/nginx/conf.d >> "$LOG_FILE" 2>&1
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_success "Nginx installed successfully"
    fi
}

# Install PHP and PHP-FPM
install_php() {
    # PHP version to install
    PHP_VERSION="8.2"
    
    # Add PHP repository based on OS
    if [ "$OS" = "ubuntu" ]; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Adding Ondrej PHP repository for Ubuntu..."
        fi
        add-apt-repository -y ppa:ondrej/php >> "$LOG_FILE" 2>&1
        apt-get update -y >> "$LOG_FILE" 2>&1
    elif [ "$OS" = "debian" ]; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Adding Sury PHP repository for Debian..."
        fi
        
        # Add Sury repository key
        curl -fsSL https://packages.sury.org/php/apt.gpg -o /etc/apt/trusted.gpg.d/php.gpg 2>> "$LOG_FILE"
        
        # Add repository
        echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
        
        apt-get update -y >> "$LOG_FILE" 2>&1
    fi
    
    # Install PHP packages
    execute "Installing PHP ${PHP_VERSION} and extensions" apt-get install -y \
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
        php${PHP_VERSION}-intl \
        php${PHP_VERSION}-soap \
        php${PHP_VERSION}-imap \
        php${PHP_VERSION}-opcache \
        php${PHP_VERSION}-readline
    
    # Enable and start PHP-FPM
    systemctl enable php${PHP_VERSION}-fpm >> "$LOG_FILE" 2>&1
    systemctl start php${PHP_VERSION}-fpm >> "$LOG_FILE" 2>&1
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_success "PHP ${PHP_VERSION} installed successfully"
    fi
}

# Install MariaDB
install_mariadb() {
    execute "Installing MariaDB" apt-get install -y mariadb-server mariadb-client
    
    # Enable and start MariaDB
    systemctl enable mariadb >> "$LOG_FILE" 2>&1
    systemctl start mariadb >> "$LOG_FILE" 2>&1
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_success "MariaDB installed successfully"
        log_warning "Don't forget to run: mysql_secure_installation"
    fi
}

# Install Redis (optional but recommended for caching)
install_redis() {
    execute "Installing Redis" apt-get install -y redis-server
    
    # Enable and start Redis
    systemctl enable redis-server >> "$LOG_FILE" 2>&1
    systemctl start redis-server >> "$LOG_FILE" 2>&1
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_success "Redis installed successfully"
    fi
}

# Install Node.js and npm (for frontend assets)
install_nodejs() {
    # Install NodeSource repository for latest LTS
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Adding NodeSource repository..."
    fi
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - >> "$LOG_FILE" 2>&1
    
    execute "Installing Node.js and npm" apt-get install -y nodejs
    
    # Install Yarn
    npm install -g yarn >> "$LOG_FILE" 2>&1
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_success "Node.js $(node -v) and npm $(npm -v) installed successfully"
    fi
}

# Install Go
install_go() {
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Installing Go..."
    fi
    
    # Go version to install
    GO_VERSION="1.25.5"
    
    # Download and install Go
    cd /tmp
    wget -q https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz >> "$LOG_FILE" 2>&1
    
    # Remove old Go installation if exists
    rm -rf /usr/local/go >> "$LOG_FILE" 2>&1
    
    # Extract new Go
    tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz >> "$LOG_FILE" 2>&1
    
    # Add Go to PATH
    if ! grep -q "/usr/local/go/bin" /etc/profile; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    fi
    
    # Set for current session
    export PATH=$PATH:/usr/local/go/bin
    
    # Cleanup
    rm -f go${GO_VERSION}.linux-amd64.tar.gz >> "$LOG_FILE" 2>&1
    
    cd - >> "$LOG_FILE" 2>&1
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_success "Go $(/usr/local/go/bin/go version | cut -d' ' -f3) installed successfully"
    fi
}

# Install Composer (PHP package manager)
install_composer() {
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Installing Composer..."
    fi
    
    EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");' 2>/dev/null)"
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" >> "$LOG_FILE" 2>&1
    ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');" 2>/dev/null)"

    if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
        log_error "Invalid Composer installer checksum"
        rm -f composer-setup.php
        exit 1
    fi

    # Install Composer - auto-answer "yes" to root warning
    echo "yes" | php composer-setup.php --quiet --install-dir=/usr/local/bin --filename=composer >> "$LOG_FILE" 2>&1
    
    rm -f composer-setup.php >> "$LOG_FILE" 2>&1
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_success "Composer installed successfully"
    fi
}

# Configure firewall
configure_firewall() {
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Configuring UFW firewall..."
    fi
    
    # Allow SSH, HTTP, HTTPS
    ufw allow 22/tcp >> "$LOG_FILE" 2>&1
    ufw allow 80/tcp >> "$LOG_FILE" 2>&1
    ufw allow 443/tcp >> "$LOG_FILE" 2>&1
    ufw allow 8080/tcp >> "$LOG_FILE" 2>&1  # R-Panel port
    ufw allow 3306/tcp >> "$LOG_FILE" 2>&1  # MySQL (optional, for remote access)
    
    # Enable firewall
    echo "y" | ufw enable >> "$LOG_FILE" 2>&1
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_success "Firewall configured successfully"
    fi
}

# Configure Fail2Ban
configure_fail2ban() {
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Configuring Fail2Ban..."
    fi
    
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

    systemctl enable fail2ban >> "$LOG_FILE" 2>&1
    systemctl restart fail2ban >> "$LOG_FILE" 2>&1
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_success "Fail2Ban configured successfully"
    fi
}

# Create R-Panel directory structure
create_rpanel_structure() {
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Creating R-Panel directory structure..."
    fi
    
    # Main directories
    mkdir -p /opt/r-panel >> "$LOG_FILE" 2>&1
    mkdir -p /opt/r-panel/bin >> "$LOG_FILE" 2>&1
    mkdir -p /opt/r-panel/config >> "$LOG_FILE" 2>&1
    mkdir -p /opt/r-panel/logs >> "$LOG_FILE" 2>&1
    mkdir -p /opt/r-panel/temp >> "$LOG_FILE" 2>&1
    mkdir -p /opt/r-panel/backups >> "$LOG_FILE" 2>&1
    
    # Web directories
    mkdir -p /var/www/r-panel >> "$LOG_FILE" 2>&1
    mkdir -p /var/www/r-panel/public >> "$LOG_FILE" 2>&1
    mkdir -p /var/www/r-panel/storage >> "$LOG_FILE" 2>&1
    
    # User websites directory
    mkdir -p /var/www/vhosts >> "$LOG_FILE" 2>&1
    
    # Set permissions
    chown -R www-data:www-data /var/www >> "$LOG_FILE" 2>&1
    chmod -R 755 /var/www >> "$LOG_FILE" 2>&1
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_success "R-Panel directory structure created"
    fi
}

# Create basic Nginx configuration for R-Panel
create_nginx_config() {
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Creating Nginx configuration..."
    fi
    
    # Create a basic default configuration for user websites
    cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    root /var/www/html;
    index index.html index.htm index.php;
    
    server_name _;
    
    location / {
        try_files $uri $uri/ =404;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
    }
    
    location ~ /\.ht {
        deny all;
    }
}
EOF

    # Enable the default site
    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default >> "$LOG_FILE" 2>&1
    
    # Test and reload Nginx
    nginx -t >> "$LOG_FILE" 2>&1 && systemctl reload nginx >> "$LOG_FILE" 2>&1
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_success "Nginx configuration created"
    fi
}

# Optimize PHP-FPM configuration
optimize_php_fpm() {
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Optimizing PHP-FPM configuration..."
    fi
    
    PHP_VERSION="8.2"
    PHP_FPM_CONF="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"
    
    # Backup original config
    cp $PHP_FPM_CONF ${PHP_FPM_CONF}.backup >> "$LOG_FILE" 2>&1
    
    # Update PHP-FPM pool settings
    sed -i 's/pm = dynamic/pm = ondemand/' $PHP_FPM_CONF 2>> "$LOG_FILE"
    sed -i 's/pm.max_children = .*/pm.max_children = 50/' $PHP_FPM_CONF 2>> "$LOG_FILE"
    sed -i 's/pm.start_servers = .*/pm.start_servers = 5/' $PHP_FPM_CONF 2>> "$LOG_FILE"
    sed -i 's/pm.min_spare_servers = .*/pm.min_spare_servers = 5/' $PHP_FPM_CONF 2>> "$LOG_FILE"
    sed -i 's/pm.max_spare_servers = .*/pm.max_spare_servers = 10/' $PHP_FPM_CONF 2>> "$LOG_FILE"
    
    # Restart PHP-FPM
    systemctl restart php${PHP_VERSION}-fpm >> "$LOG_FILE" 2>&1
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_success "PHP-FPM optimized"
    fi
}

# Create swap if not exists (to prevent memory issues)
create_swap() {
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Checking swap memory..."
    fi
    
    if [ "$(swapon --show | wc -l)" -eq 0 ]; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_warning "No swap detected. Creating 2GB swap file..."
        fi
        
        fallocate -l 2G /swapfile >> "$LOG_FILE" 2>&1
        chmod 600 /swapfile >> "$LOG_FILE" 2>&1
        mkswap /swapfile >> "$LOG_FILE" 2>&1
        swapon /swapfile >> "$LOG_FILE" 2>&1
        
        # Make it permanent
        echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab >> "$LOG_FILE" 2>&1
        
        if [ "$VERBOSE_MODE" = true ]; then
            log_success "Swap file created successfully"
        fi
    else
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Swap already exists"
        fi
    fi
}

# Detect R-Panel source code location
detect_rpanel_source() {
    local SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Check if we're inside r-panel repository (Go project)
    if [ -f "$SCRIPT_DIR/go.mod" ] || [ -f "$SCRIPT_DIR/main.go" ] || [ -d "$SCRIPT_DIR/.git" ]; then
        echo "$SCRIPT_DIR"
        return 0
    fi
    
    # Check parent directory (in case script is in subdirectory)
    local PARENT_DIR="$(dirname "$SCRIPT_DIR")"
    if [ -f "$PARENT_DIR/go.mod" ] || [ -f "$PARENT_DIR/main.go" ]; then
        echo "$PARENT_DIR"
        return 0
    fi
    
    # No source found
    echo ""
    return 1
}

# Compile and install R-Panel (Go application)
compile_and_install_rpanel() {
    local SOURCE_DIR=$(detect_rpanel_source)
    
    if [ -z "$SOURCE_DIR" ]; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_warning "R-Panel source code not found in current directory"
            log_info "Skipping R-Panel compilation"
            log_info "To install R-Panel later:"
            log_info "  1. Clone: git clone https://github.com/mrizkir/r-panel"
            log_info "  2. Run: cd r-panel && ./install.sh"
        fi
        return 0
    fi
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "R-Panel source found at: $SOURCE_DIR"
        log_info "Compiling R-Panel..."
    fi
    
    cd "$SOURCE_DIR"
    
    # Set Go environment
    export PATH=$PATH:/usr/local/go/bin
    export GOPATH=$HOME/go
    
    # Build frontend assets if package.json exists
    if [ -f "package.json" ]; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Installing frontend dependencies..."
        fi
        npm install >> "$LOG_FILE" 2>&1
        
        # Check if build script exists
        if grep -q '"build"' package.json; then
            if [ "$VERBOSE_MODE" = true ]; then
                log_info "Building frontend assets..."
            fi
            npm run build >> "$LOG_FILE" 2>&1
        fi
    fi
    
    # Build Go application
    if [ -f "main.go" ] || [ -f "cmd/main.go" ]; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Building Go application..."
        fi
        
        # Determine main file location
        if [ -f "cmd/main.go" ]; then
            MAIN_PATH="./cmd"
        else
            MAIN_PATH="."
        fi
        
        # Build with optimizations
        CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
            -ldflags="-s -w" \
            -o r-panel \
            $MAIN_PATH >> "$LOG_FILE" 2>&1
        
        if [ ! -f "r-panel" ]; then
            log_error "Go build failed. Check logs: $LOG_FILE"
            cd - >> "$LOG_FILE" 2>&1
            return 1
        fi
        
        if [ "$VERBOSE_MODE" = true ]; then
            log_success "Go application compiled successfully"
        fi
    else
        log_error "No main.go file found"
        cd - >> "$LOG_FILE" 2>&1
        return 1
    fi
    
    # Create installation directory
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Installing R-Panel to /usr/local/r-panel..."
    fi
    
    mkdir -p /usr/local/r-panel >> "$LOG_FILE" 2>&1
    
    # Copy compiled binary and required files
    cp r-panel /usr/local/r-panel/ >> "$LOG_FILE" 2>&1
    
    # Copy static files, templates, config, etc.
    for dir in static templates public assets config web; do
        if [ -d "$dir" ]; then
            cp -r "$dir" /usr/local/r-panel/ >> "$LOG_FILE" 2>&1
        fi
    done
    
    # Copy config files if exist
    for file in config.yaml config.yml .env.example config.toml; do
        if [ -f "$file" ]; then
            cp "$file" /usr/local/r-panel/ >> "$LOG_FILE" 2>&1
        fi
    done
    
    # Create config from example if needed
    if [ -f /usr/local/r-panel/.env.example ] && [ ! -f /usr/local/r-panel/.env ]; then
        cp /usr/local/r-panel/.env.example /usr/local/r-panel/.env >> "$LOG_FILE" 2>&1
    fi
    
    if [ -f /usr/local/r-panel/config.yaml.example ] && [ ! -f /usr/local/r-panel/config.yaml ]; then
        cp /usr/local/r-panel/config.yaml.example /usr/local/r-panel/config.yaml >> "$LOG_FILE" 2>&1
    fi
    
    # Set proper permissions
    chown -R www-data:www-data /usr/local/r-panel >> "$LOG_FILE" 2>&1
    chmod -R 755 /usr/local/r-panel >> "$LOG_FILE" 2>&1
    chmod +x /usr/local/r-panel/r-panel >> "$LOG_FILE" 2>&1
    
    # Create data directories if needed
    mkdir -p /usr/local/r-panel/{data,logs,uploads} >> "$LOG_FILE" 2>&1
    chown -R www-data:www-data /usr/local/r-panel/{data,logs,uploads} >> "$LOG_FILE" 2>&1
    chmod -R 775 /usr/local/r-panel/{data,logs,uploads} >> "$LOG_FILE" 2>&1
    
    # Create symbolic link for easy access
    ln -sf /usr/local/r-panel/r-panel /usr/local/bin/r-panel >> "$LOG_FILE" 2>&1
    
    # Create systemd service for R-Panel
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Creating R-Panel systemd service..."
    fi
    
    cat > /etc/systemd/system/r-panel.service <<EOF
[Unit]
Description=R-Panel Hosting Control Panel (Go)
After=network.target mysql.service redis.service
Requires=mysql.service

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/usr/local/r-panel
Environment="PORT=8080"
Environment="GIN_MODE=release"
ExecStart=/usr/local/r-panel/r-panel
Restart=always
RestartSec=3
StandardOutput=append:/opt/r-panel/logs/r-panel.log
StandardError=append:/opt/r-panel/logs/r-panel-error.log

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/usr/local/r-panel/data /usr/local/r-panel/logs /usr/local/r-panel/uploads /opt/r-panel/logs /var/www/vhosts

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    systemctl daemon-reload >> "$LOG_FILE" 2>&1
    
    # Enable and start R-Panel service
    systemctl enable r-panel >> "$LOG_FILE" 2>&1
    systemctl start r-panel >> "$LOG_FILE" 2>&1
    
    # Wait a moment for service to start
    sleep 3
    
    # Check if R-Panel service is running
    if systemctl is-active --quiet r-panel; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_success "R-Panel service started successfully on port 8080"
        fi
    else
        log_warning "R-Panel service failed to start. Check logs: journalctl -u r-panel"
    fi
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_success "R-Panel compiled and installed successfully"
    fi
    
    cd - >> "$LOG_FILE" 2>&1
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
    echo "  ✓ Go: $(/usr/local/go/bin/go version 2>/dev/null | cut -d' ' -f3 | sed 's/go//')"
    echo "  ✓ Composer: $(COMPOSER_ALLOW_SUPERUSER=1 composer --version 2>/dev/null | cut -d' ' -f3)"
    
    # Check if R-Panel was installed
    if [ -d /usr/local/r-panel ]; then
        echo "  ✓ R-Panel: Installed at /usr/local/r-panel"
        
        # Check if service is running
        if systemctl is-active --quiet r-panel 2>/dev/null; then
            echo "    └─ Service: Running on port 8080"
        else
            echo "    └─ Service: Stopped (check logs)"
        fi
    fi
    
    echo ""
    echo "Directories Created:"
    echo "  • /opt/r-panel (panel files)"
    echo "  • /var/www/r-panel (web files)"
    echo "  • /var/www/vhosts (user websites)"
    
    if [ -d /usr/local/r-panel ]; then
        echo "  • /usr/local/r-panel (R-Panel application)"
    fi
    
    echo ""
    
    # Get server IP
    SERVER_IP=$(hostname -I | awk '{print $1}')
    
    if [ -d /usr/local/r-panel ]; then
        echo "Access R-Panel:"
        echo "  • Direct Access: http://$SERVER_IP:8080"
        echo "  • With Domain: http://your-domain.com:8080"
        echo "  • With SSL: https://your-domain.com:8080"
        echo ""
        echo "NOTE: Clients will access R-Panel on their own domains:"
        echo "      https://client1.com:8080"
        echo "      https://client2.org:8080"
        echo ""
    fi
    
    echo "Next Steps:"
    
    if [ -d /usr/local/r-panel ]; then
        echo "  1. Configure R-Panel:"
        echo "     - Edit: nano /usr/local/r-panel/config.yaml"
        echo "     - Or: nano /usr/local/r-panel/.env"
        echo "  2. Run: mysql_secure_installation"
        echo "  3. Create database for R-Panel:"
        echo "     mysql -e \"CREATE DATABASE rpanel;\""
        echo "     mysql -e \"CREATE USER 'rpanel'@'localhost' IDENTIFIED BY 'your_password';\""
        echo "     mysql -e \"GRANT ALL ON rpanel.* TO 'rpanel'@'localhost';\""
        echo "  4. Update database config in R-Panel configuration file"
        echo "  5. Restart R-Panel: systemctl restart r-panel"
        echo "  6. Set up SSL certificate for port 8080 (optional):"
        echo "     - Configure SSL directly in R-Panel settings"
        echo "     - Or use a reverse proxy (nginx/apache) for SSL termination"
    else
        echo "  1. Run: mysql_secure_installation"
        echo "  2. Clone R-Panel: git clone https://github.com/mrizkir/r-panel"
        echo "  3. Install R-Panel: cd r-panel && ./install.sh"
    fi
    
    echo ""
    echo "Useful Commands:"
    echo "  • Check services: systemctl status nginx php8.2-fpm mariadb"
    
    if [ -d /usr/local/r-panel ]; then
        echo "  • R-Panel status: systemctl status r-panel"
        echo "  • R-Panel logs: journalctl -u r-panel -f"
        echo "  • Application logs: tail -f /opt/r-panel/logs/*.log"
        echo "  • Restart R-Panel: systemctl restart r-panel"
    fi
    
    echo "  • View logs: tail -f /opt/r-panel/logs/*.log"
    echo "  • Nginx test: nginx -t"
    
    if [ -d /usr/local/r-panel ]; then
        echo "  • R-Panel CLI: r-panel --help"
    fi
    
    echo ""
    echo "Firewall Ports:"
    echo "  • 22   - SSH"
    echo "  • 80   - HTTP (User Websites)"
    echo "  • 443  - HTTPS (User Websites)"
    echo "  • 8080 - R-Panel Control Panel"
    echo "  • 3306 - MySQL (optional, for remote access)"
    echo ""
    echo "=============================================="
    echo ""
}

# Main installation flow
main() {
    clear
    
    # Create log file immediately
    touch "$LOG_FILE"
    echo "R-Panel Installation Started at $(date)" > "$LOG_FILE"
    
    if [ "$VERBOSE_MODE" = false ]; then
        echo "=============================================="
        echo "  R-Panel Installation Script"
        echo "  Installing all required components..."
        echo "=============================================="
        echo ""
        echo "Mode: Quiet (Progress Bar)"
        echo "Log file: $LOG_FILE"
        echo ""
    else
        echo "=============================================="
        echo "  R-Panel Installation Script"
        echo "  Installing all required components..."
        echo "=============================================="
        echo ""
        echo "Mode: Verbose (Detailed Output)"
        echo "Log file: $LOG_FILE"
        echo ""
    fi
    
    check_root
    detect_os
    
    # Show initial progress if in quiet mode
    if [ "$VERBOSE_MODE" = false ]; then
        show_progress "Initializing installation..."
        sleep 0.5
    fi
    
    disable_prompts
    
    # Installation steps
    update_system
    install_utilities
    install_nginx
    install_php
    install_mariadb
    install_redis
    install_nodejs
    install_go
    install_composer
    
    # Configuration steps
    configure_firewall
    configure_fail2ban
    create_rpanel_structure
    create_nginx_config
    optimize_php_fpm
    create_swap
    
    # Compile and install R-Panel if source exists
    compile_and_install_rpanel
    
    # Clear progress bar line if in quiet mode
    if [ "$VERBOSE_MODE" = false ]; then
        echo ""
    fi
    
    # Display summary
    display_info
    
    log_success "Installation completed successfully!"
    echo ""
    log_info "Full installation log saved to: $LOG_FILE"
    echo ""
    log_warning "IMPORTANT: Reboot the server to ensure all configurations are active"
    echo ""
}

# Run main installation
main
