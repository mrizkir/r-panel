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
    
    # Check if command involves apt-get or add-apt-repository and wait for locks
    local cmd_str="$*"
    if [[ "$cmd_str" == *"apt-get"* ]] || [[ "$cmd_str" == *"add-apt-repository"* ]] || [[ "$cmd_str" == *"apt"* ]]; then
        wait_for_apt_lock
    fi
    
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

# Wait for apt/dpkg lock to be released
wait_for_apt_lock() {
    local max_wait=300  # Maximum wait time in seconds (5 minutes)
    local wait_time=0
    local check_interval=2  # Check every 2 seconds
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Checking for apt/dpkg locks..."
    fi
    
    while [ $wait_time -lt $max_wait ]; do
        # Check if lock files exist and if processes are running
        if lsof /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
           lsof /var/lib/dpkg/lock >/dev/null 2>&1 || \
           lsof /var/lib/apt/lists/lock >/dev/null 2>&1 || \
           lsof /var/cache/apt/archives/lock >/dev/null 2>&1; then
            
            # Get the process holding the lock
            local lock_process=$(lsof /var/lib/dpkg/lock-frontend 2>/dev/null | tail -n +2 | awk '{print $2}' | head -1)
            
            if [ -n "$lock_process" ]; then
                local process_name=$(ps -p "$lock_process" -o comm= 2>/dev/null || echo "unknown")
                if [ "$VERBOSE_MODE" = true ]; then
                    log_warning "apt/dpkg lock is held by process $lock_process ($process_name). Waiting..."
                fi
            else
                if [ "$VERBOSE_MODE" = true ]; then
                    log_warning "apt/dpkg lock detected. Waiting..."
                fi
            fi
            
            sleep $check_interval
            wait_time=$((wait_time + check_interval))
        else
            # No locks found, we can proceed
            if [ $wait_time -gt 0 ]; then
                if [ "$VERBOSE_MODE" = true ]; then
                    log_success "apt/dpkg locks released after ${wait_time} seconds"
                fi
            fi
            return 0
        fi
    done
    
    # If we get here, we've waited too long
    log_error "Timeout waiting for apt/dpkg locks to be released (waited ${max_wait} seconds)"
    log_error "Another package management process may be running."
    log_error "Please check for running apt/apt-get/dpkg processes:"
    log_error "  ps aux | grep -E 'apt|dpkg'"
    log_error "Or wait for the process to complete and try again."
    return 1
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
    
    # Backup /etc/hosts before making any changes
    if [ -f /etc/hosts ]; then
        if [ ! -f /etc/hosts.bak ]; then
            cp /etc/hosts /etc/hosts.bak >> "$LOG_FILE" 2>&1 || true
            if [ "$VERBOSE_MODE" = true ]; then
                log_info "Backed up /etc/hosts to /etc/hosts.bak"
            fi
        else
            if [ "$VERBOSE_MODE" = true ]; then
                log_info "/etc/hosts.bak already exists, skipping backup"
            fi
        fi
    fi
    
    # Get current hostname
    local CURRENT_HOSTNAME=$(hostname 2>/dev/null || echo "")
    local CURRENT_FQDN=$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo "")
    
    # Always set hostname if SERVER_NAME is provided and different
    if [ -n "$SERVER_NAME" ] && [ "$SERVER_NAME" != "$CURRENT_HOSTNAME" ] && [ "$SERVER_NAME" != "$CURRENT_FQDN" ]; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Setting hostname from '$CURRENT_HOSTNAME' to '$SERVER_NAME'"
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
            log_warning "Failed to set hostname using hostnamectl. Trying alternative method..."
            # Try alternative method
            set +e
            echo "$SERVER_NAME" > /etc/hostname 2>> "$LOG_FILE" || true
            set -e
        fi
    else
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Hostname already set to: $SERVER_NAME (no change needed)"
        fi
    fi
    
    # Update /etc/hosts if IP and server name are provided
    if [ -n "$SERVER_IP" ] && [ -n "$SERVER_NAME" ] && [ "$SERVER_IP" != "127.0.0.1" ] && [ "$SERVER_NAME" != "default" ]; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Updating /etc/hosts with $SERVER_IP -> $SERVER_NAME"
        fi
        
        # Remove old entries that contain the IP or server name (to avoid duplicates and malformed entries)
        set +e
        # Remove lines containing the IP address (but keep localhost entries)
        sed -i "/^[[:space:]]*${SERVER_IP}[[:space:]]/d" /etc/hosts 2>> "$LOG_FILE" || true
        # Remove lines ending with the server name (but be careful with localhost)
        sed -i "/[[:space:]]${SERVER_NAME}[[:space:]]*$/d" /etc/hosts 2>> "$LOG_FILE" || true
        # Remove lines that have server name in the middle
        sed -i "/[[:space:]]${SERVER_NAME}[[:space:]]/d" /etc/hosts 2>> "$LOG_FILE" || true
        set -e
        
        # Add new entry with proper formatting
        set +e
        printf "%s\t%s\n" "$SERVER_IP" "$SERVER_NAME" >> /etc/hosts 2>> "$LOG_FILE"
        local hosts_result=$?
        set -e
        
        if [ $hosts_result -eq 0 ]; then
            if [ "$VERBOSE_MODE" = true ]; then
                log_success "Updated /etc/hosts with $SERVER_IP -> $SERVER_NAME"
            fi
        else
            log_warning "Failed to update /etc/hosts. You may need to add it manually."
        fi
    fi
    
    # Also ensure localhost entry exists and is correct
    set +e
    if ! grep -qE "^[[:space:]]*127\.0\.0\.1[[:space:]]+.*localhost" /etc/hosts 2>/dev/null; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Ensuring localhost entry exists in /etc/hosts"
        fi
        printf "127.0.0.1\tlocalhost\n" >> /etc/hosts 2>> "$LOG_FILE" || true
    fi
    
    # Ensure IPv6 localhost entry exists
    if ! grep -qE "^[[:space:]]*::1[[:space:]]+.*localhost" /etc/hosts 2>/dev/null; then
        printf "::1\t\tlocalhost\n" >> /etc/hosts 2>> "$LOG_FILE" || true
    fi
    set -e
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
    
    # Wait for apt locks before updating
    wait_for_apt_lock
    
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
    # Wait for apt locks before installing
    wait_for_apt_lock
    
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
        lsb-release \
        quota
    
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

# Install Certbot for SSL certificates
install_certbot() {
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Installing Certbot for SSL certificates..."
    fi
    
    wait_for_apt_lock
    execute "Installing Certbot" apt-get install -y certbot python3-certbot-nginx
    
    # Enable certbot auto-renewal timer
    systemctl enable certbot.timer >> "$LOG_FILE" 2>&1 || true
    systemctl start certbot.timer >> "$LOG_FILE" 2>&1 || true
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_success "Certbot installed successfully"
    fi
}

