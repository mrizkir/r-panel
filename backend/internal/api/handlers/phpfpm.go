package handlers

import (
	"r-panel/internal/config"
	"r-panel/internal/services"

	"github.com/gin-gonic/gin"
)

type PHPFPMHandler struct {
	phpfpmService *services.PHPFPMService
}

func NewPHPFPMHandler(cfg *config.Config) *PHPFPMHandler {
	return &PHPFPMHandler{
		phpfpmService: services.NewPHPFPMService(cfg.Paths.PHPFPM),
	}
}

type CreatePoolRequest struct {
	PHPVersion string `json:"php_version" binding:"required"`
	PoolName   string `json:"pool_name" binding:"required"`
	Config     string `json:"config" binding:"required"`
}

type UpdatePoolRequest struct {
	Config string `json:"config" binding:"required"`
}

// GetVersions returns installed PHP versions
func (h *PHPFPMHandler) GetVersions(c *gin.Context) {
	versions, err := h.phpfpmService.GetPHPVersions()
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to get PHP versions", "details": err.Error()})
		return
	}

	c.JSON(200, gin.H{"versions": versions})
}

// GetPools returns all pools
func (h *PHPFPMHandler) GetPools(c *gin.Context) {
	pools, err := h.phpfpmService.GetPools()
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to get pools", "details": err.Error()})
		return
	}

	c.JSON(200, gin.H{"pools": pools})
}

// GetPool returns a specific pool
func (h *PHPFPMHandler) GetPool(c *gin.Context) {
	phpVersion := c.Param("version")
	poolName := c.Param("name")

	pool, err := h.phpfpmService.GetPool(phpVersion, poolName)
	if err != nil {
		c.JSON(404, gin.H{"error": err.Error()})
		return
	}

	c.JSON(200, pool)
}

// CreatePool creates a new pool
func (h *PHPFPMHandler) CreatePool(c *gin.Context) {
	var req CreatePoolRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid request", "details": err.Error()})
		return
	}

	if err := h.phpfpmService.CreatePool(req.PHPVersion, req.PoolName, req.Config); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	c.JSON(201, gin.H{"message": "Pool created successfully"})
}

// UpdatePool updates a pool
func (h *PHPFPMHandler) UpdatePool(c *gin.Context) {
	phpVersion := c.Param("version")
	poolName := c.Param("name")

	var req UpdatePoolRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid request", "details": err.Error()})
		return
	}

	if err := h.phpfpmService.UpdatePool(phpVersion, poolName, req.Config); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	c.JSON(200, gin.H{"message": "Pool updated successfully"})
}

// DeletePool deletes a pool
func (h *PHPFPMHandler) DeletePool(c *gin.Context) {
	phpVersion := c.Param("version")
	poolName := c.Param("name")

	if err := h.phpfpmService.DeletePool(phpVersion, poolName); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	c.JSON(200, gin.H{"message": "Pool deleted successfully"})
}

// ReloadPHPFPM reloads PHP-FPM service
func (h *PHPFPMHandler) ReloadPHPFPM(c *gin.Context) {
	phpVersion := c.Param("version")

	if err := h.phpfpmService.ReloadPHPFPM(phpVersion); err != nil {
		c.JSON(500, gin.H{"error": "Failed to reload PHP-FPM", "details": err.Error()})
		return
	}

	c.JSON(200, gin.H{"message": "PHP-FPM reloaded successfully"})
}
