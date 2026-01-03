package models

import (
	"fmt"
	"r-panel/internal/config"

	"gorm.io/driver/mysql"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

var DB *gorm.DB

// InitDB initializes the database connection
func InitDB(cfg *config.Config) error {
	var dialector gorm.Dialector
	var err error

	switch cfg.Database.Type {
	case "sqlite":
		dialector = sqlite.Open(cfg.Database.SQLite.Path)
	case "mysql":
		dsn := fmt.Sprintf("%s:%s@tcp(%s:%d)/%s?charset=%s&parseTime=True&loc=Local",
			cfg.Database.MySQL.Username,
			cfg.Database.MySQL.Password,
			cfg.Database.MySQL.Host,
			cfg.Database.MySQL.Port,
			cfg.Database.MySQL.Database,
			cfg.Database.MySQL.Charset,
		)
		dialector = mysql.Open(dsn)
	default:
		return fmt.Errorf("unsupported database type: %s", cfg.Database.Type)
	}

	logLevel := logger.Silent
	if cfg.Server.Mode == "debug" {
		logLevel = logger.Info
	}

	DB, err = gorm.Open(dialector, &gorm.Config{
		Logger: logger.Default.LogMode(logLevel),
	})
	if err != nil {
		return fmt.Errorf("failed to connect to database: %w", err)
	}

	// Auto migrate models
	if err := DB.AutoMigrate(&User{}, &Session{}, &AuditLog{}); err != nil {
		return fmt.Errorf("failed to migrate database: %w", err)
	}

	return nil
}
