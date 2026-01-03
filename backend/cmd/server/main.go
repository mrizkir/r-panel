package main

import (
	"fmt"
	"log"
	"path/filepath"

	"r-panel/internal/api/routes"
	"r-panel/internal/config"
	"r-panel/internal/models"
	"r-panel/internal/services"

	"github.com/gin-gonic/gin"
)

func main() {
	// Load configuration
	cfg, err := config.Load("configs/config.yaml")
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Initialize database
	if err := models.InitDB(cfg); err != nil {
		log.Fatalf("Failed to initialize database: %v", err)
	}

	// Create default user if database is empty
	authService := services.NewAuthService(cfg)
	if err := authService.CreateDefaultUser(); err != nil {
		log.Printf("Warning: Failed to create default user: %v", err)
	}

	// Set Gin mode
	if cfg.Server.Mode == "release" {
		gin.SetMode(gin.ReleaseMode)
	}

	// Create router
	r := gin.Default()

	// Setup routes
	routes.SetupRoutes(r, cfg)

	// Serve static files from web/dist directory
	frontendDir := filepath.Join("web", "dist")
	r.Static("/assets", filepath.Join(frontendDir, "assets"))
	r.StaticFile("/favicon.ico", filepath.Join(frontendDir, "favicon.ico"))

	// Serve index.html for root and all non-API routes (SPA routing)
	r.GET("/", func(c *gin.Context) {
		c.File(filepath.Join(frontendDir, "index.html"))
	})

	// Fallback to index.html for SPA routing (Vue Router)
	r.NoRoute(func(c *gin.Context) {
		// Check if it's an API route
		path := c.Request.URL.Path
		if len(path) >= 4 && path[:4] == "/api" {
			c.JSON(404, gin.H{"error": "API endpoint not found"})
			return
		}

		// For all other routes, serve index.html (SPA fallback)
		c.File(filepath.Join(frontendDir, "index.html"))
	})

	// Run server
	addr := fmt.Sprintf("%s:%d", cfg.Server.Host, cfg.Server.Port)
	log.Printf("Starting R-Panel server on %s", addr)
	if err := r.Run(addr); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
