# R-Panel

<p align="center">
  <img src="frontend/src/images/logo-rpanel.png" alt="R-Panel Logo" width="200"/>
</p>

<p align="center">
  <strong>Lightweight Server Management Panel</strong>
  <br>
  Built with Go & Bootstrap for Ubuntu Server Management
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#tech-stack">Tech Stack</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#screenshots">Screenshots</a> •
  <a href="#license">License</a>
</p>

---

## 📋 About

**R-Panel** is a minimalist, modern server management panel designed for **Ubuntu servers (minimum version 22.04 LTS)**. Perfect for managing web servers, PHP-FPM pools, Nginx virtual hosts, and MySQL databases without the overhead of heavy control panels.

Born from real-world production experience managing servers, R-Panel provides an intuitive web interface for server administration tasks that typically require SSH and command-line expertise.

**Why R-Panel?**
- 🎯 **Ubuntu-focused** - Optimized for Ubuntu 22.04 LTS and higher
- 🪶 **Lightweight** - Minimal resource usage, no bloat
- 🚀 **Fast** - Built with Go for maximum performance
- 🔒 **Security-first** - Production-hardened security practices
- 📊 **Real-time** - Live server monitoring and service status
- 🛠️ **Extensible** - Clean codebase, easy to customize

**Perfect for:**
- VPS/Cloud servers (DigitalOcean, Linode, AWS EC2, etc.)
- Development servers
- Small to medium production environments
- Moodle/WordPress/Laravel hosting
- Anyone who prefers simplicity over bloated control panels

---

## ✨ Features

### 🖥️ Server Monitoring
- **Real-time system stats** - CPU, Memory, Disk, Network
- **Visual dashboards** with Chart.js graphs
- **Service status** - Nginx, PHP-FPM, MySQL, swap memory
- **Process monitoring** - Top processes by CPU/Memory
- **Disk usage alerts** - Prevent storage issues

### 🔧 PHP-FPM Management
- **Multiple PHP versions** support (7.4, 8.0, 8.1, 8.2, 8.3)
- **Pool configuration editor** - Create, edit, delete pools
- **Per-pool security** - Customize `disable_functions`, `open_basedir`
- **Resource limits** - Set memory_limit, max_execution_time per pool
- **Performance tuning** - Configure pm settings (static, dynamic, ondemand)
- **Zero-downtime reload** - Apply changes without dropping connections

### 🌐 Nginx Management
- **Virtual host management** - Add/edit/delete server blocks
- **SSL/TLS support** - HTTPS enabled by default with automatic certificate management
- **Multi-domain SSL** - Automatic SSL for multiple domains via SNI (Server Name Indication)
- **Let's Encrypt integration** - Automatic certificate generation and renewal
- **Self-signed fallback** - Temporary certificates created automatically during installation
- **PHP-FPM integration** - Automatic pool assignment
- **Access & error logs** - Built-in log viewer
- **Configuration validator** - Test nginx config before reload
- **Custom nginx.conf** - Edit advanced configurations

### 💾 MySQL/MariaDB Management
- **Database CRUD** - Create, list, delete databases
- **User management** - Manage MySQL users and privileges
- **Import/Export** - SQL file upload and download
- **Query executor** - Run SQL queries via web interface
- **Performance stats** - Query cache, connections, slow queries

### 📦 Backup & Restore
- **Automated backups** - Schedule file and database backups
- **Flexible scheduling** - Hourly, daily, weekly, monthly
- **Compression** - Gzip compression for space saving
- **Retention policies** - Auto-delete old backups
- **One-click restore** - Restore from backup archive
- **Remote storage** - Support for S3/SFTP (coming soon)

### 💿 Disk & Resource Management
- **Disk quota** - Set quotas for users and groups
- **Quota management** - Easy quota configuration via CLI tools
- **Swap management** - Automatic swap file creation (2GB default)
- **Resource monitoring** - Track disk usage and quotas

### 📜 System Logs
- **Real-time log viewer** - Tail logs in browser
- **Multi-source logs** - System, Nginx, PHP-FPM, MySQL
- **Search & filter** - Find specific log entries
- **Download logs** - Export log segments
- **Log rotation** - Prevent log files from filling disk

### 👤 User Management
- **Multi-user support** - Create admin and read-only users
- **Role-based access** - Granular permissions
- **Activity logging** - Audit trail of all actions
- **Session management** - Active session monitoring

---

## 🛠️ Tech Stack

