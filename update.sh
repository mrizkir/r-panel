#!/bin/bash

#==============================================================================
# R-Panel Update Script
# Description: Update script for R-Panel hosting control panel
#
# Usage:
#   ./update.sh                      # Interactive menu
#   ./update.sh --binary             # Update binary only
#   ./update.sh --service            # Update service only
#   ./update.sh --frontend           # Update frontend only
#   ./update.sh --all                # Update binary, service, and frontend
#   ./update.sh --verbose            # Show detailed output
#   ./update.sh --help               # Show help message
#==============================================================================

# Auto re-execute with bash if not running with bash
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/usr/local/r-panel"
BINARY_PATH="$INSTALL_DIR/r-panel"
SERVICE_FILE="/etc/systemd/system/r-panel.service"
BACKUP_DIR="$INSTALL_DIR/backups"
LOG_FILE="/tmp/r-panel-update-$(date +%Y%m%d_%H%M%S).log"
VERBOSE_MODE=false
UPDATE_BINARY=false
UPDATE_SERVICE=false
UPDATE_FRONTEND=false

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

# Show help
show_help() {
    cat << EOF
R-Panel Update Script

Usage:
    ./update.sh [OPTIONS]

Options:
    --binary, -b        Update binary only
    --service, -s       Update service only
    --frontend, -f      Update frontend only
    --all, -a           Update binary, service, and frontend
    --verbose, -v       Show detailed output
    --help, -h          Show this help message

Examples:
    ./update.sh                    # Interactive menu
    ./update.sh --binary           # Update binary only
    ./update.sh --service          # Update service only
    ./update.sh --frontend         # Update frontend only
    ./update.sh --all --verbose    # Update all with verbose output

EOF
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root or with sudo"
        exit 1
    fi
}

# Check if R-Panel is installed
check_installation() {
    if [ ! -f "$BINARY_PATH" ]; then
        log_error "R-Panel binary not found at $BINARY_PATH"
        log_error "Please run install.sh first"
        exit 1
    fi
    
    if [ ! -f "$SERVICE_FILE" ]; then
        log_warning "Service file not found at $SERVICE_FILE"
        UPDATE_SERVICE=true
    fi
}

# Get current directory (should be r-panel repo root)
get_source_dir() {
    # Try to find the source directory
    if [ -f "install.sh" ] && [ -d "backend" ]; then
        SOURCE_DIR="$(pwd)"
        return 0
    fi
    
    # Try parent directory
    if [ -f "../install.sh" ] && [ -d "../backend" ]; then
        SOURCE_DIR="$(cd .. && pwd)"
        return 0
    fi
    
    # Try common locations
    if [ -d "/opt/r-panel" ] && [ -f "/opt/r-panel/install.sh" ]; then
        SOURCE_DIR="/opt/r-panel"
        return 0
    fi
    
    log_error "Cannot find R-Panel source directory"
    log_error "Please run this script from the r-panel repository root"
    exit 1
}

# Backup current binary
backup_binary() {
    if [ ! -f "$BINARY_PATH" ]; then
        return 0
    fi
    
    log_info "Backing up current binary..."
    
    mkdir -p "$BACKUP_DIR" || true
    local backup_file="$BACKUP_DIR/r-panel-$(date +%Y%m%d_%H%M%S).backup"
    cp "$BINARY_PATH" "$backup_file" || {
        log_warning "Failed to backup binary, continuing anyway..."
        return 0
    }
    
    log_success "Binary backed up to: $backup_file"
}

# Build new binary
build_binary() {
    log_info "Building new binary..."
    
    get_source_dir
    
    # Determine build directory
    BUILD_DIR="$SOURCE_DIR"
    if [ -f "$SOURCE_DIR/backend/go.mod" ]; then
        BUILD_DIR="$SOURCE_DIR/backend"
        MAIN_PATH="./cmd/server"
    elif [ -f "$SOURCE_DIR/go.mod" ]; then
        BUILD_DIR="$SOURCE_DIR"
        MAIN_PATH="./cmd/server"
    else
        log_error "Cannot find go.mod file"
        exit 1
    fi
    
    cd "$BUILD_DIR"
    
    # Check if Go is installed
    if ! command -v go &> /dev/null; then
        log_error "Go is not installed. Please install Go first."
        exit 1
    fi
    
    # Download dependencies
    log_info "Downloading dependencies..."
    if [ "$VERBOSE_MODE" = true ]; then
        go mod download
    else
        go mod download >> "$LOG_FILE" 2>&1
    fi
    
    # Build binary
    log_info "Compiling Go binary..."
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
        -ldflags="-s -w" \
        -o r-panel \
        $MAIN_PATH >> "$LOG_FILE" 2>&1
    
    if [ ! -f "r-panel" ]; then
        log_error "Build failed. Check logs: $LOG_FILE"
        cd - >> "$LOG_FILE" 2>&1
        exit 1
    fi
    
    # Move binary to source directory
    if [ "$BUILD_DIR" != "$SOURCE_DIR" ]; then
        mv r-panel "$SOURCE_DIR/r-panel" >> "$LOG_FILE" 2>&1
        cd "$SOURCE_DIR"
    fi
    
    log_success "Binary built successfully"
    cd - >> "$LOG_FILE" 2>&1
}

