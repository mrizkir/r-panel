package handlers

import (
	"r-panel/internal/config"
	"r-panel/internal/services"

	"github.com/gin-gonic/gin"
)

type BackupHandler struct {
	backupService *services.BackupService
}

func NewBackupHandler(cfg *config.Config) *BackupHandler {
	return &BackupHandler{
		backupService: services.NewBackupService(cfg.Paths.Backups),
	}
}

type CreateBackupRequest struct {
	Type       string `json:"type" binding:"required"` // file or database
	Source     string `json:"source" binding:"required"`
	BackupName string `json:"backup_name"`
}

type RestoreBackupRequest struct {
	BackupName string `json:"backup_name" binding:"required"`
	TargetPath string `json:"target_path"`
}

// GetBackups returns list of backup files
func (h *BackupHandler) GetBackups(c *gin.Context) {
	backups, err := h.backupService.ListBackups()
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to list backups", "details": err.Error()})
		return
	}

	c.JSON(200, gin.H{"backups": backups})
}

// CreateBackup creates a new backup
func (h *BackupHandler) CreateBackup(c *gin.Context) {
	var req CreateBackupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid request", "details": err.Error()})
		return
	}

	var backupPath string
	var err error

	switch req.Type {
	case "file":
		backupPath, err = h.backupService.CreateFileBackup(req.Source, req.BackupName)
	case "database":
		backupPath, err = h.backupService.CreateDatabaseBackup(req.Source, req.BackupName)
	default:
		c.JSON(400, gin.H{"error": "Invalid backup type. Use 'file' or 'database'"})
		return
	}

	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to create backup", "details": err.Error()})
		return
	}

	c.JSON(201, gin.H{"message": "Backup created successfully", "path": backupPath})
}

// DeleteBackup deletes a backup
func (h *BackupHandler) DeleteBackup(c *gin.Context) {
	backupName := c.Param("id")

	if err := h.backupService.DeleteBackup(backupName); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	c.JSON(200, gin.H{"message": "Backup deleted successfully"})
}

// RestoreBackup restores a backup
func (h *BackupHandler) RestoreBackup(c *gin.Context) {
	var req RestoreBackupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid request", "details": err.Error()})
		return
	}

	backups, err := h.backupService.ListBackups()
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to list backups"})
		return
	}

	var backupPath string
	for _, backup := range backups {
		if backup.Name == req.BackupName {
			backupPath = backup.Path
			break
		}
	}

	if backupPath == "" {
		c.JSON(404, gin.H{"error": "Backup not found"})
		return
	}

	// Determine backup type
	backupType := "file"
	if backupPath[len(backupPath)-7:] == ".sql.gz" || backupPath[len(backupPath)-4:] == ".sql" {
		backupType = "database"
	}

	if backupType == "file" {
		if req.TargetPath == "" {
			c.JSON(400, gin.H{"error": "target_path is required for file backups"})
			return
		}

		if err := h.backupService.RestoreFileBackup(backupPath, req.TargetPath); err != nil {
			c.JSON(500, gin.H{"error": "Failed to restore backup", "details": err.Error()})
			return
		}
	} else {
		c.JSON(400, gin.H{"error": "Database restore not implemented yet"})
		return
	}

	c.JSON(200, gin.H{"message": "Backup restored successfully"})
}