# Install PHP and PHP-FPM
install_php() {
    # PHP version to install
    PHP_VERSION="8.2"
    
    # Wait for apt locks before installing PHP
    wait_for_apt_lock
    
    # Add PHP repository based on OS
    if [ "$OS" = "ubuntu" ]; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Adding Ondrej PHP repository for Ubuntu..."
        fi
        wait_for_apt_lock
        add-apt-repository -y ppa:ondrej/php >> "$LOG_FILE" 2>&1
        wait_for_apt_lock
        apt-get update -y >> "$LOG_FILE" 2>&1
    elif [ "$OS" = "debian" ]; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Adding Sury PHP repository for Debian..."
        fi
        
        # Add Sury repository key
        curl -fsSL https://packages.sury.org/php/apt.gpg -o /etc/apt/trusted.gpg.d/php.gpg 2>> "$LOG_FILE"
        
        # Add repository
        echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
        
        wait_for_apt_lock
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
    wait_for_apt_lock
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
    wait_for_apt_lock
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
    wait_for_apt_lock
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - >> "$LOG_FILE" 2>&1
    
    wait_for_apt_lock
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

# Create R-Panel system user
create_rpanel_user() {
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Creating R-Panel system user..."
    fi
    
    # Check if user already exists
    if id "rpanel" &>/dev/null; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "User 'rpanel' already exists"
        fi
    else
        # Create system user without home directory (like mysql user)
        set +e
        useradd -r -s /bin/false -d /nonexistent -c "R-Panel System User" rpanel >> "$LOG_FILE" 2>&1
        local user_result=$?
        set -e
        
        if [ $user_result -eq 0 ]; then
            if [ "$VERBOSE_MODE" = true ]; then
                log_success "User 'rpanel' created successfully"
            fi
        else
            log_error "Failed to create user 'rpanel'"
            return 1
        fi
    fi
    
    # Add rpanel to groups that have read access to logs
    set +e
    usermod -a -G adm,systemd-journal rpanel >> "$LOG_FILE" 2>&1 || true
    set -e
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_success "R-Panel user configured"
    fi
}

# Create R-Panel directory structure
create_rpanel_structure() {
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Creating R-Panel directory structure..."
    fi
    
    # Main directories (consolidated in /usr/local/r-panel)
    mkdir -p /usr/local/r-panel/bin >> "$LOG_FILE" 2>&1
    mkdir -p /usr/local/r-panel/config >> "$LOG_FILE" 2>&1
    mkdir -p /usr/local/r-panel/logs >> "$LOG_FILE" 2>&1
    mkdir -p /usr/local/r-panel/temp >> "$LOG_FILE" 2>&1
    mkdir -p /usr/local/r-panel/backups >> "$LOG_FILE" 2>&1
    
    # Web directories
    mkdir -p /var/www/r-panel >> "$LOG_FILE" 2>&1
    mkdir -p /var/www/r-panel/public >> "$LOG_FILE" 2>&1
    mkdir -p /var/www/r-panel/storage >> "$LOG_FILE" 2>&1
    
    # User websites directory
    mkdir -p /var/www/vhosts >> "$LOG_FILE" 2>&1
    
    # Set permissions
    # /usr/local/r-panel owned by rpanel (for R-Panel application)
    chown -R rpanel:rpanel /usr/local/r-panel >> "$LOG_FILE" 2>&1 || true
    chmod -R 755 /usr/local/r-panel >> "$LOG_FILE" 2>&1 || true
    
    # /var/www owned by www-data (for client websites)
    chown -R www-data:www-data /var/www >> "$LOG_FILE" 2>&1 || true
    chmod -R 755 /var/www >> "$LOG_FILE" 2>&1 || true
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_success "R-Panel directory structure created"
    fi
}

# Configure permissions for R-Panel to access system files
configure_rpanel_permissions() {
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Configuring permissions for R-Panel user (rpanel)..."
    fi
    
    # Set permissions for log directories (allow rpanel to read via group membership)
    set +e
    chmod 755 /var/log >> "$LOG_FILE" 2>&1 || true
    chmod 644 /var/log/*.log 2>> "$LOG_FILE" || true
    chmod 755 /var/log/nginx >> "$LOG_FILE" 2>&1 || true
    chmod 644 /var/log/nginx/*.log 2>> "$LOG_FILE" || true
    set -e
    
    # Create sudo rules for rpanel user to manage system configurations
    # This allows R-Panel to update nginx, php-fpm configs, and restart services
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Creating sudo rules for rpanel user..."
    fi
    
    cat > /etc/sudoers.d/r-panel <<'EOF'
# R-Panel sudo rules for rpanel system user
# Allow rpanel to manage nginx configuration
rpanel ALL=(ALL) NOPASSWD: /usr/bin/systemctl reload nginx
rpanel ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart nginx
rpanel ALL=(ALL) NOPASSWD: /usr/sbin/nginx -t
rpanel ALL=(ALL) NOPASSWD: /bin/cp /etc/nginx/sites-available/* /etc/nginx/sites-available/*
rpanel ALL=(ALL) NOPASSWD: /bin/mv /etc/nginx/sites-available/* /etc/nginx/sites-available/*
rpanel ALL=(ALL) NOPASSWD: /bin/rm /etc/nginx/sites-available/*
rpanel ALL=(ALL) NOPASSWD: /bin/ln -sf /etc/nginx/sites-available/* /etc/nginx/sites-enabled/*
rpanel ALL=(ALL) NOPASSWD: /bin/rm /etc/nginx/sites-enabled/*

# Allow rpanel to manage PHP-FPM
rpanel ALL=(ALL) NOPASSWD: /usr/bin/systemctl reload php*-fpm
rpanel ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart php*-fpm
rpanel ALL=(ALL) NOPASSWD: /bin/cp /etc/php/*/fpm/pool.d/* /etc/php/*/fpm/pool.d/*
rpanel ALL=(ALL) NOPASSWD: /bin/mv /etc/php/*/fpm/pool.d/* /etc/php/*/fpm/pool.d/*
rpanel ALL=(ALL) NOPASSWD: /bin/rm /etc/php/*/fpm/pool.d/*

# Allow rpanel to read system logs (no sudo needed, handled by group membership)
EOF

    # Set proper permissions for sudoers file
    chmod 440 /etc/sudoers.d/r-panel >> "$LOG_FILE" 2>&1 || true
    
    # Set group ownership for nginx and php config directories
    set +e
    chgrp -R rpanel /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/conf.d 2>> "$LOG_FILE" || true
    chmod -R g+w /etc/nginx/sites-available /etc/nginx/sites-enabled /etc/nginx/conf.d 2>> "$LOG_FILE" || true
    
    # For PHP-FPM pool.d directories
    for phpdir in /etc/php/*/fpm/pool.d; do
        if [ -d "$phpdir" ]; then
            chgrp rpanel "$phpdir" 2>> "$LOG_FILE" || true
            chmod g+w "$phpdir" 2>> "$LOG_FILE" || true
        fi
    done
    set -e
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_success "R-Panel permissions configured for rpanel user"
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

# Create temporary self-signed SSL certificate for R-Panel
create_temp_ssl_certificate() {
    local R_PANEL_DOMAIN="${SERVER_NAME:-panel.example.com}"
    local CERT_DIR="/etc/letsencrypt/live/${R_PANEL_DOMAIN}"
    local CERT_FILE="${CERT_DIR}/fullchain.pem"
    local KEY_FILE="${CERT_DIR}/privkey.pem"
    
    # Check if openssl is available
    if ! command -v openssl &> /dev/null; then
        log_error "OpenSSL is not installed. Cannot create SSL certificate."
        log_error "Please install openssl: apt-get install openssl"
        return 1
    fi
    
    # Create directory structure
    mkdir -p "$CERT_DIR" >> "$LOG_FILE" 2>&1
    
    # Verify directory was created
    if [ ! -d "$CERT_DIR" ]; then
        log_error "Failed to create certificate directory: $CERT_DIR"
        return 1
    fi
    
    # Check if certificate already exists and is valid
    if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
        # Verify certificate is valid (not empty and readable)
        if [ -s "$CERT_FILE" ] && [ -s "$KEY_FILE" ]; then
            if [ "$VERBOSE_MODE" = true ]; then
                log_info "SSL certificate already exists at ${CERT_DIR}"
            fi
            return 0
        else
            if [ "$VERBOSE_MODE" = true ]; then
                log_warning "Existing certificate files are empty, recreating..."
            fi
            rm -f "$CERT_FILE" "$KEY_FILE" >> "$LOG_FILE" 2>&1
        fi
    fi
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Creating temporary self-signed SSL certificate for ${R_PANEL_DOMAIN}..."
    fi
    
    # Generate self-signed certificate valid for 365 days
    # Use set +e to handle potential errors gracefully
    set +e
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$KEY_FILE" \
        -out "$CERT_FILE" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=${R_PANEL_DOMAIN}" \
        >> "$LOG_FILE" 2>&1
    local openssl_result=$?
    set -e
    
    if [ $openssl_result -ne 0 ]; then
        log_error "Failed to create SSL certificate. OpenSSL error code: $openssl_result"
        log_error "Check if openssl is installed: apt-get install openssl"
        return 1
    fi
    
    # Verify certificate files were created
    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
        log_error "Certificate files were not created successfully"
        log_error "Expected: $CERT_FILE and $KEY_FILE"
        return 1
    fi
    
    # Verify files are not empty
    if [ ! -s "$CERT_FILE" ] || [ ! -s "$KEY_FILE" ]; then
        log_error "Certificate files are empty"
        return 1
    fi
    
    # Set proper permissions
    chmod 600 "$KEY_FILE" >> "$LOG_FILE" 2>&1
    chmod 644 "$CERT_FILE" >> "$LOG_FILE" 2>&1
    
    # Verify permissions were set correctly
    if [ "$VERBOSE_MODE" = true ]; then
        log_success "Temporary self-signed SSL certificate created at ${CERT_DIR}"
        log_info "Certificate: $CERT_FILE"
        log_info "Private key: $KEY_FILE"
        log_info "Note: Replace with Let's Encrypt certificate using: certbot --nginx -d ${R_PANEL_DOMAIN}"
    fi
    
    return 0
}

# Create Nginx configuration for R-Panel reverse proxy
create_rpanel_nginx_config() {
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Creating Nginx configuration for R-Panel reverse proxy..."
    fi
    
    # Get R-Panel domain from config or use server name
    local R_PANEL_DOMAIN="${SERVER_NAME:-panel.example.com}"
    
    # Create temporary self-signed certificate first (so nginx can start with SSL)
    # This will be replaced by Let's Encrypt certificate if available
    create_temp_ssl_certificate
    
    # Verify certificate files exist before creating nginx config
    local CERT_DIR="/etc/letsencrypt/live/${R_PANEL_DOMAIN}"
    local CERT_FILE="${CERT_DIR}/fullchain.pem"
    local KEY_FILE="${CERT_DIR}/privkey.pem"
    
    # Check if certificate files exist and are valid
    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
        log_error "SSL certificate files not found at ${CERT_DIR}"
        log_error "Certificate creation may have failed. Attempting to create again..."
        
        # Try to create certificate one more time
        if ! create_temp_ssl_certificate; then
            log_error "Failed to create SSL certificate. Creating HTTP-only configuration..."
            log_warning "SSL will not be available. You can add SSL later by running: certbot --nginx -d ${R_PANEL_DOMAIN}"
            
            # Create HTTP-only config as fallback
            cat > /etc/nginx/sites-available/r-panel <<EOF
# HTTP server (SSL not available - certificate creation failed)
server {
    listen 8080;
    listen [::]:8080;
    server_name _;

    # Logging
    access_log /var/log/nginx/r-panel-access.log;
    error_log /var/log/nginx/r-panel-error.log;

    # Increase body size for file uploads
    client_max_body_size 100M;
    client_body_buffer_size 128k;

    # Proxy to backend Go application
    location / {
        proxy_pass http://127.0.0.1:8081;
        proxy_http_version 1.1;
        
        # Essential headers
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # WebSocket support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffering
        proxy_buffering off;
        proxy_request_buffering off;
        
        # Don't pass these headers
        proxy_set_header Accept-Encoding "";
    }

    # Health check endpoint
    location /health {
        access_log off;
        proxy_pass http://127.0.0.1:8081/health;
        proxy_set_header Host \$host;
    }

    # Static files caching
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        proxy_pass http://127.0.0.1:8081;
        proxy_set_header Host \$host;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
EOF
            # Enable the site and test
            set +e
            ln -sf /etc/nginx/sites-available/r-panel /etc/nginx/sites-enabled/r-panel 2>> "$LOG_FILE" || true
            nginx -t >> "$LOG_FILE" 2>&1
            local nginx_test_result=$?
            set -e
            
            if [ $nginx_test_result -eq 0 ]; then
                systemctl reload nginx >> "$LOG_FILE" 2>&1 || true
                if [ "$VERBOSE_MODE" = true ]; then
                    log_warning "R-Panel configured with HTTP only (SSL certificate creation failed)"
                fi
            fi
            return 0
        fi
    fi
    
    # Verify files are not empty
    if [ ! -s "$CERT_FILE" ] || [ ! -s "$KEY_FILE" ]; then
        log_error "Certificate files are empty. Recreating..."
        rm -f "$CERT_FILE" "$KEY_FILE" >> "$LOG_FILE" 2>&1
        if ! create_temp_ssl_certificate; then
            log_error "Failed to recreate certificate. See error above."
            return 1
        fi
    fi
    
    # Create Nginx config for R-Panel
    # SSL support is enabled by default - certificate will be setup by certbot
    cat > /etc/nginx/sites-available/r-panel <<EOF
# HTTP server - redirect to HTTPS
server {
    listen 8080;
    listen [::]:8080;
    server_name _;  # Catch-all for all domains

    # Redirect all HTTP traffic to HTTPS
    return 301 https://\$host\$request_uri;
}

# HTTPS server - SSL enabled by default
# Supports multiple domains via SNI (Server Name Indication)
server {
    listen 8080 ssl http2;
    listen [::]:8080 ssl http2;
    server_name _;  # Catch-all for all domains (SNI will handle domain-specific certificates)

    # SSL Certificate paths
    # Default: self-signed certificate (created during installation)
    # Will be updated by certbot when Let's Encrypt certificate is obtained
    ssl_certificate /etc/letsencrypt/live/${R_PANEL_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${R_PANEL_DOMAIN}/privkey.pem;

    # SSL Configuration (modern, secure)
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305';
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Logging
    access_log /var/log/nginx/r-panel-access.log;
    error_log /var/log/nginx/r-panel-error.log;

    # Increase body size for file uploads
    client_max_body_size 100M;
    client_body_buffer_size 128k;

    # Proxy to backend Go application
    location / {
        proxy_pass http://127.0.0.1:8081;
        proxy_http_version 1.1;
        
        # Essential headers
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        
        # WebSocket support (if needed in future)
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Buffering
        proxy_buffering off;
        proxy_request_buffering off;
        
        # Don't pass these headers
        proxy_set_header Accept-Encoding "";
    }

    # Health check endpoint (optional)
    location /health {
        access_log off;
        proxy_pass http://127.0.0.1:8081/health;
        proxy_set_header Host \$host;
    }

    # Static files caching (if served directly)
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        proxy_pass http://127.0.0.1:8081;
        proxy_set_header Host \$host;
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
EOF

    # Enable the site
    set +e
    ln -sf /etc/nginx/sites-available/r-panel /etc/nginx/sites-enabled/r-panel 2>> "$LOG_FILE" || true
    set -e
    
    # Test Nginx config (may fail if SSL cert not ready yet)
    set +e
    nginx -t >> "$LOG_FILE" 2>&1
    local nginx_test_result=$?
    set -e
    
    if [ $nginx_test_result -eq 0 ]; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_success "Nginx configuration for R-Panel created"
        fi
        # Reload Nginx
        systemctl reload nginx >> "$LOG_FILE" 2>&1 || true
    else
        if [ "$VERBOSE_MODE" = true ]; then
            log_warning "Nginx configuration created but test failed"
            log_info "This is normal if SSL certificate is not setup yet"
            log_info "Setup SSL certificate with: certbot --nginx -d ${R_PANEL_DOMAIN}"
        fi
    fi
}

# Setup SSL certificate for R-Panel
setup_ssl_certificate() {
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Setting up SSL certificate for R-Panel..."
    fi
    
    # Get R-Panel domain from config or use server name
    local R_PANEL_DOMAIN="${SERVER_NAME:-panel.example.com}"
    
    # Create temporary self-signed certificate first (so nginx can start)
    create_temp_ssl_certificate
    
    # Skip Let's Encrypt setup if server name is not set or is default
    if [ -z "$SERVER_NAME" ] || [ "$SERVER_NAME" = "default" ]; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_warning "Skipping Let's Encrypt SSL setup: Server name not configured or is 'default'"
            log_info "Using self-signed certificate. To setup Let's Encrypt later, run: certbot --nginx -d your-domain.com"
        fi
        return 0
    fi
    
    # Check if certbot is installed
    if ! command -v certbot &> /dev/null; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_warning "Certbot not found. Using self-signed certificate."
            log_info "Install certbot and run: certbot --nginx -d ${R_PANEL_DOMAIN}"
        fi
        return 0
    fi
    
    # Check if domain resolves (basic DNS check)
    if ! host "$R_PANEL_DOMAIN" &> /dev/null; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_warning "Domain $R_PANEL_DOMAIN does not resolve. Using self-signed certificate."
            log_info "Please configure DNS first, then run: certbot --nginx -d $R_PANEL_DOMAIN"
        fi
        return 0
    fi
    
    # Try to setup Let's Encrypt SSL certificate (non-blocking)
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Attempting to setup Let's Encrypt SSL certificate for $R_PANEL_DOMAIN..."
        log_info "This may require email input. Use SSL_EMAIL environment variable to set email."
    fi
    
    set +e
    trap - ERR
    
    # Determine email for certbot
    local CERTBOT_EMAIL="${SSL_EMAIL:-admin@${R_PANEL_DOMAIN}}"
    
    # Run certbot in non-interactive mode for port 8080
    # Note: certbot --nginx may not work directly for port 8080
    # We'll use certbot certonly with standalone mode or manual configuration
    certbot certonly --nginx \
        -d "$R_PANEL_DOMAIN" \
        --non-interactive \
        --agree-tos \
        --email "$CERTBOT_EMAIL" \
        --nginx-server-root /etc/nginx \
        >> "$LOG_FILE" 2>&1
    
    local certbot_result=$?
    set -e
    trap 'error_exit $LINENO' ERR
    
    if [ $certbot_result -eq 0 ]; then
        # Update nginx config with Let's Encrypt certificate paths
        # Certbot should have already updated the config, but we verify
        if [ -f "/etc/letsencrypt/live/${R_PANEL_DOMAIN}/fullchain.pem" ]; then
            # Reload nginx after SSL setup
            systemctl reload nginx >> "$LOG_FILE" 2>&1 || true
            
            if [ "$VERBOSE_MODE" = true ]; then
                log_success "Let's Encrypt SSL certificate setup successfully for $R_PANEL_DOMAIN"
            fi
        fi
    else
        if [ "$VERBOSE_MODE" = true ]; then
            log_warning "Let's Encrypt SSL certificate setup failed for $R_PANEL_DOMAIN"
            log_info "Using self-signed certificate. This is normal if:"
            log_info "  - DNS is not configured yet"
            log_info "  - Domain does not point to this server"
            log_info "  - Port 80 is not accessible from internet"
            log_info ""
            log_info "To setup Let's Encrypt manually later, run:"
            log_info "  certbot --nginx -d $R_PANEL_DOMAIN"
        fi
    fi
}

# Setup disk quota for client websites
setup_disk_quota() {
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Setting up disk quota for client websites..."
    fi
    
    # Check if quota is already enabled
    if mount | grep -q "usrquota\|grpquota"; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Quota already enabled on filesystem"
        fi
    else
        # Find root filesystem
        ROOT_FS=$(df /var/www | tail -1 | awk '{print $1}')
        ROOT_MOUNT=$(df /var/www | tail -1 | awk '{print $6}')
        
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Root filesystem: $ROOT_FS mounted on $ROOT_MOUNT"
        fi
        
        # Backup fstab
        if [ ! -f /etc/fstab.backup ]; then
            cp /etc/fstab /etc/fstab.backup >> "$LOG_FILE" 2>&1
            if [ "$VERBOSE_MODE" = true ]; then
                log_info "Backed up /etc/fstab to /etc/fstab.backup"
            fi
        fi
        
        # Check if quota options already in fstab
        if grep -q "$ROOT_FS.*usrquota\|grpquota" /etc/fstab; then
            if [ "$VERBOSE_MODE" = true ]; then
                log_info "Quota options already in /etc/fstab"
            fi
        else
            # Add quota options to fstab
            # Find the line for root filesystem and add usrquota,grpquota
            set +e
            sed -i "s|^\($ROOT_FS.*defaults\)|\1,usrquota,grpquota|" /etc/fstab 2>> "$LOG_FILE"
            local sed_result=$?
            set -e
            
            if [ $sed_result -eq 0 ]; then
                if [ "$VERBOSE_MODE" = true ]; then
                    log_success "Added quota options to /etc/fstab"
                fi
                log_warning "Quota options added to /etc/fstab. Remount required:"
                log_warning "  mount -o remount $ROOT_MOUNT"
                log_warning "  Or reboot the server"
            else
                log_warning "Failed to automatically add quota to /etc/fstab"
                log_warning "Please manually add 'usrquota,grpquota' to $ROOT_FS in /etc/fstab"
            fi
        fi
    fi
    
    # Create quota files if they don't exist
    set +e
    touch /aquota.user /aquota.group >> "$LOG_FILE" 2>&1 || true
    chmod 600 /aquota.user /aquota.group >> "$LOG_FILE" 2>&1 || true
    set -e
    
    # Initialize quota database
    set +e
    quotacheck -ugm / >> "$LOG_FILE" 2>&1 || true
    quotaon -ug / >> "$LOG_FILE" 2>&1 || true
    set -e
    
    # Setup default quota for www-data group (all client websites)
    # Default: 10GB soft limit, 11GB hard limit
    set +e
    setquota -g www-data 0 10485760 0 11264 / >> "$LOG_FILE" 2>&1 || true
    # 0 = unlimited inodes, 10485760 = 10GB in KB, 0 = unlimited inodes, 11264 = 11GB in KB
    set -e
    
    # Create quota management script
    cat > /usr/local/bin/r-panel-set-quota <<'EOF'
#!/bin/bash
# R-Panel Quota Management Script
# Usage: r-panel-set-quota <username|groupname> <soft_limit_GB> <hard_limit_GB> [user|group]

if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root"
    exit 1
fi

if [ $# -lt 3 ]; then
    echo "Usage: $0 <username|groupname> <soft_limit_GB> <hard_limit_GB> [user|group]"
    echo "Example: $0 client1 5 6 user"
    echo "Example: $0 www-data 10 11 group"
    exit 1
fi

TARGET=$1
SOFT_GB=$2
HARD_GB=$3
TYPE=${4:-user}

# Convert GB to KB
SOFT_KB=$((SOFT_GB * 1024 * 1024))
HARD_KB=$((HARD_GB * 1024 * 1024))

if [ "$TYPE" = "user" ]; then
    if ! id "$TARGET" &>/dev/null; then
        echo "Error: User $TARGET does not exist"
        exit 1
    fi
    setquota -u "$TARGET" 0 "$SOFT_KB" 0 "$HARD_KB" /
    echo "Set quota for user $TARGET: ${SOFT_GB}GB soft, ${HARD_GB}GB hard"
elif [ "$TYPE" = "group" ]; then
    if ! getent group "$TARGET" &>/dev/null; then
        echo "Error: Group $TARGET does not exist"
        exit 1
    fi
    setquota -g "$TARGET" 0 "$SOFT_KB" 0 "$HARD_KB" /
    echo "Set quota for group $TARGET: ${SOFT_GB}GB soft, ${HARD_GB}GB hard"
else
    echo "Error: Type must be 'user' or 'group'"
    exit 1
fi

# Report quota
if [ "$TYPE" = "user" ]; then
    quota -u "$TARGET"
else
    quota -g "$TARGET"
fi
EOF

    chmod +x /usr/local/bin/r-panel-set-quota >> "$LOG_FILE" 2>&1
    
    # Create quota report script
    cat > /usr/local/bin/r-panel-quota-report <<'EOF'
#!/bin/bash
# R-Panel Quota Report Script
# Shows quota usage for all users and groups

echo "=== User Quotas ==="
repquota -u / 2>/dev/null | grep -v "^$" | head -20

echo ""
echo "=== Group Quotas ==="
repquota -g / 2>/dev/null | grep -v "^$" | head -20

echo ""
echo "=== www-data Group Quota (Client Websites) ==="
quota -g www-data 2>/dev/null || echo "No quota set for www-data group"
EOF

    chmod +x /usr/local/bin/r-panel-quota-report >> "$LOG_FILE" 2>&1
    
    if [ "$VERBOSE_MODE" = true ]; then
        log_success "Disk quota system configured"
        log_info "Default quota for www-data group: 10GB soft, 11GB hard"
        log_info "Use 'r-panel-set-quota <user|group> <soft_GB> <hard_GB> [user|group]' to set quota"
        log_info "Use 'r-panel-quota-report' to view quota usage"
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

# Setup MySQL database for R-Panel
setup_mysql_database() {
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Setting up MySQL database for R-Panel..."
    fi
    
    # Generate secure random password for MySQL user
    MYSQL_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    # Generate secure random password for admin user
    ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-20)
    
    # Check if MariaDB/MySQL is running
    if ! systemctl is-active --quiet mariadb && ! systemctl is-active --quiet mysql; then
        log_warning "MariaDB/MySQL is not running. Starting service..."
        systemctl start mariadb >> "$LOG_FILE" 2>&1 || systemctl start mysql >> "$LOG_FILE" 2>&1
        sleep 2
    fi
    
    # Try to connect to MySQL as root (try without password first, then with sudo)
    set +e
    trap - ERR
    
    # Try connecting without password (fresh install)
    mysql -u root -e "SELECT 1" >> "$LOG_FILE" 2>&1
    local mysql_connect_result=$?
    
    if [ $mysql_connect_result -ne 0 ]; then
        # Try with sudo (some systems require sudo for root MySQL access)
        sudo mysql -u root -e "SELECT 1" >> "$LOG_FILE" 2>&1
        mysql_connect_result=$?
        MYSQL_CMD="sudo mysql"
    else
        MYSQL_CMD="mysql"
    fi
    
    set -e
    trap 'error_exit $LINENO' ERR
    
    if [ $mysql_connect_result -ne 0 ]; then
        log_warning "Cannot connect to MySQL as root without password"
        log_info "You will need to setup MySQL database manually:"
        log_info "  1. Run: mysql_secure_installation"
        log_info "  2. Login: mysql -u root -p"
        log_info "  3. Create database: CREATE DATABASE rpanel;"
        log_info "  4. Create user: CREATE USER 'rpanel'@'localhost' IDENTIFIED BY 'password';"
        log_info "  5. Grant privileges: GRANT ALL ON rpanel.* TO 'rpanel'@'localhost';"
        log_info "  6. Update /usr/local/r-panel/configs/config.yaml with credentials"
        # Still save admin password even if MySQL setup fails
        echo "$ADMIN_PASSWORD" > /tmp/r-panel-admin-password.txt
        chmod 600 /tmp/r-panel-admin-password.txt
        return 0
    fi
    
    # Create database if not exists
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Creating database 'rpanel'..."
    fi
    
    $MYSQL_CMD -u root <<EOF >> "$LOG_FILE" 2>&1
CREATE DATABASE IF NOT EXISTS rpanel CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
EOF
    
    # Check if user already exists
    USER_EXISTS=$($MYSQL_CMD -u root -sN -e "SELECT COUNT(*) FROM mysql.user WHERE User='rpanel' AND Host='localhost';" 2>> "$LOG_FILE" || echo "0")
    
    if [ "$USER_EXISTS" = "0" ]; then
        # Create user
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Creating MySQL user 'rpanel'..."
        fi
        
        $MYSQL_CMD -u root <<EOF >> "$LOG_FILE" 2>&1
CREATE USER IF NOT EXISTS 'rpanel'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON rpanel.* TO 'rpanel'@'localhost';
FLUSH PRIVILEGES;
EOF
        
        if [ "$VERBOSE_MODE" = true ]; then
            log_success "MySQL user 'rpanel' created with generated password"
        fi
    else
        # User exists, check if we need to update password
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "MySQL user 'rpanel' already exists"
        fi
        
        # Try to update password (may fail if user has different auth method)
        $MYSQL_CMD -u root <<EOF >> "$LOG_FILE" 2>&1 || true
ALTER USER 'rpanel'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';
FLUSH PRIVILEGES;
EOF
        
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Updated password for existing user 'rpanel'"
        fi
    fi
    
    # Verify connection with new credentials
    set +e
    mysql -u rpanel -p"${MYSQL_PASSWORD}" -e "SELECT 1" rpanel >> "$LOG_FILE" 2>&1
    local verify_result=$?
    set -e
    
    if [ $verify_result -eq 0 ]; then
        if [ "$VERBOSE_MODE" = true ]; then
            log_success "MySQL database setup verified successfully"
        fi
        
        # Save passwords to temporary files
        echo "$MYSQL_PASSWORD" > /tmp/r-panel-mysql-password.txt
        chmod 600 /tmp/r-panel-mysql-password.txt
        
        echo "$ADMIN_PASSWORD" > /tmp/r-panel-admin-password.txt
        chmod 600 /tmp/r-panel-admin-password.txt
        
        # Update config.yaml if it exists
        if [ -f /usr/local/r-panel/configs/config.yaml ]; then
            if [ "$VERBOSE_MODE" = true ]; then
                log_info "Updating config.yaml with MySQL credentials and admin password..."
            fi
            
            # Update MySQL settings - use more precise sed patterns
            sed -i "s|host:.*mysql.*|host: \"localhost\"|" /usr/local/r-panel/configs/config.yaml
            sed -i "s|host: \"mysql\"|host: \"localhost\"|" /usr/local/r-panel/configs/config.yaml
            
            # Update MySQL username, password, and database
            sed -i "/^  mysql:/,/^[^ ]/ {
                s|username:.*|username: \"rpanel\"|
                s|password:.*|password: \"${MYSQL_PASSWORD}\"|
                s|database:.*|database: \"rpanel\"|
            }" /usr/local/r-panel/configs/config.yaml
            
            # Update admin password in default_user section
            sed -i '/^default_user:/,/^[^ ]/ {
                s/^  password:.*/  password: "'"${ADMIN_PASSWORD}"'" # Auto-generated - CHANGE ON FIRST LOGIN/
            }' /usr/local/r-panel/configs/config.yaml
            
            if [ "$VERBOSE_MODE" = true ]; then
                log_success "config.yaml updated with MySQL credentials and admin password"
            fi
        else
            # Create config.yaml from example if it doesn't exist
            if [ -f /usr/local/r-panel/configs/config.example.yaml ]; then
                cp /usr/local/r-panel/configs/config.example.yaml /usr/local/r-panel/configs/config.yaml >> "$LOG_FILE" 2>&1
                
                # Update MySQL settings
                sed -i "s|host:.*|host: \"localhost\"|" /usr/local/r-panel/configs/config.yaml
                sed -i "/^  mysql:/,/^[^ ]/ {
                    s|username:.*|username: \"rpanel\"|
                    s|password:.*|password: \"${MYSQL_PASSWORD}\"|
                    s|database:.*|database: \"rpanel\"|
                }" /usr/local/r-panel/configs/config.yaml
                
                # Update admin password
                sed -i '/^default_user:/,/^[^ ]/ {
                    s/^  password:.*/  password: "'"${ADMIN_PASSWORD}"'" # Auto-generated - CHANGE ON FIRST LOGIN/
                }' /usr/local/r-panel/configs/config.yaml
                
                if [ "$VERBOSE_MODE" = true ]; then
                    log_success "Created config.yaml from example with MySQL credentials and admin password"
                fi
            fi
        fi
        
        # Display passwords (user needs to save them)
        echo ""
        log_warning "IMPORTANT: Save these credentials:"
        echo "  MySQL Database:"
        echo "    Username: rpanel"
        echo "    Password: ${MYSQL_PASSWORD}"
        echo "    Database: rpanel"
        echo ""
        echo "  R-Panel Admin Login:"
        echo "    Username: admin"
        echo "    Password: ${ADMIN_PASSWORD}"
        echo ""
        echo "  (Passwords also saved in /tmp/r-panel-*-password.txt - will be deleted on reboot)"
        echo ""
        
    else
        log_warning "Failed to verify MySQL connection with new credentials"
        log_info "You may need to setup database manually"
        # Still save admin password
        echo "$ADMIN_PASSWORD" > /tmp/r-panel-admin-password.txt
        chmod 600 /tmp/r-panel-admin-password.txt
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
    
    # Build frontend assets if frontend directory exists
    if [ -d "frontend" ] && [ -f "frontend/package.json" ]; then
        log_info "Building frontend assets from frontend/ directory..."
        
        cd frontend
        
        # Install frontend dependencies
        log_info "Installing frontend dependencies..."
        
        # Temporarily disable exit on error to check npm install result
        set +e
        trap - ERR
        npm install >> "$LOG_FILE" 2>&1
        local npm_install_result=$?
        set -e
        trap 'error_exit $LINENO' ERR
        
        if [ $npm_install_result -ne 0 ]; then
            log_error "Frontend npm install failed with exit code $npm_install_result"
            log_error "Check log file for details: $LOG_FILE"
            cd "$SOURCE_DIR"
            exit 1
        fi
        
        log_success "Frontend dependencies installed successfully"
        
        # Setup .env.local for production build
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Setting up frontend environment variables..."
        fi
        
        # Determine API URL based on SERVER_NAME
        local API_URL="http://localhost:8080/api"
        if [ -n "$SERVER_NAME" ] && [ "$SERVER_NAME" != "default" ]; then
            # Use HTTPS for production (SSL will be setup during installation or after)
            API_URL="https://${SERVER_NAME}:8080/api"
        fi
        
        # Copy .env.local.example to .env.local if it exists
        if [ -f ".env.local.example" ]; then
            if [ "$VERBOSE_MODE" = true ]; then
                log_info "Copying .env.local.example to .env.local..."
            fi
            cp .env.local.example .env.local >> "$LOG_FILE" 2>&1
        else
            # Create .env.local if .env.local.example doesn't exist
            if [ "$VERBOSE_MODE" = true ]; then
                log_info "Creating .env.local file..."
            fi
            touch .env.local >> "$LOG_FILE" 2>&1
        fi
        
        # Update or add VITE_API_URL in .env.local
        if grep -q "^VITE_API_URL=" .env.local 2>/dev/null; then
            # Update existing VITE_API_URL
            if [ "$VERBOSE_MODE" = true ]; then
                log_info "Updating VITE_API_URL in .env.local to: $API_URL"
            fi
            sed -i "s|^VITE_API_URL=.*|VITE_API_URL=$API_URL|" .env.local
        else
            # Add VITE_API_URL if it doesn't exist
            if [ "$VERBOSE_MODE" = true ]; then
                log_info "Adding VITE_API_URL to .env.local: $API_URL"
            fi
            echo "VITE_API_URL=$API_URL" >> .env.local
        fi
        
        if [ "$VERBOSE_MODE" = true ]; then
            log_success "Frontend environment configured: VITE_API_URL=$API_URL"
        fi
        
        # Check if build script exists and build
        if grep -q '"build"' package.json; then
            log_info "Building frontend assets (output to backend/web/dist)..."
            
            # Temporarily disable exit on error to check npm build result
            set +e
            trap - ERR
            npm run build >> "$LOG_FILE" 2>&1
            local npm_build_result=$?
            set -e
            trap 'error_exit $LINENO' ERR
            
            if [ $npm_build_result -ne 0 ]; then
                log_error "Frontend build failed with exit code $npm_build_result"
                log_error "Check log file for details: $LOG_FILE"
                cd "$SOURCE_DIR"
                exit 1
            fi
            
            # Verify build output exists and has files
            if [ ! -d "../backend/web/dist" ]; then
                log_error "Frontend build completed but backend/web/dist directory not found"
                log_error "Expected build output at: $SOURCE_DIR/backend/web/dist"
                cd "$SOURCE_DIR"
                exit 1
            fi
            
            # Check if index.html exists in dist directory
            if [ ! -f "../backend/web/dist/index.html" ]; then
                log_error "Frontend build completed but index.html not found in backend/web/dist"
                log_error "Build may have failed silently"
                cd "$SOURCE_DIR"
                exit 1
            fi
            
            # Count files in dist to verify build succeeded
            local dist_file_count=$(find "../backend/web/dist" -type f | wc -l)
            if [ "$dist_file_count" -eq 0 ]; then
                log_error "Frontend build directory is empty"
                cd "$SOURCE_DIR"
                exit 1
            fi
            
            log_success "Frontend built successfully to backend/web/dist ($dist_file_count files)"
        else
            log_error "No build script found in frontend/package.json"
            cd "$SOURCE_DIR"
            exit 1
        fi
        
        # Return to source directory
        cd "$SOURCE_DIR"
    else
        if [ "$VERBOSE_MODE" = true ]; then
            log_warning "Frontend directory or package.json not found, skipping frontend build"
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
    
    # Copy compiled binary and required files (with error handling)
    set +e
    if [ -f "r-panel" ]; then
        cp -f r-panel /usr/local/r-panel/ >> "$LOG_FILE" 2>&1
        local cp_result=$?
        if [ $cp_result -ne 0 ]; then
            log_warning "Failed to copy r-panel binary. Continuing..."
        fi
    else
        log_error "r-panel binary not found in current directory"
        cd "$SOURCE_DIR" >> "$LOG_FILE" 2>&1
        return 1
    fi
    set -e
    
    # Copy static files, templates, config, etc. (check both root and backend)
    for dir in static templates public assets config; do
        set +e
        if [ -d "$dir" ]; then
            cp -r "$dir" /usr/local/r-panel/ >> "$LOG_FILE" 2>&1 || true
        elif [ -d "backend/$dir" ]; then
            cp -r "backend/$dir" /usr/local/r-panel/ >> "$LOG_FILE" 2>&1 || true
        fi
        set -e
    done
    
    # Copy web directory separately with verification (critical for frontend)
    set +e
    trap - ERR
    if [ -d "backend/web" ]; then
        cp -r "backend/web" /usr/local/r-panel/ >> "$LOG_FILE" 2>&1
        local web_copy_result=$?
    elif [ -d "web" ]; then
        cp -r "web" /usr/local/r-panel/ >> "$LOG_FILE" 2>&1
        local web_copy_result=$?
    else
        log_error "web directory not found in source directory"
        local web_copy_result=1
    fi
    set -e
    trap 'error_exit $LINENO' ERR
    
    if [ $web_copy_result -ne 0 ]; then
        log_error "Failed to copy web directory to /usr/local/r-panel/"
        exit 1
    fi
    
    # Verify web/dist exists after copy
    if [ ! -d "/usr/local/r-panel/web/dist" ]; then
        log_error "web/dist directory not found in /usr/local/r-panel after copy"
        exit 1
    fi
    
    # Verify index.html exists
    if [ ! -f "/usr/local/r-panel/web/dist/index.html" ]; then
        log_error "index.html not found in /usr/local/r-panel/web/dist"
        log_error "Frontend build may not have completed successfully"
        exit 1
    fi
    
    local dist_file_count=$(find "/usr/local/r-panel/web/dist" -type f | wc -l)
    log_success "Web directory copied successfully ($dist_file_count files in dist)"
    
    # Copy backend-specific directories
    set +e
    if [ -d "backend/templates" ]; then
        cp -r backend/templates /usr/local/r-panel/ >> "$LOG_FILE" 2>&1 || true
    fi
    
    # Ensure configs directory exists
    mkdir -p /usr/local/r-panel/configs >> "$LOG_FILE" 2>&1
    
    # Copy configs directory if exists
    if [ -d "backend/configs" ]; then
        cp -r backend/configs/* /usr/local/r-panel/configs/ >> "$LOG_FILE" 2>&1 || true
    fi
    set -e
    
    # Create config.yaml from example if needed (in configs/ directory)
    set +e
    if [ -f /usr/local/r-panel/configs/config.example.yaml ] && [ ! -f /usr/local/r-panel/configs/config.yaml ]; then
        cp /usr/local/r-panel/configs/config.example.yaml /usr/local/r-panel/configs/config.yaml >> "$LOG_FILE" 2>&1
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Created config.yaml from config.example.yaml"
        fi
    fi
    
    # Also check if config.yaml exists in root and copy to configs/ if needed
    if [ -f /usr/local/r-panel/config.yaml ] && [ ! -f /usr/local/r-panel/configs/config.yaml ]; then
        cp /usr/local/r-panel/config.yaml /usr/local/r-panel/configs/config.yaml >> "$LOG_FILE" 2>&1
        if [ "$VERBOSE_MODE" = true ]; then
            log_info "Copied config.yaml from root to configs/"
        fi
    fi
    
    # Verify config.yaml exists in configs/ directory
    if [ ! -f /usr/local/r-panel/configs/config.yaml ]; then
        log_error "config.yaml not found in /usr/local/r-panel/configs/"
        log_error "Please create it manually or ensure config.example.yaml exists"
    else
        if [ "$VERBOSE_MODE" = true ]; then
            log_success "Config file verified at /usr/local/r-panel/configs/config.yaml"
        fi
    fi
    set -e
    
    # Set proper permissions (owned by rpanel user)
    set +e
    chown -R rpanel:rpanel /usr/local/r-panel >> "$LOG_FILE" 2>&1 || true
    chmod -R 755 /usr/local/r-panel >> "$LOG_FILE" 2>&1 || true
    chmod +x /usr/local/r-panel/r-panel >> "$LOG_FILE" 2>&1 || true
    set -e
    
    # Create data directories if needed
    set +e
    mkdir -p /usr/local/r-panel/{data,logs,uploads} >> "$LOG_FILE" 2>&1 || true
    chown -R rpanel:rpanel /usr/local/r-panel/{data,logs,uploads} >> "$LOG_FILE" 2>&1 || true
    chmod -R 775 /usr/local/r-panel/{data,logs,uploads} >> "$LOG_FILE" 2>&1 || true
    set -e
    
    # Create symbolic link for easy access
    set +e
    ln -sf /usr/local/r-panel/r-panel /usr/local/bin/r-panel >> "$LOG_FILE" 2>&1 || true
    set -e
    
    # Create systemd service for R-Panel
    if [ "$VERBOSE_MODE" = true ]; then
        log_info "Creating R-Panel systemd service..."
    fi
    
    cat > /etc/systemd/system/r-panel.service <<EOF
[Unit]
Description=R-Panel Hosting Control Panel (Go)
After=network.target mysql.service redis.service nginx.service
Requires=mysql.service

[Service]
Type=simple
User=rpanel
Group=rpanel
WorkingDirectory=/usr/local/r-panel
Environment="PORT=8081"
Environment="GIN_MODE=release"
ExecStart=/usr/local/r-panel/r-panel
Restart=always
RestartSec=3
StandardOutput=append:/usr/local/r-panel/logs/r-panel.log
StandardError=append:/usr/local/r-panel/logs/r-panel-error.log

# Security (compatible with systems that have limited namespace support)
NoNewPrivileges=true
# Removed PrivateTmp, ProtectSystem, ProtectHome, ReadOnlyPaths, and ReadWritePaths
# to avoid namespace errors (exit code 226/NAMESPACE) on systems without namespace support
# File permissions are still enforced via User/Group settings above

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    set +e
    systemctl daemon-reload >> "$LOG_FILE" 2>&1 || true
    set -e
    
    # Enable and start R-Panel service
    set +e
    systemctl enable r-panel >> "$LOG_FILE" 2>&1 || log_warning "Failed to enable r-panel service"
    systemctl start r-panel >> "$LOG_FILE" 2>&1 || log_warning "Failed to start r-panel service"
    set -e
    
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
    echo "  • /usr/local/r-panel (R-Panel application and files)"
    echo "  • /var/www/r-panel (web files)"
    echo "  • /var/www/vhosts (user websites)"
    
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
    
    echo "MySQL Database Setup:"
    if [ -f /tmp/r-panel-mysql-password.txt ]; then
        MYSQL_PASS=$(cat /tmp/r-panel-mysql-password.txt)
        echo "  ✓ Database: rpanel"
        echo "  ✓ Username: rpanel"
        echo "  ✓ Password: ${MYSQL_PASS}"
    else
        echo "  ⚠  Database setup may need manual configuration"
        echo "     Run: mysql_secure_installation"
        echo "     Then create database and user manually"
    fi
    echo ""
    
    echo "R-Panel Admin Login:"
    if [ -f /tmp/r-panel-admin-password.txt ]; then
        ADMIN_PASS=$(cat /tmp/r-panel-admin-password.txt)
        echo "  ✓ Username: admin"
        echo "  ✓ Password: ${ADMIN_PASS}"
        echo "  ⚠  IMPORTANT: Change this password on first login!"
    else
        echo "  ⚠  Admin password may need manual configuration"
        echo "     Default: username=admin, password=changeme"
    fi
    echo ""
    if [ -f /tmp/r-panel-mysql-password.txt ] || [ -f /tmp/r-panel-admin-password.txt ]; then
        echo "  ⚠  IMPORTANT: Save all passwords! They're stored in /tmp/r-panel-*-password.txt"
        echo "     (These files will be deleted on reboot)"
    fi
    echo ""
    
    echo "Next Steps:"
    
    if [ -d /usr/local/r-panel ]; then
        echo "  1. Configure R-Panel (if needed):"
        echo "     - Edit: nano /usr/local/r-panel/configs/config.yaml"
        echo "     - Config should already be set with auto-generated credentials"
        echo "  2. Setup SSL certificate for R-Panel (after DNS is configured):"
        if [ -n "$SERVER_NAME" ] && [ "$SERVER_NAME" != "default" ]; then
            echo "     certbot --nginx -d ${SERVER_NAME} --email your-email@example.com"
        else
            echo "     certbot --nginx -d panel.example.com --email your-email@example.com"
        fi
        echo "     Note: If certbot fails, temporarily comment SSL lines in:"
        echo "     /etc/nginx/sites-available/r-panel"
        if [ ! -f /tmp/r-panel-mysql-password.txt ]; then
            echo "  3. Run: mysql_secure_installation"
            echo "  4. Create database for R-Panel:"
            echo "     mysql -e \"CREATE DATABASE rpanel;\""
            echo "     mysql -e \"CREATE USER 'rpanel'@'localhost' IDENTIFIED BY 'your_password';\""
            echo "     mysql -e \"GRANT ALL ON rpanel.* TO 'rpanel'@'localhost';\""
            echo "  5. Update database config in R-Panel configuration file"
            echo "  6. Restart services:"
        else
            echo "  3. Restart services (if needed):"
        fi
        echo "     systemctl restart r-panel nginx"
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
        echo "  • Application logs: tail -f /usr/local/r-panel/logs/*.log"
        echo "  • Restart R-Panel: systemctl restart r-panel"
    fi
    
    echo "  • View logs: tail -f /usr/local/r-panel/logs/*.log"
    echo "  • Nginx test: nginx -t"
    echo ""
    echo "Disk Quota Management:"
    echo "  • Set quota: r-panel-set-quota <user|group> <soft_GB> <hard_GB> [user|group]"
    echo "    Example: r-panel-set-quota client1 5 6 user"
    echo "    Example: r-panel-set-quota www-data 10 11 group"
    echo "  • View quota report: r-panel-quota-report"
    echo "  • Check user quota: quota -u <username>"
    echo "  • Check group quota: quota -g <groupname>"
    echo "  • Note: If quota not working, remount filesystem:"
    echo "    mount -o remount /"
    echo "    quotaon -ug /"
    
    if [ -d /usr/local/r-panel ]; then
        echo "  • R-Panel CLI: r-panel --help"
    fi
    
    echo ""
    echo "Firewall Ports:"
    echo "  • 22   - SSH"
    echo "  • 80   - HTTP (User Websites)"
    echo "  • 443  - HTTPS (User Websites)"
    echo "  • 8080 - R-Panel Control Panel"
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
    
    # Wait for apt locks before starting installation
    if ! wait_for_apt_lock; then
        log_error "Cannot proceed with installation. Please resolve apt lock issues and try again."
        exit 1
    fi
    
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
        # Wait for apt locks before installing debconf-utils
        wait_for_apt_lock
        apt-get update -qq >> "$LOG_FILE" 2>&1
        wait_for_apt_lock
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
    install_certbot
    install_php
    install_mariadb
    install_redis
    install_nodejs
    install_go
    install_composer
    
    # Configuration steps
    configure_firewall
    configure_fail2ban
    create_rpanel_user
    create_rpanel_structure
    configure_rpanel_permissions
    create_nginx_config
    create_rpanel_nginx_config
    setup_ssl_certificate
    setup_disk_quota
    optimize_php_fpm
    create_swap
    
    # Setup MySQL database for R-Panel (before compiling)
    setup_mysql_database
    
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