# Install new binary
install_binary() {
    log_info "Installing new binary..."
    
    get_source_dir
    
    if [ ! -f "$SOURCE_DIR/r-panel" ]; then
        log_error "Binary not found at $SOURCE_DIR/r-panel"
        exit 1
    fi
    
    # Stop service before replacing binary
    log_info "Stopping R-Panel service..."
    systemctl stop r-panel 2>/dev/null || log_warning "Service was not running"
    
    # Copy new binary
    cp -f "$SOURCE_DIR/r-panel" "$BINARY_PATH" || {
        log_error "Failed to copy binary"
        systemctl start r-panel 2>/dev/null || true
        exit 1
    }
    
    # Set permissions
    chown rpanel:rpanel "$BINARY_PATH" || true
    chmod +x "$BINARY_PATH" || true
    
    log_success "Binary installed successfully"
}

# Build frontend
build_frontend() {
    log_info "Building frontend assets..."
    
    get_source_dir
    
    # Check if frontend directory exists
    if [ ! -d "$SOURCE_DIR/frontend" ] || [ ! -f "$SOURCE_DIR/frontend/package.json" ]; then
        log_error "Frontend directory or package.json not found"
        log_error "Expected: $SOURCE_DIR/frontend/package.json"
        exit 1
    fi
    
    # Remove old dist directory before building
    if [ -d "$SOURCE_DIR/backend/web/dist" ]; then
        log_info "Removing old backend/web/dist directory..."
        rm -rf "$SOURCE_DIR/backend/web/dist" >> "$LOG_FILE" 2>&1 || true
    fi
    
    cd "$SOURCE_DIR/frontend"
    
    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed. Please install Node.js first."
        exit 1
    fi
    
    # Check for package manager (prefer yarn, fallback to npm)
    local PACKAGE_MANAGER="npm"
    local INSTALL_CMD="install"
    local BUILD_CMD="run build"
    
    if command -v yarn &> /dev/null; then
        PACKAGE_MANAGER="yarn"
        INSTALL_CMD="install"
        BUILD_CMD="build"
        log_info "Using yarn as package manager"
    else
        log_info "Using npm as package manager"
    fi
    
    # Install dependencies
    log_info "Installing frontend dependencies..."
    set +e
    if [ "$VERBOSE_MODE" = true ]; then
        $PACKAGE_MANAGER $INSTALL_CMD
    else
        $PACKAGE_MANAGER $INSTALL_CMD >> "$LOG_FILE" 2>&1
    fi
    local install_result=$?
    set -e
    
    if [ $install_result -ne 0 ]; then
        log_error "Frontend dependency installation failed"
        log_error "Check log file for details: $LOG_FILE"
        cd - >> "$LOG_FILE" 2>&1
        exit 1
    fi
    
    log_success "Frontend dependencies installed successfully"
    
    # Build frontend
    log_info "Building frontend assets (output to backend/web/dist)..."
    set +e
    if [ "$VERBOSE_MODE" = true ]; then
        $PACKAGE_MANAGER $BUILD_CMD
    else
        $PACKAGE_MANAGER $BUILD_CMD >> "$LOG_FILE" 2>&1
    fi
    local build_result=$?
    set -e
    
    if [ $build_result -ne 0 ]; then
        log_error "Frontend build failed"
        log_error "Check log file for details: $LOG_FILE"
        cd - >> "$LOG_FILE" 2>&1
        exit 1
    fi
    
    # Verify build output
    if [ ! -d "../backend/web/dist" ]; then
        log_error "Frontend build completed but backend/web/dist directory not found"
        log_error "Expected build output at: $SOURCE_DIR/backend/web/dist"
        cd - >> "$LOG_FILE" 2>&1
        exit 1
    fi
    
    if [ ! -f "../backend/web/dist/index.html" ]; then
        log_error "Frontend build completed but index.html not found in backend/web/dist"
        log_error "Build may have failed silently"
        cd - >> "$LOG_FILE" 2>&1
        exit 1
    fi
    
    # Count files in dist to verify build succeeded
    local dist_file_count=$(find "../backend/web/dist" -type f | wc -l)
    if [ "$dist_file_count" -eq 0 ]; then
        log_error "Frontend build directory is empty"
        cd - >> "$LOG_FILE" 2>&1
        exit 1
    fi
    
    log_success "Frontend built successfully to backend/web/dist ($dist_file_count files)"
    cd - >> "$LOG_FILE" 2>&1
}

