package handlers

import (
	"r-panel/internal/services"
	"strconv"

	"github.com/gin-gonic/gin"
)

type MonitoringHandler struct {
	systemService *services.SystemService
}

func NewMonitoringHandler() *MonitoringHandler {
	return &MonitoringHandler{
		systemService: services.NewSystemService(),
	}
}

// GetStats returns current system statistics
func (h *MonitoringHandler) GetStats(c *gin.Context) {
	stats, err := h.systemService.GetStats()
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to get system stats", "details": err.Error()})
		return
	}

	c.JSON(200, stats)
}

// GetServices returns status of common services
func (h *MonitoringHandler) GetServices(c *gin.Context) {
	serviceNames := []string{"nginx", "php8.1-fpm", "php8.2-fpm", "mysql", "mariadb"}

	services, err := h.systemService.GetServicesStatus(serviceNames)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to get service status", "details": err.Error()})
		return
	}

	c.JSON(200, gin.H{"services": services})
}

// GetProcesses returns top processes
func (h *MonitoringHandler) GetProcesses(c *gin.Context) {
	limit := 10
	if limitStr := c.Query("limit"); limitStr != "" {
		// Parse limit, but keep it reasonable
		if parsedLimit, err := strconv.Atoi(limitStr); err == nil && parsedLimit > 0 && parsedLimit <= 50 {
			limit = parsedLimit
		}
	}

	processes, err := h.systemService.GetTopProcesses(limit)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to get processes", "details": err.Error()})
		return
	}

	c.JSON(200, gin.H{"processes": processes})
}
