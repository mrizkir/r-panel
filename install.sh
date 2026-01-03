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

# Server configuration
SERVER_NAME=""
SERVER_IP=""
DETECTED_PUBLIC_IPS=()
DETECTED_PRIVATE_IPS=()
DETECTED_ALL_IPS=()
DEFAULT_IP=""

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
        set +e  # Temporarily disable exit on error
        sync > /dev/null 2>&1
        set -e  # Re-enable exit on error
    fi
    
    if [ "$CURRENT_STEP" -eq "$TOTAL_STEPS" ]; then
        echo ""
    fi
}

# Execute command based on verbose mode
execute() {
    local description="$1"
    shift
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "execute() called with: $description"
        log_info "Current step before increment: $CURRENT_STEP"
    fi
    
    # Increment step counter - use simple assignment to avoid set -e issues
    CURRENT_STEP=$(($CURRENT_STEP + 1))
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Current step after increment: $CURRENT_STEP"
    fi
    
    show_progress "$description"
    
    if [ "$VERBOSE_MODE" = true ]; then
        echo ""
        log_info "$description"
        # Temporarily disable exit on error and trap
        set +e
        trap - ERR  # Disable error trap temporarily
        
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Executing command: $@"
        fi
        
        # Execute command and capture exit code properly
        "$@" 2>&1 | tee -a "$LOG_FILE"
        local exit_code=${PIPESTATUS[0]}
        
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Command exit code: $exit_code"
        fi
        
        # Re-enable error handling
        set -e
        trap 'error_exit $LINENO' ERR
        
        if [ $exit_code -ne 0 ]; then
            log_error "Failed: $description (exit code: $exit_code)"
            return 1
        fi
    else
        # Temporarily disable exit on error and trap
        set +e
        trap - ERR  # Disable error trap temporarily
        
        "$@" >> "$LOG_FILE" 2>&1
        local exit_code=$?
        
        # Re-enable error handling
        set -e
        trap 'error_exit $LINENO' ERR
        
        if [ $exit_code -ne 0 ]; then
            echo ""
            log_error "Failed: $description (exit code: $exit_code)"
            log_error "Check log: $LOG_FILE"
            return 1
        fi
    fi
}

# Logging functions
log_info() {
    set +e  # Temporarily disable exit on error
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE" || true
    set -e  # Re-enable exit on error
}

log_success() {
    set +e  # Temporarily disable exit on error
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE" || true
    set -e  # Re-enable exit on error
}

log_warning() {
    set +e  # Temporarily disable exit on error
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE" || true
    set -e  # Re-enable exit on error
}