# Update service file
update_service() {
    log_warning "Service update is currently disabled"
    return 0
    
    # DISABLED - Uncomment below to enable service update
    # log_info "Updating systemd service..."
    # 
    # cat > "$SERVICE_FILE" <<EOF
    # [Unit]
    # Description=R-Panel Hosting Control Panel (Go)
    # After=network.target mysql.service redis.service nginx.service
    # Requires=mysql.service
    # 
    # [Service]
    # Type=simple
    # User=rpanel
    # Group=rpanel
    # WorkingDirectory=/usr/local/r-panel
    # Environment="PORT=8081"
    # Environment="GIN_MODE=release"
    # ExecStart=/usr/local/r-panel/r-panel
    # Restart=always
    # RestartSec=3
    # StandardOutput=append:/usr/local/r-panel/logs/r-panel.log
    # StandardError=append:/usr/local/r-panel/logs/r-panel-error.log
    # 
    # # Security
    # NoNewPrivileges=true
    # 
    # [Install]
    # WantedBy=multi-user.target
    # EOF
    # 
    # # Reload systemd
    # log_info "Reloading systemd..."
    # systemctl daemon-reload || {
    #     log_error "Failed to reload systemd"
    #     exit 1
    # }
    # 
    # log_success "Service file updated successfully"
}

# Restart service
restart_service() {
    log_info "Restarting R-Panel service..."
    
    systemctl restart r-panel || {
        log_error "Failed to restart service"
        exit 1
    }
    
    # Wait a moment for service to start
    sleep 2
    
    # Check if service is running
    if systemctl is-active --quiet r-panel; then
        log_success "Service started successfully"
    else
        log_warning "Service may not be running. Check status with: systemctl status r-panel"
        log_warning "Check logs with: journalctl -u r-panel -n 50"
    fi
}

# Update binary
update_binary_function() {
    log_info "=== Updating R-Panel Binary ==="
    
    backup_binary
    build_binary
    install_binary
    restart_service
    
    log_success "=== Binary Update Complete ==="
}

# Update service
update_service_function() {
    log_info "=== Updating R-Panel Service ==="
    
    update_service
    restart_service
    
    log_success "=== Service Update Complete ==="
}

# Update frontend
update_frontend_function() {
    log_info "=== Updating R-Panel Frontend ==="
    
    build_frontend
    
    # Restart service to serve new frontend files
    restart_service
    
    log_success "=== Frontend Update Complete ==="
}

# Interactive menu
show_menu() {
    echo ""
    echo "=========================================="
    echo "  R-Panel Update Script"
    echo "=========================================="
    echo ""
    echo "What would you like to update?"
    echo ""
    echo "  1) Update Binary Only"
    echo "  2) Update Service Only"
    echo "  3) Update Frontend Only"
    echo "  4) Update Both (Binary + Service)"
    echo "  5) Update All (Binary + Service + Frontend)"
    echo "  6) Exit"
    echo ""
    read -p "Enter your choice [1-6]: " choice
    
    case $choice in
        1)
            UPDATE_BINARY=true
            ;;
        2)
            UPDATE_SERVICE=true
            ;;
        3)
            UPDATE_FRONTEND=true
            ;;
        4)
            UPDATE_BINARY=true
            UPDATE_SERVICE=true
            ;;
        5)
            UPDATE_BINARY=true
            UPDATE_SERVICE=true
            UPDATE_FRONTEND=true
            ;;
        6)
            log_info "Exiting..."
            exit 0
            ;;
        *)
            log_error "Invalid choice"
            exit 1
            ;;
    esac
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --binary|-b)
                UPDATE_BINARY=true
                shift
                ;;
            --service|-s)
                UPDATE_SERVICE=true
                shift
                ;;
            --frontend|-f)
                UPDATE_FRONTEND=true
                shift
                ;;
            --all|-a)
                UPDATE_BINARY=true
                UPDATE_SERVICE=true
                UPDATE_FRONTEND=true
                shift
                ;;
            --verbose|-v)
                VERBOSE_MODE=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    echo "R-Panel Update Script"
    echo "Log file: $LOG_FILE"
    echo ""
    
    # Parse arguments
    parse_args "$@"
    
    # Check root
    check_root
    
    # Check installation
    check_installation
    
    # Show menu if no options specified
    if [ "$UPDATE_BINARY" = false ] && [ "$UPDATE_SERVICE" = false ] && [ "$UPDATE_FRONTEND" = false ]; then
        show_menu
    fi
    
    # Execute updates
    if [ "$UPDATE_BINARY" = true ]; then
        update_binary_function
    fi
    
    if [ "$UPDATE_SERVICE" = true ]; then
        update_service_function
    fi
    
    if [ "$UPDATE_FRONTEND" = true ]; then
        update_frontend_function
    fi
    
    echo ""
    log_success "Update completed!"
    echo ""
    echo "Service status:"
    systemctl status r-panel --no-pager -l || true
    echo ""
    echo "Log file: $LOG_FILE"
}

# Run main function
main "$@"


