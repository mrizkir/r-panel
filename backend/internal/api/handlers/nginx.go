package handlers

import (
	"r-panel/internal/config"
	"r-panel/internal/services"
	"strconv"

	"github.com/gin-gonic/gin"
)

type NginxHandler struct {
	nginxService *services.NginxService
}

func NewNginxHandler(cfg *config.Config) *NginxHandler {
	return &NginxHandler{
		nginxService: services.NewNginxService(
			cfg.Paths.NginxSitesAvailable,
			cfg.Paths.NginxSitesEnabled,
			cfg.Paths.NginxLogs,
		),
	}
}

type CreateSiteRequest struct {
	Domain string `json:"domain" binding:"required"`
	Config string `json:"config" binding:"required"`
}

type UpdateSiteRequest struct {
	Config string `json:"config" binding:"required"`
}

// GetSites returns all Nginx sites
func (h *NginxHandler) GetSites(c *gin.Context) {
	sites, err := h.nginxService.GetSites()
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to get sites", "details": err.Error()})
		return
	}

	c.JSON(200, gin.H{"sites": sites})
}

// GetSite returns a specific site
func (h *NginxHandler) GetSite(c *gin.Context) {
	domain := c.Param("domain")

	site, err := h.nginxService.GetSite(domain)
	if err != nil {
		c.JSON(404, gin.H{"error": err.Error()})
		return
	}

	c.JSON(200, site)
}

// CreateSite creates a new site
func (h *NginxHandler) CreateSite(c *gin.Context) {
	var req CreateSiteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid request", "details": err.Error()})
		return
	}

	if err := h.nginxService.CreateSite(req.Domain, req.Config); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	c.JSON(201, gin.H{"message": "Site created successfully"})
}

// UpdateSite updates a site
func (h *NginxHandler) UpdateSite(c *gin.Context) {
	domain := c.Param("domain")

	var req UpdateSiteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid request", "details": err.Error()})
		return
	}

	if err := h.nginxService.UpdateSite(domain, req.Config); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	c.JSON(200, gin.H{"message": "Site updated successfully"})
}

// DeleteSite deletes a site
func (h *NginxHandler) DeleteSite(c *gin.Context) {
	domain := c.Param("domain")

	if err := h.nginxService.DeleteSite(domain); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	c.JSON(200, gin.H{"message": "Site deleted successfully"})
}

// EnableSite enables a site
func (h *NginxHandler) EnableSite(c *gin.Context) {
	domain := c.Param("domain")

	if err := h.nginxService.EnableSite(domain); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	c.JSON(200, gin.H{"message": "Site enabled successfully"})
}

// DisableSite disables a site
func (h *NginxHandler) DisableSite(c *gin.Context) {
	domain := c.Param("domain")

	if err := h.nginxService.DisableSite(domain); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}

	c.JSON(200, gin.H{"message": "Site disabled successfully"})
}

// TestConfig tests Nginx configuration
func (h *NginxHandler) TestConfig(c *gin.Context) {
	if err := h.nginxService.TestConfig(); err != nil {
		c.JSON(400, gin.H{"error": "Configuration test failed", "details": err.Error()})
		return
	}

	c.JSON(200, gin.H{"message": "Configuration is valid"})
}

// Reload reloads Nginx
func (h *NginxHandler) Reload(c *gin.Context) {
	if err := h.nginxService.Reload(); err != nil {
		c.JSON(500, gin.H{"error": "Failed to reload Nginx", "details": err.Error()})
		return
	}

	c.JSON(200, gin.H{"message": "Nginx reloaded successfully"})
}

// GetLogs returns Nginx logs
func (h *NginxHandler) GetLogs(c *gin.Context) {
	logType := c.Param("type") // access or error
	if logType != "access" && logType != "error" {
		c.JSON(400, gin.H{"error": "Invalid log type. Use 'access' or 'error'"})
		return
	}

	lines := 100
	if linesStr := c.Query("lines"); linesStr != "" {
		if parsedLines, err := strconv.Atoi(linesStr); err == nil && parsedLines > 0 && parsedLines <= 1000 {
			lines = parsedLines
		}
	}

	logs, err := h.nginxService.GetLogs(logType, lines)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to read logs", "details": err.Error()})
		return
	}

	c.JSON(200, gin.H{"logs": logs, "type": logType})
}