log_error() {
    set +e  # Temporarily disable exit on error
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE" || true
    set -e  # Re-enable exit on error
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Prompt for server name
prompt_server_name() {
    # Check if server name is already set via environment variable
    if [ -n "$R_PANEL_SERVER_NAME" ]; then
        SERVER_NAME="$R_PANEL_SERVER_NAME"
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Server name set from environment: $SERVER_NAME"
        fi
        return 0
    fi
    
    # Only prompt if we have a TTY (interactive mode)
    if [ ! -t 0 ]; then
        # Non-interactive mode, use hostname
        SERVER_NAME=$(hostname -f 2>/dev/null || hostname)
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Non-interactive mode detected. Using hostname: $SERVER_NAME"
        fi
        return 0
    fi
    
    echo ""
    echo -e "${CYAN}=============================================${NC}"
    echo -e "${CYAN}  Server Configuration${NC}"
    echo -e "${CYAN}=============================================${NC}"
    echo ""
    echo -e "${YELLOW}Please enter your server name (domain or hostname):${NC}"
    echo -e "${BLUE}Example: panel.example.com or server1.example.com${NC}"
    echo ""
    echo -n "Server name: "
    read -r SERVER_NAME
    
    # Validate input
    if [ -z "$SERVER_NAME" ]; then
        # If empty, use hostname as default
        SERVER_NAME=$(hostname -f 2>/dev/null || hostname)
        if [ "$VERBOSE_MODE" = true ]; then
            log_warning "No server name provided. Using hostname: $SERVER_NAME"
        fi
    else
        # Remove any whitespace
        SERVER_NAME=$(echo "$SERVER_NAME" | xargs)
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Server name set to: $SERVER_NAME"
        fi
    fi
    
    echo ""
    echo -e "${GREEN}Using server name: ${SERVER_NAME}${NC}"
    echo ""
}

# Detect available IP addresses
detect_ip_addresses() {
    local PUBLIC_IPS=()
    local PRIVATE_IPS=()
    local ALL_IPS=()
    
    # Get all IP addresses from network interfaces
    if command -v ip > /dev/null 2>&1; then
        # Using ip command (preferred)
        while IFS= read -r line; do
            local ip=$(echo "$line" | awk '{print $2}' | cut -d'/' -f1)
            if [ -n "$ip" ] && [ "$ip" != "127.0.0.1" ] && [ "$ip" != "::1" ]; then
                ALL_IPS+=("$ip")
                # Check if it's a private IP
                if [[ "$ip" =~ ^10\. ]] || \
                   [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || \
                   [[ "$ip" =~ ^192\.168\. ]] || \
                   [[ "$ip" =~ ^169\.254\. ]]; then
                    PRIVATE_IPS+=("$ip")
                else
                    PUBLIC_IPS+=("$ip")
                fi
            fi
        done < <(ip -4 addr show 2>/dev/null | grep "inet ")
    elif command -v ifconfig > /dev/null 2>&1; then
        # Using ifconfig as fallback
        while IFS= read -r line; do
            local ip=$(echo "$line" | grep -oE 'inet [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | awk '{print $2}')
            if [ -n "$ip" ] && [ "$ip" != "127.0.0.1" ]; then
                ALL_IPS+=("$ip")
                # Check if it's a private IP
                if [[ "$ip" =~ ^10\. ]] || \
                   [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || \
                   [[ "$ip" =~ ^192\.168\. ]] || \
                   [[ "$ip" =~ ^169\.254\. ]]; then
                    PRIVATE_IPS+=("$ip")
                else
                    PUBLIC_IPS+=("$ip")
                fi
            fi
        done < <(ifconfig 2>/dev/null | grep "inet ")
    else
        # Fallback to hostname -I
        local hostname_ips=$(hostname -I 2>/dev/null | tr ' ' '\n')
        while IFS= read -r ip; do
            if [ -n "$ip" ] && [ "$ip" != "127.0.0.1" ]; then
                ALL_IPS+=("$ip")
                # Check if it's a private IP
                if [[ "$ip" =~ ^10\. ]] || \
                   [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || \
                   [[ "$ip" =~ ^192\.168\. ]] || \
                   [[ "$ip" =~ ^169\.254\. ]]; then
                    PRIVATE_IPS+=("$ip")
                else
                    PUBLIC_IPS+=("$ip")
                fi
            fi
        done <<< "$hostname_ips"
    fi
    
    # Return results via global variables (bash doesn't support returning arrays easily)
    DETECTED_PUBLIC_IPS=("${PUBLIC_IPS[@]}")
    DETECTED_PRIVATE_IPS=("${PRIVATE_IPS[@]}")
    DETECTED_ALL_IPS=("${ALL_IPS[@]}")
    
    # Determine default IP
    if [ ${#PUBLIC_IPS[@]} -gt 0 ]; then
        DEFAULT_IP="${PUBLIC_IPS[0]}"
    elif [ ${#PRIVATE_IPS[@]} -gt 0 ]; then
        DEFAULT_IP="${PRIVATE_IPS[0]}"
    else
        DEFAULT_IP="127.0.0.1"
    fi
}

# Prompt for server IP address
prompt_server_ip() {
    # Check if server IP is already set via environment variable
    if [ -n "$R_PANEL_SERVER_IP" ]; then
        SERVER_IP="$R_PANEL_SERVER_IP"
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Server IP set from environment: $SERVER_IP"
        fi
        return 0
    fi
    
    # Detect available IP addresses
    detect_ip_addresses
    
    # Only prompt if we have a TTY (interactive mode)
    if [ ! -t 0 ]; then
        # Non-interactive mode, use default IP
        SERVER_IP="$DEFAULT_IP"
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Non-interactive mode detected. Using default IP: $SERVER_IP"
        fi
        return 0
    fi
    
    echo ""
    echo -e "${CYAN}=============================================${NC}"
    echo -e "${CYAN}  Server IP Address Configuration${NC}"
    echo -e "${CYAN}=============================================${NC}"
    echo ""
    
    # Display available IP addresses
    if [ ${#DETECTED_ALL_IPS[@]} -gt 0 ]; then
        echo -e "${YELLOW}Available IP addresses on this system:${NC}"
        echo ""
        
        local index=1
        if [ ${#DETECTED_PUBLIC_IPS[@]} -gt 0 ]; then
            echo -e "${GREEN}Public IP addresses:${NC}"
            for ip in "${DETECTED_PUBLIC_IPS[@]}"; do
                echo -e "  ${GREEN}[$index]${NC} $ip ${BLUE}(Public)${NC}"
                ((index++))
            done
            echo ""
        fi
        
        if [ ${#DETECTED_PRIVATE_IPS[@]} -gt 0 ]; then
            echo -e "${YELLOW}Private IP addresses:${NC}"
            for ip in "${DETECTED_PRIVATE_IPS[@]}"; do
                echo -e "  ${YELLOW}[$index]${NC} $ip ${BLUE}(Private)${NC}"
                ((index++))
            done
            echo ""
        fi
    else
        echo -e "${YELLOW}No IP addresses detected. Using localhost.${NC}"
        echo ""
    fi
    
    echo -e "${YELLOW}Please enter the IP address to use:${NC}"
    echo -e "${BLUE}Default: $DEFAULT_IP${NC}"
    echo ""
    echo -n "Server IP address [$DEFAULT_IP]: "
    read -r SERVER_IP
    
    # Validate input
    if [ -z "$SERVER_IP" ]; then
        # If empty, use default
        SERVER_IP="$DEFAULT_IP"
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "No IP address provided. Using default: $SERVER_IP"
        fi
    else
        # Remove any whitespace
        SERVER_IP=$(echo "$SERVER_IP" | xargs)
        
        # Validate IP format (basic validation)
        if [[ ! "$SERVER_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            log_warning "Invalid IP format. Using default: $DEFAULT_IP"
            SERVER_IP="$DEFAULT_IP"
        else
            if [ "$VERBOSE_MODE" = true ]; then
                log_info "Server IP set to: $SERVER_IP"
            fi
        fi
    fi
    
    echo ""
    echo -e "${GREEN}Using server IP: ${SERVER_IP}${NC}"
    echo ""
}

# Configure hostname and /etc/hosts
configure_hostname() {
    if [ -z "$SERVER_NAME" ] || [ "$SERVER_NAME" = "default" ]; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Skipping hostname configuration (no valid server name provided)"
        fi
        return 0
    fi
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Configuring hostname and /etc/hosts..."
    fi
    
    # Get current hostname
    local CURRENT_HOSTNAME=$(hostname)
    local CURRENT_FQDN=$(hostname -f 2>/dev/null || hostname)
    
    # Only configure if server name is different from current hostname
    if [ "$SERVER_NAME" != "$CURRENT_HOSTNAME" ] && [ "$SERVER_NAME" != "$CURRENT_FQDN" ]; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Setting hostname to: $SERVER_NAME"
        fi
        
        # Set hostname using hostnamectl
        set +e
        hostnamectl set-hostname "$SERVER_NAME" >> "$LOG_FILE" 2>&1
        local hostname_result=$?
        set -e
        
        if [ $hostname_result -eq 0 ]; then
            if [ "$VERBOSE_MODE" = true ]; then
                log_success "Hostname set to: $SERVER_NAME"
            fi
        else
            log_warning "Failed to set hostname using hostnamectl. Continuing..."
        fi
    else
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Hostname already set to: $SERVER_NAME"
        fi
    fi
    
    # Update /etc/hosts if IP and server name are provided
    if [ -n "$SERVER_IP" ] && [ -n "$SERVER_NAME" ] && [ "$SERVER_IP" != "127.0.0.1" ] && [ "$SERVER_NAME" != "default" ]; then
        # Check if entry already exists in /etc/hosts
        if ! grep -qE "^[[:space:]]*${SERVER_IP}[[:space:]]+.*${SERVER_NAME}" /etc/hosts 2>/dev/null; then
            if [ "$VERBOSE_MODE" = true ]; then
                log_info "Adding $SERVER_IP $SERVER_NAME to /etc/hosts"
            fi
            
            # Backup /etc/hosts
            cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d_%H%M%S) >> "$LOG_FILE" 2>&1 || true
            
            # Remove old entry if exists (to avoid duplicates)
            sed -i "/[[:space:]]*${SERVER_NAME}[[:space:]]*$/d" /etc/hosts 2>> "$LOG_FILE" || true
            
            # Add new entry
            set +e
            echo "$SERVER_IP    $SERVER_NAME" >> /etc/hosts 2>> "$LOG_FILE"
            local hosts_result=$?
            set -e
            
            if [ $hosts_result -eq 0 ]; then
                if [ "$VERBOSE_MODE" = true ]; then
                    log_success "Updated /etc/hosts with $SERVER_IP -> $SERVER_NAME"
                fi
            else
                log_warning "Failed to update /etc/hosts. You may need to add it manually."
            fi
        else
            if [ "$VERBOSE_MODE" = true ]; then
                log_info "Entry for $SERVER_IP -> $SERVER_NAME already exists in /etc/hosts"
            fi
        fi
    fi
    
    # Also ensure localhost entry exists
    if ! grep -qE "^[[:space:]]*127\.0\.0\.1[[:space:]]+.*localhost" /etc/hosts 2>/dev/null; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Ensuring localhost entry exists in /etc/hosts"
        fi
        set +e
        echo "127.0.0.1    localhost" >> /etc/hosts 2>> "$LOG_FILE" || true
        set -e
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
        set +e  # Temporarily disable exit on error
        sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf 2>> "$LOG_FILE"
        set -e  # Re-enable exit on error
    fi
    
    # Create needrestart config if not exists
    set +e  # Temporarily disable exit on error
    mkdir -p /etc/needrestart >> "$LOG_FILE" 2>&1
    set -e  # Re-enable exit on error
    
    set +e  # Temporarily disable exit on error
    cat > /etc/needrestart/conf.d/no-prompt.conf <<'EOF'
# Restart services automatically without asking
$nrconf{restart} = 'a';
EOF
    set -e  # Re-enable exit on error
    
    # Configure debconf for non-interactive mode
    if command -v debconf-set-selections &> /dev/null; then
        set +e  # Temporarily disable exit on error
        echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections >> "$LOG_FILE" 2>&1
        set -e  # Re-enable exit on error
    else
        log_warning "debconf-set-selections not found, skipping debconf configuration"
    fi
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_success "Non-interactive mode configured"
    else
        echo "Non-interactive mode configured" >> "$LOG_FILE"
    fi
}

# Update system
update_system() {
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Entering update_system() function"
    fi
    
    # Configure apt to not ask questions
    if command -v debconf-set-selections &> /dev/null; then
        set +e  # Temporarily disable exit on error
        echo 'libc6 libraries/restart-without-asking boolean true' | debconf-set-selections >> "$LOG_FILE" 2>&1
        set -e  # Re-enable exit on error
    fi
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "About to execute: apt-get update -y"
    fi
    
    execute "Updating system packages" apt-get update -y
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "apt-get update completed"
    fi
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
    
    # Backup existing default config if it exists
    if [ -f /etc/nginx/sites-available/default ]; then
        cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.backup.$(date +%Y%m%d_%H%M%S) >> "$LOG_FILE" 2>&1 || true
    fi
    
    # Use server name if provided, otherwise use default
    if [ -z "$SERVER_NAME" ]; then
        SERVER_NAME="default"
    fi
    
    # Create a basic default configuration for user websites
    cat > /etc/nginx/sites-available/default <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    root /var/www/html;
    index index.html index.htm index.php;
    
    # Server name from user input
    server_name $SERVER_NAME;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    location ~ \.php\$ {
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
    
    # Test and reload Nginx (suppress warnings about conflicting server names)
    set +e
    nginx -t >> "$LOG_FILE" 2>&1
    local nginx_test_result=$?
    set -e
    
    # Check if nginx test passed (exit code 0 means success, even with warnings)
    if [ $nginx_test_result -eq 0 ]; then
        systemctl reload nginx >> "$LOG_FILE" 2>&1
        if [ "$VERBOSE_MODE" = true ]; then
            log_success "Nginx configuration created"
        fi
    else
        log_error "Nginx configuration test failed. Check logs: $LOG_FILE"
        return 1
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
    # Check for go.mod in root or backend directory
    if [ -f "$SCRIPT_DIR/go.mod" ] || [ -f "$SCRIPT_DIR/backend/go.mod" ] || \
       [ -f "$SCRIPT_DIR/main.go" ] || [ -f "$SCRIPT_DIR/backend/cmd/server/main.go" ] || \
       [ -d "$SCRIPT_DIR/.git" ]; then
        echo "$SCRIPT_DIR"
        return 0
    fi
    
    # Check parent directory (in case script is in subdirectory)
    local PARENT_DIR="$(dirname "$SCRIPT_DIR")"
    if [ -f "$PARENT_DIR/go.mod" ] || [ -f "$PARENT_DIR/backend/go.mod" ] || \
       [ -f "$PARENT_DIR/main.go" ] || [ -f "$PARENT_DIR/backend/cmd/server/main.go" ]; then
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
    
    # Build Go application - search for main.go in various locations
    MAIN_PATH=""
    if [ -f "backend/cmd/server/main.go" ]; then
        MAIN_PATH="./backend/cmd/server"
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Found main.go at: backend/cmd/server/main.go"
        fi
    elif [ -f "cmd/server/main.go" ]; then
        MAIN_PATH="./cmd/server"
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Found main.go at: cmd/server/main.go"
        fi
    elif [ -f "cmd/main.go" ]; then
        MAIN_PATH="./cmd"
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Found main.go at: cmd/main.go"
        fi
    elif [ -f "main.go" ]; then
        MAIN_PATH="."
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Found main.go at: main.go"
        fi
    fi
    
    if [ -n "$MAIN_PATH" ]; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Building Go application from: $MAIN_PATH"
        fi
        
        # Determine build directory and main path
        BUILD_DIR="$SOURCE_DIR"
        if [ -f "$SOURCE_DIR/backend/go.mod" ]; then
            BUILD_DIR="$SOURCE_DIR/backend"
            MAIN_PATH="./cmd/server"
        elif [ -f "$SOURCE_DIR/go.mod" ]; then
            BUILD_DIR="$SOURCE_DIR"
            # MAIN_PATH already set above
        fi
        
        # Change to build directory
        cd "$BUILD_DIR"
        
        # Build with optimizations
        CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
            -ldflags="-s -w" \
            -o r-panel \
            $MAIN_PATH >> "$LOG_FILE" 2>&1
        
        if [ ! -f "r-panel" ]; then
            log_error "Go build failed. Check logs: $LOG_FILE"
            cd "$SOURCE_DIR" >> "$LOG_FILE" 2>&1
            return 1
        fi
        
        # Move binary to source directory for installation
        if [ "$BUILD_DIR" != "$SOURCE_DIR" ]; then
            mv r-panel "$SOURCE_DIR/r-panel" >> "$LOG_FILE" 2>&1
            cd "$SOURCE_DIR"
        fi
        
        if [ "$VERBOSE_MODE" = true ]; then
            log_success "Go application compiled successfully"
        fi
    else
        log_error "No main.go file found. Searched in:"
        log_error "  - backend/cmd/server/main.go"
        log_error "  - cmd/server/main.go"
        log_error "  - cmd/main.go"
        log_error "  - main.go"
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
    
    # Copy static files, templates, config, etc. (check both root and backend)
    for dir in static templates public assets config web; do
        if [ -d "$dir" ]; then
            cp -r "$dir" /usr/local/r-panel/ >> "$LOG_FILE" 2>&1
        elif [ -d "backend/$dir" ]; then
            cp -r "backend/$dir" /usr/local/r-panel/ >> "$LOG_FILE" 2>&1
        fi
    done
    
    # Copy backend-specific directories
    if [ -d "backend/templates" ]; then
        cp -r backend/templates /usr/local/r-panel/ >> "$LOG_FILE" 2>&1
    fi
    if [ -d "backend/configs" ]; then
        cp -r backend/configs /usr/local/r-panel/ >> "$LOG_FILE" 2>&1
    fi
    
    # Copy config files if exist (check both root and backend)
    for file in config.yaml config.yml .env.example config.toml; do
        if [ -f "$file" ]; then
            cp "$file" /usr/local/r-panel/ >> "$LOG_FILE" 2>&1
        elif [ -f "backend/$file" ]; then
            cp "backend/$file" /usr/local/r-panel/ >> "$LOG_FILE" 2>&1
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
    if [ -n "$SERVER_NAME" ] || [ -n "$SERVER_IP" ]; then
        echo "Server Configuration:"
        if [ -n "$SERVER_NAME" ]; then
            echo "  • Server Name: $SERVER_NAME"
        fi
        if [ -n "$SERVER_IP" ]; then
            echo "  • Server IP: $SERVER_IP"
        fi
        echo ""
    fi
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
    
    # Use configured server IP or detect if not set
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "127.0.0.1")
    fi
    
    if [ -d /usr/local/r-panel ]; then
        echo "Access R-Panel:"
        echo "  • Direct Access: http://$SERVER_IP:8080"
        if [ -n "$SERVER_NAME" ] && [ "$SERVER_NAME" != "default" ]; then
            echo "  • With Domain: http://$SERVER_NAME:8080"
            echo "  • With SSL: https://$SERVER_NAME:8080"
        else
            echo "  • With Domain: http://your-domain.com:8080"
            echo "  • With SSL: https://your-domain.com:8080"
        fi
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
    
    # Prompt for server name
    prompt_server_name
    
    # Log server name
    echo "Server name: $SERVER_NAME" >> "$LOG_FILE"
    
    # Prompt for server IP address
    prompt_server_ip
    
    # Log server IP
    echo "Server IP: $SERVER_IP" >> "$LOG_FILE"
    
    # Configure hostname and /etc/hosts
    configure_hostname
    
    # Show initial progress if in quiet mode
    if [ "$VERBOSE_MODE" = false ]; then
        show_progress "Initializing installation..."
        sleep 0.5
    fi
    
    # Install debconf-utils first (needed by disable_prompts)
    if ! command -v debconf-set-selections &> /dev/null; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Installing debconf-utils (required for non-interactive mode)..."
        fi
        apt-get update -qq >> "$LOG_FILE" 2>&1
        apt-get install -y -qq debconf-utils >> "$LOG_FILE" 2>&1
    fi
    
    disable_prompts
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Non-interactive mode setup completed"
        log_info "Starting system update..."
    fi
    
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
