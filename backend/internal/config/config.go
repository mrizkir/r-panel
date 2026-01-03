package config

import (
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Server     ServerConfig     `yaml:"server"`
	Database   DatabaseConfig   `yaml:"database"`
	JWT        JWTConfig        `yaml:"jwt"`
	Security   SecurityConfig   `yaml:"security"`
	Paths      PathsConfig      `yaml:"paths"`
	DefaultUser DefaultUserConfig `yaml:"default_user"`
}

type ServerConfig struct {
	Host string `yaml:"host"`
	Port int    `yaml:"port"`
	Mode string `yaml:"mode"`
}

type DatabaseConfig struct {
	Type   string         `yaml:"type"`
	SQLite SQLiteConfig   `yaml:"sqlite"`
	MySQL  MySQLConfig    `yaml:"mysql"`
}

type SQLiteConfig struct {
	Path string `yaml:"path"`
}

type MySQLConfig struct {
	Host     string `yaml:"host"`
	Port     int    `yaml:"port"`
	Username string `yaml:"username"`
	Password string `yaml:"password"`
	Database string `yaml:"database"`
	Charset  string `yaml:"charset"`
}

type JWTConfig struct {
	Secret    string `yaml:"secret"`
	ExpiresIn string `yaml:"expires_in"`
	Issuer    string `yaml:"issuer"`
}

type SecurityConfig struct {
	BcryptCost int              `yaml:"bcrypt_cost"`
	RateLimit  RateLimitConfig  `yaml:"rate_limit"`
}

type RateLimitConfig struct {
	Enabled           bool `yaml:"enabled"`
	RequestsPerMinute int  `yaml:"requests_per_minute"`
}

type PathsConfig struct {
	PHPFPM Pools      string `yaml:"php_fpm_pools"`
	NginxSitesAvailable string `yaml:"nginx_sites_available"`
	NginxSitesEnabled   string `yaml:"nginx_sites_enabled"`
	NginxLogs           string `yaml:"nginx_logs"`
	Backups             string `yaml:"backups"`
}

type DefaultUserConfig struct {
	Username string `yaml:"username"`
	Password string `yaml:"password"`
	Role     string `yaml:"role"`
}

var Global *Config

// Load reads the configuration file and environment variables
func Load(configPath string) (*Config, error) {
	// Read config file
	data, err := os.ReadFile(configPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config file: %w", err)
	}

	// Override with environment variables
	if jwtSecret := os.Getenv("RPANEL_JWT_SECRET"); jwtSecret != "" {
		cfg.JWT.Secret = jwtSecret
	}

	if dbType := os.Getenv("RPANEL_DB_TYPE"); dbType != "" {
		cfg.Database.Type = dbType
	}

	if dbPath := os.Getenv("RPANEL_DB_PATH"); dbPath != "" {
		cfg.Database.SQLite.Path = dbPath
	}

	if mysqlHost := os.Getenv("RPANEL_MYSQL_HOST"); mysqlHost != "" {
		cfg.Database.MySQL.Host = mysqlHost
	}

	if mysqlUser := os.Getenv("RPANEL_MYSQL_USER"); mysqlUser != "" {
		cfg.Database.MySQL.Username = mysqlUser
	}

	if mysqlPass := os.Getenv("RPANEL_MYSQL_PASSWORD"); mysqlPass != "" {
		cfg.Database.MySQL.Password = mysqlPass
	}

	if mysqlDB := os.Getenv("RPANEL_MYSQL_DATABASE"); mysqlDB != "" {
		cfg.Database.MySQL.Database = mysqlDB
	}

	// Ensure data directory exists for SQLite
	if cfg.Database.Type == "sqlite" {
		dataDir := filepath.Dir(cfg.Database.SQLite.Path)
		if err := os.MkdirAll(dataDir, 0755); err != nil {
			return nil, fmt.Errorf("failed to create data directory: %w", err)
		}
	}
	
	// Validate MySQL configuration if MySQL is selected
	if cfg.Database.Type == "mysql" {
		if cfg.Database.MySQL.Username == "" {
			return nil, fmt.Errorf("MySQL username is required")
		}
		if cfg.Database.MySQL.Database == "" {
			return nil, fmt.Errorf("MySQL database name is required")
		}
	}

	// Ensure backups directory exists
	if err := os.MkdirAll(cfg.Paths.Backups, 0755); err != nil {
		return nil, fmt.Errorf("failed to create backups directory: %w", err)
	}

	Global = &cfg
	return &cfg, nil
}

