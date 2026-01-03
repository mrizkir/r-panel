package handlers

import (
	"fmt"
	"path/filepath"
	"r-panel/internal/config"
	"r-panel/internal/services"
	"time"

	"github.com/gin-gonic/gin"
)

type MySQLHandler struct {
	mysqlService *services.MySQLService
	cfg          *config.Config
}

func NewMySQLHandler(cfg *config.Config) (*MySQLHandler, error) {
	dsn := ""
	if cfg.Database.Type == "mysql" {
		dsn = fmt.Sprintf("%s:%s@tcp(%s:%d)/?charset=%s&parseTime=True",
			cfg.Database.MySQL.Username,
			cfg.Database.MySQL.Password,
			cfg.Database.MySQL.Host,
			cfg.Database.MySQL.Port,
			cfg.Database.MySQL.Charset,
		)
	} else {
		return nil, fmt.Errorf("MySQL service requires MySQL database type")
	}

	mysqlService, err := services.NewMySQLService(dsn)
	if err != nil {
		return nil, err
	}

	return &MySQLHandler{
		mysqlService: mysqlService,
		cfg:          cfg,
	}, nil
}

type CreateDatabaseRequest struct {
	Name string `json:"name" binding:"required"`
}

type CreateMySQLUserRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
	Host     string `json:"host"`
}

type GrantPrivilegesRequest struct {
	Database   string `json:"database" binding:"required"`
	Privileges string `json:"privileges" binding:"required"`
}

type QueryRequest struct {
	Query    string `json:"query" binding:"required"`
	ReadOnly bool   `json:"read_only"`
}

// GetDatabases returns all databases
func (h *MySQLHandler) GetDatabases(c *gin.Context) {
	databases, err := h.mysqlService.GetDatabases()
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to get databases", "details": err.Error()})
		return
	}

	c.JSON(200, gin.H{"databases": databases})
}

// CreateDatabase creates a new database
func (h *MySQLHandler) CreateDatabase(c *gin.Context) {
	var req CreateDatabaseRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid request", "details": err.Error()})
		return
	}

	if err := h.mysqlService.CreateDatabase(req.Name); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	c.JSON(201, gin.H{"message": "Database created successfully"})
}

// DeleteDatabase deletes a database
func (h *MySQLHandler) DeleteDatabase(c *gin.Context) {
	name := c.Param("name")

	if err := h.mysqlService.DeleteDatabase(name); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	c.JSON(200, gin.H{"message": "Database deleted successfully"})
}

// GetUsers returns all MySQL users
func (h *MySQLHandler) GetUsers(c *gin.Context) {
	users, err := h.mysqlService.GetUsers()
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to get users", "details": err.Error()})
		return
	}

	c.JSON(200, gin.H{"users": users})
}

// CreateUser creates a new MySQL user
func (h *MySQLHandler) CreateUser(c *gin.Context) {
	var req CreateMySQLUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid request", "details": err.Error()})
		return
	}

	if req.Host == "" {
		req.Host = "localhost"
	}

	if err := h.mysqlService.CreateUser(req.Username, req.Password, req.Host); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	c.JSON(201, gin.H{"message": "User created successfully"})
}

// DeleteUser deletes a MySQL user
func (h *MySQLHandler) DeleteUser(c *gin.Context) {
	username := c.Param("user")
	host := c.DefaultQuery("host", "localhost")

	if err := h.mysqlService.DeleteUser(username, host); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	c.JSON(200, gin.H{"message": "User deleted successfully"})
}

// GrantPrivileges grants privileges to a user
func (h *MySQLHandler) GrantPrivileges(c *gin.Context) {
	username := c.Param("user")
	host := c.DefaultQuery("host", "localhost")

	var req GrantPrivilegesRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid request", "details": err.Error()})
		return
	}

	if err := h.mysqlService.GrantPrivileges(username, host, req.Database, req.Privileges); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	c.JSON(200, gin.H{"message": "Privileges granted successfully"})
}

// ExecuteQuery executes a SQL query
func (h *MySQLHandler) ExecuteQuery(c *gin.Context) {
	var req QueryRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid request", "details": err.Error()})
		return
	}

	if req.ReadOnly {
		req.ReadOnly = true
	}

	results, err := h.mysqlService.ExecuteQuery(req.Query, req.ReadOnly)
	if err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	c.JSON(200, gin.H{"results": results})
}

// ExportDatabase exports a database
func (h *MySQLHandler) ExportDatabase(c *gin.Context) {
	database := c.Param("database")

	outputPath := filepath.Join(h.cfg.Paths.Backups, fmt.Sprintf("%s_%d.sql", database, time.Now().Unix()))

	if err := h.mysqlService.ExportDatabase(database, outputPath); err != nil {
		c.JSON(500, gin.H{"error": "Failed to export database", "details": err.Error()})
		return
	}

	c.JSON(200, gin.H{"message": "Database exported successfully", "file": outputPath})
}

// ImportDatabase imports a database
func (h *MySQLHandler) ImportDatabase(c *gin.Context) {
	database := c.Param("database")

	file, err := c.FormFile("file")
	if err != nil {
		c.JSON(400, gin.H{"error": "File is required"})
		return
	}

	// Save uploaded file
	dst := filepath.Join(h.cfg.Paths.Backups, file.Filename)
	if err := c.SaveUploadedFile(file, dst); err != nil {
		c.JSON(500, gin.H{"error": "Failed to save file"})
		return
	}

	if err := h.mysqlService.ImportDatabase(database, dst); err != nil {
		c.JSON(500, gin.H{"error": "Failed to import database", "details": err.Error()})
		return
	}

	c.JSON(200, gin.H{"message": "Database imported successfully"})
}
