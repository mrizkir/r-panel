package main

import (
	"net/http"
	"path/filepath"

	"github.com/gin-gonic/gin"
)

func main() {
	// Set Gin to release mode in production
	// gin.SetMode(gin.ReleaseMode)

	r := gin.Default()

	// Setup API routes
	api := r.Group("/api")
	{
		api.GET("/health", func(c *gin.Context) {
			c.JSON(200, gin.H{
				"status":  "ok",
				"message": "R-Panel API is running",
			})
		})
		// TODO: Add more API routes here
		// api.POST("/auth/login", handlers.Login)
		// api.GET("/admin/clients", handlers.GetClients)
		// etc...
	}

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

	// Run server on port 8080
	r.Run(":8080")
}
