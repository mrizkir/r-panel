package handlers

import (
	"r-panel/internal/config"
	"r-panel/internal/services"
	"strconv"

	"github.com/gin-gonic/gin"
)

type LogsHandler struct {
	logsService *services.LogsService
}

func NewLogsHandler(cfg *config.Config) *LogsHandler {
	return &LogsHandler{
		logsService: services.NewLogsService(cfg.Paths.NginxLogs),
	}
}

// GetSystemLogs returns system logs
func (h *LogsHandler) GetSystemLogs(c *gin.Context) {
	unit := c.Query("unit")
	lines := 100
	if linesStr := c.Query("lines"); linesStr != "" {
		if parsedLines, err := strconv.Atoi(linesStr); err == nil && parsedLines > 0 && parsedLines <= 1000 {
			lines = parsedLines
		}
	}

	logs, err := h.logsService.GetSystemLogs(unit, lines)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to read system logs", "details": err.Error()})
		return
	}

	c.JSON(200, gin.H{"logs": logs})
}

// GetNginxLogs returns Nginx logs
func (h *LogsHandler) GetNginxLogs(c *gin.Context) {
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

	logs, err := h.logsService.GetNginxLogs(logType, lines)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to read Nginx logs", "details": err.Error()})
		return
	}

	c.JSON(200, gin.H{"logs": logs, "type": logType})
}

// GetPHPFPMLogs returns PHP-FPM logs
func (h *LogsHandler) GetPHPFPMLogs(c *gin.Context) {
	phpVersion := c.Query("version")
	if phpVersion == "" {
		phpVersion = "8.1"
	}

	lines := 100
	if linesStr := c.Query("lines"); linesStr != "" {
		if parsedLines, err := strconv.Atoi(linesStr); err == nil && parsedLines > 0 && parsedLines <= 1000 {
			lines = parsedLines
		}
	}

	logs, err := h.logsService.GetPHPFPMLogs(phpVersion, lines)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to read PHP-FPM logs", "details": err.Error()})
		return
	}

	c.JSON(200, gin.H{"logs": logs, "version": phpVersion})
}

// TailLogs tails a log file
func (h *LogsHandler) TailLogs(c *gin.Context) {
	source := c.Param("source")
	logFile := c.Query("file")

	lines := 100
	if linesStr := c.Query("lines"); linesStr != "" {
		if parsedLines, err := strconv.Atoi(linesStr); err == nil && parsedLines > 0 && parsedLines <= 1000 {
			lines = parsedLines
		}
	}

	logs, err := h.logsService.TailLogs(source, logFile, lines)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to read logs", "details": err.Error()})
		return
	}

	c.JSON(200, gin.H{"logs": logs, "source": source})
}