### Backend
- **[Go 1.21+](https://go.dev/)** - High-performance compiled language
- **[Gin Framework](https://gin-gonic.com/)** - Blazing fast HTTP framework
- **JWT Authentication** - Secure stateless authentication
- **MySQL** - Lightweight database options

### Frontend
- **Vanilla JavaScript** - No heavy frameworks
- **[jQuery 3.7](https://jquery.com/)** - Simple DOM manipulation
- **[Bootstrap 5](https://getbootstrap.com/)** - Responsive UI
- **[Chart.js 4](https://www.chartjs.org/)** - Real-time charts
- **[DataTables](https://datatables.net/)** - Advanced table features
- **[Vite](https://vitejs.dev/)** - Fast build tool with minification

### System Requirements
- **OS**: Ubuntu Server 22.04 LTS or higher (Debian-based systems supported)
- **RAM**: 512MB minimum (1GB recommended)
- **Disk**: 500MB for R-Panel + space for data
- **Swap**: Automatically created (2GB) if not present
- **Services**: Nginx, PHP-FPM, MySQL/MariaDB (installed automatically)
- **SSL**: OpenSSL for certificate generation

---

## 📥 Installation

### Prerequisites
```bash
# Ubuntu Server 22.04 LTS or higher
# Update system first
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y nginx mysql-server php8.1-fpm php8.1-mysql \
    git curl wget build-essential
```

### Quick Install (Recommended)
```bash
# 1. Download and run installer
curl -fsSL https://raw.githubusercontent.com/rizkiromdoni/r-panel/main/install.sh | sudo bash

# 2. Access R-Panel
# HTTPS is enabled by default (self-signed certificate)
# https://your-server-ip:8080
# https://your-domain.com:8080 (if DNS configured)
# Default: admin / changeme
# 
# Note: HTTP will automatically redirect to HTTPS
```

### Debug Installation (Troubleshooting)
If you encounter issues during installation, run with debug mode to see detailed output:
```bash
bash -x ./install.sh --verbose 2>&1 | tee debug.log
```
This will:
- Show all commands being executed (`-x` flag)
- Display verbose output (`--verbose`)
- Save all output to `debug.log` file for later review

### Manual Installation
```bash
# 1. Install Go
wget https://go.dev/dl/go1.21.5.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc

# 2. Install Node.js
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# 3. Clone R-Panel
git clone https://github.com/rizkiromdoni/r-panel.git
cd r-panel

# 4. Setup backend
cd backend
go mod download
cp configs/config.example.yaml configs/config.yaml
# Edit config.yaml with your settings

# 5. Initialize database
go run cmd/server/main.go migrate

# 6. Build frontend
cd ../frontend
yarn install
yarn build

# 7. Start R-Panel
cd ../backend
go run cmd/server/main.go

# Access at http://localhost:8080
```

### Production Deployment
```bash
# 1. Build production binary
cd backend
go build -ldflags="-s -w" -o /opt/r-panel/r-panel cmd/server/main.go

# 2. Create systemd service
sudo tee /etc/systemd/system/rpanel.service > /dev/null <<EOF
[Unit]
Description=R-Panel Server Management
After=network.target mysql.service

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/r-panel
ExecStart=/opt/r-panel/r-panel
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 3. Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable rpanel
sudo systemctl start rpanel

# 4. Setup Nginx reverse proxy with SSL (automatically configured by installer)
# The installer automatically:
# - Creates HTTPS server block on port 8080
# - Generates self-signed certificate
# - Configures automatic redirect from HTTP to HTTPS
# - Supports multiple domains via SNI
#
# To upgrade to Let's Encrypt certificate:
# certbot --nginx -d panel.yourdomain.com
#
# Manual Nginx config (if not using installer):
sudo tee /etc/nginx/sites-available/rpanel > /dev/null <<EOF
# HTTP redirect to HTTPS
server {
    listen 8080;
    server_name _;
    return 301 https://\$host\$request_uri;
}

# HTTPS server
server {
    listen 8080 ssl http2;
    server_name _;
    
    ssl_certificate /etc/letsencrypt/live/panel.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/panel.yourdomain.com/privkey.pem;
    
    location / {
        proxy_pass http://127.0.0.1:8081;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/rpanel /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

---

## 📖 Usage

### First Login
```
1. Access https://your-server-ip:8080 or https://your-domain.com:8080
   (HTTP will automatically redirect to HTTPS)
2. Accept the self-signed certificate warning (browser security prompt)
   - This is normal during initial setup
   - Let's Encrypt certificate will replace it automatically if DNS is configured
3. Login with: admin / changeme
4. IMMEDIATELY change password in Settings → Profile
5. Create additional users if needed
```

### Managing PHP-FPM Pools
```
1. Navigate to PHP-FPM → Pools
2. Click "Create Pool"
3. Set pool name (e.g., "website1")
4. Choose PHP version (8.1, 8.2, etc.)
5. Configure resources (pm.max_children, memory_limit)
6. Apply security template or custom disable_functions
7. Save and reload PHP-FPM
```

### Creating Nginx Sites
```
1. Go to Nginx → Sites
2. Click "Add New Site"
3. Enter domain (e.g., example.com)
4. Set document root (e.g., /var/www/example.com)
5. Select PHP-FPM pool
6. SSL is automatically configured for R-Panel on port 8080
7. Save and test nginx configuration
8. Reload Nginx
```

### SSL Certificate Management
```
R-Panel automatically handles SSL certificates:

1. During installation:
   - Self-signed certificate is created automatically
   - HTTPS is enabled by default on port 8080
   - HTTP automatically redirects to HTTPS

2. For Let's Encrypt certificate:
   - Ensure DNS points to your server
   - Run: certbot --nginx -d your-domain.com
   - Certificate will automatically replace self-signed cert

3. Multiple domains:
   - Each domain accessing port 8080 gets SSL automatically
   - SNI (Server Name Indication) handles domain-specific certificates
   - Example: https://client1.com:8080, https://client2.org:8080
```

### Database Management
```
1. MySQL → Databases → Create New
2. Enter database name
3. Create user with privileges
4. Use credentials in your application
```

### Setting Up Backups
```
1. Backup → Schedule → New Job
2. Select what to backup (files/databases)
3. Choose frequency (daily/weekly)
4. Set retention (keep last 7 backups)
5. Enable and save
```

---

## 🖼️ Screenshots

### Dashboard - Real-time Monitoring
![Dashboard](docs/screenshots/dashboard.png)
*Live CPU, Memory, Disk statistics with Chart.js graphs*

### PHP-FPM Pool Management
![PHP-FPM](docs/screenshots/phpfpm.png)
*Create and manage multiple PHP-FPM pools with different configurations*

### Nginx Virtual Hosts
![Nginx](docs/screenshots/nginx.png)
*Easy virtual host management with syntax validation*

---

## 🗂️ Project Structure
```
r-panel/
├── backend/                 # Go backend
│   ├── cmd/server/         # Main application
│   ├── internal/
│   │   ├── api/           # HTTP handlers & routes
│   │   ├── services/      # Business logic
│   │   └── models/        # Data models
│   ├── templates/         # HTML templates
│   └── configs/           # Configuration files
├── frontend/              # Frontend assets
│   └── src/
│       ├── css/          # Stylesheets
│       └── js/           # JavaScript
├── dist/                 # Built frontend (generated)
├── scripts/              # Installation scripts
└── docs/                 # Documentation
```

---

## 🔐 Security

R-Panel follows security best practices:

- ✅ **Authentication** - JWT-based with secure password hashing (bcrypt)
- ✅ **Authorization** - Role-based access control (RBAC)
- ✅ **Input validation** - All user inputs sanitized
- ✅ **SQL injection prevention** - Parameterized queries only
- ✅ **XSS protection** - Proper output encoding
- ✅ **CSRF tokens** - Protection on state-changing requests
- ✅ **Rate limiting** - Prevent brute-force attacks
- ✅ **Audit logging** - Track all administrative actions
- ✅ **Secure defaults** - PHP dangerous functions disabled by default

**Security Recommendations:**
- Change default password immediately
- HTTPS is enabled by default - upgrade to Let's Encrypt certificate when DNS is ready
- Restrict panel access by IP (firewall rules)
- Keep system and R-Panel updated
- Regular security audits
- Use strong passwords (12+ characters)
- SSL certificates are automatically managed - self-signed during install, Let's Encrypt when available

---

## 🤝 Contributing

Contributions are welcome! Here's how:

1. Fork the repository
2. Create feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit changes (`git commit -m 'Add AmazingFeature'`)
4. Push to branch (`git push origin feature/AmazingFeature`)
5. Open Pull Request

**Development Setup:**
```bash
# Backend (Go)
cd backend
go run cmd/server/main.go

# Frontend (Vite dev server)
cd frontend
yarn dev
```

---

## 📝 Roadmap

- [x] Core monitoring (CPU, RAM, Disk)
- [x] PHP-FPM pool management
- [x] Nginx vhost management
- [x] MySQL database management
- [x] Backup system
- [x] SSL/TLS support with automatic certificate management
- [x] Multi-domain SSL support via SNI
- [x] Self-signed certificate fallback
- [x] Disk quota management
- [x] Automatic swap creation
- [ ] Let's Encrypt automatic renewal UI
- [ ] Firewall (UFW) management
- [ ] Cron job manager
- [ ] File manager
- [ ] Email alerts (disk space, service down)
- [ ] Two-factor authentication (2FA)
- [ ] Docker container support
- [ ] Multi-server management
- [ ] REST API for automation
- [ ] Telegram bot integration

---

## 📄 License

MIT License - Copyright (c) 2026 Mochammad Rizki Romdoni

See [LICENSE](LICENSE) file for details.

---

## 👨‍💻 Author

**Mochammad Rizki Romdoni**

- GitHub: [@mrizkir](https://github.com/mrizkir)
- Server: [dev.yacanet.com](https://dev.yacanet.com)

---

## 🙏 Acknowledgments

- Built from experience managing production Moodle servers
- Designed for simplicity and minimal resource usage
- Inspired by the need for lightweight alternatives to bloated panels

---

## ⚠️ Disclaimer

R-Panel is designed for **Ubuntu Server 22.04 LTS or higher**. While it may work on other Debian-based systems, official support is limited to Ubuntu 22.04 LTS and newer versions.

Always test in a non-production environment first!

---

## 📞 Support

- 📖 [Documentation](docs/)
- 🐛 [Issue Tracker](https://github.com/rizkiromdoni/r-panel/issues)
- 💬 [Discussions](https://github.com/rizkiromdoni/r-panel/discussions)

---

<p align="center">
  Made with ❤️ for Ubuntu server administrators
</p>

<p align="center">
  ⭐ Star this repo if it helps you manage your servers!
</p>
