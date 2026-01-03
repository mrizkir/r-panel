package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"r-panel/internal/api/routes"
	"r-panel/internal/config"
	"r-panel/internal/models"
	"r-panel/internal/services"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/acme/autocert"
)

// findConfigFile searches for config.yaml in multiple locations
func findConfigFile() string {
	// List of possible config file locations (in order of priority)
	possiblePaths := []string{
		// 1. Current working directory
		"./configs/config.yaml",
		// 2. Installed location (production)
		"/usr/local/r-panel/configs/config.yaml",
		// 3. Relative to binary location
		"",
		// 4. Home directory fallback
		"",
	}
	
	// Try to find binary location and add relative path
	if exePath, err := os.Executable(); err == nil {
		exeDir := filepath.Dir(exePath)
		possiblePaths = append(possiblePaths, filepath.Join(exeDir, "configs", "config.yaml"))
		// Also try parent directory (if binary is in bin/)
		possiblePaths = append(possiblePaths, filepath.Join(filepath.Dir(exeDir), "configs", "config.yaml"))
	}
	
	// Try each path
	for _, path := range possiblePaths {
		if path == "" {
			continue
		}
		// Try absolute path first
		absPath, err := filepath.Abs(path)
		if err == nil {
			if _, err := os.Stat(absPath); err == nil {
				return absPath
			}
		}
		// Try relative path
		if _, err := os.Stat(path); err == nil {
			absPath, _ := filepath.Abs(path)
			return absPath
		}
	}
	
	return ""
}

// findFrontendDir searches for web/dist directory in multiple locations
func findFrontendDir() string {
	// List of possible frontend directory locations (in order of priority)
	possiblePaths := []string{
		// 1. Current working directory
		"./web/dist",
		// 2. Installed location (production)
		"/usr/local/r-panel/web/dist",
		// 3. Relative to binary location
		"",
	}
	
	// Try to find binary location and add relative path
	if exePath, err := os.Executable(); err == nil {
		exeDir := filepath.Dir(exePath)
		possiblePaths = append(possiblePaths, filepath.Join(exeDir, "web", "dist"))
		// Also try parent directory (if binary is in bin/)
		possiblePaths = append(possiblePaths, filepath.Join(filepath.Dir(exeDir), "web", "dist"))
	}
	
	// Try each path
	for _, path := range possiblePaths {
		if path == "" {
			continue
		}
		// Try absolute path first
		absPath, err := filepath.Abs(path)
		if err == nil {
			if info, err := os.Stat(absPath); err == nil && info.IsDir() {
				return absPath
			}
		}
		// Try relative path
		if info, err := os.Stat(path); err == nil && info.IsDir() {
			absPath, _ := filepath.Abs(path)
			return absPath
		}
	}
	
	return ""
}

func main() {
	// Find config file - try multiple locations
	configPath := findConfigFile()
	if configPath == "" {
		log.Fatalf("Failed to find config file. Searched in:")
		log.Fatalf("  - ./configs/config.yaml (current directory)")
		log.Fatalf("  - /usr/local/r-panel/configs/config.yaml (installed location)")
		log.Fatalf("  - configs/config.yaml (relative to binary)")
		log.Fatalf("")
		log.Fatalf("To fix this:")
		log.Fatalf("  1. Copy example config: cp /usr/local/r-panel/configs/config.example.yaml /usr/local/r-panel/configs/config.yaml")
		log.Fatalf("  2. Edit config: nano /usr/local/r-panel/configs/config.yaml")
	}
	
	log.Printf("Loading config from: %s", configPath)
	
	// Load configuration
	cfg, err := config.Load(configPath)
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

	// Find frontend directory - try multiple locations
	frontendDir := findFrontendDir()
	if frontendDir == "" {
		log.Fatalf("Failed to find frontend directory (web/dist). Searched in:")
		log.Fatalf("  - ./web/dist (current directory)")
		log.Fatalf("  - /usr/local/r-panel/web/dist (installed location)")
	}

	r.Static("/assets", filepath.Join(frontendDir, "assets"))
	r.StaticFile("/favicon.ico", filepath.Join(frontendDir, "favicon.ico"))

	// Serve index.html for root and all non-API routes (SPA routing)
	r.GET("/", func(c *gin.Context) {
		c.File(filepath.Join(frontendDir, "index.html"))
	})

	// Fallback to index.html for SPA routing (Vue Router)
	r.NoRoute(func(c *gin.Context) {
		path := c.Request.URL.Path

		// Check if it's an API route
		if len(path) >= 4 && path[:4] == "/api" {
			c.JSON(404, gin.H{"error": "API endpoint not found"})
			return
		}

		// Serve index.html for SPA fallback
		c.File(filepath.Join(frontendDir, "index.html"))
	})

	// Create HTTP server
	srv := &http.Server{
		Handler:      r,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Configure TLS if enabled
	if cfg.Server.TLS.Enabled && cfg.Server.TLS.Domain != "" {
		// Setup cache directory
		cacheDir := cfg.Server.TLS.CacheDir
		if cacheDir == "" {
			cacheDir = "./data/certs"
		}

		// Convert to absolute path
		absCacheDir, err := filepath.Abs(cacheDir)
		if err == nil {
			cacheDir = absCacheDir
		}

		// Ensure directory exists
		if err := os.MkdirAll(cacheDir, 0755); err != nil {
			log.Fatalf("Failed to create cache directory: %v", err)
		}

		// Create autocert manager with dynamic host policy
		m := &autocert.Manager{
			Prompt: autocert.AcceptTOS,
			// Dynamic HostPolicy - allow any domain for multi-domain support
			// Autocert will automatically get certificate for any requested domain
			HostPolicy: func(ctx context.Context, host string) error {
				// Remove port from host
				host = strings.Split(host, ":")[0]

				// Allow R-Panel domain
				if host == cfg.Server.TLS.Domain {
					return nil
				}

				// Allow all domains for client websites
				// Autocert will automatically get certificate for any domain
				// This enables multi-domain support: client1.com:8080, client2.com:8080, etc.
				return nil
			},
			Cache: autocert.DirCache(cacheDir),
			Email: cfg.Server.TLS.Email,
		}

		// Configure TLS with SNI support
		srv.Addr = fmt.Sprintf(":%d", cfg.Server.Port)

		// Create TLS config with autocert
		srv.TLSConfig = &tls.Config{
			GetCertificate: func(hello *tls.ClientHelloInfo) (*tls.Certificate, error) {
				// Remove port from ServerName
				if hello.ServerName != "" {
					serverName := strings.Split(hello.ServerName, ":")[0]
					hello.ServerName = serverName
				}
				return m.GetCertificate(hello)
			},
			MinVersion: tls.VersionTLS12,
		}

		// Start HTTP server on port 80 for ACME challenge
		// This is required for Let's Encrypt HTTP-01 challenge
		go func() {
			log.Printf("Starting ACME HTTP server on :80 for certificate validation")
			httpServer := &http.Server{
				Addr:    ":80",
				Handler: m.HTTPHandler(nil),
			}
			if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				log.Printf("ACME HTTP server error: %v", err)
			}
		}()

		log.Printf("Starting R-Panel server with TLS on %s (multi-domain support enabled)", srv.Addr)
		log.Printf("R-Panel domain: %s", cfg.Server.TLS.Domain)
		log.Printf("Client domains will be automatically handled with SNI")

		if err := srv.ListenAndServeTLS("", ""); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Failed to start server: %v", err)
		}
	} else {
		// No TLS - listen on configured host/port (typically localhost for reverse proxy)
		addr := fmt.Sprintf("%s:%d", cfg.Server.Host, cfg.Server.Port)
		srv.Addr = addr
		log.Printf("Starting R-Panel server on %s (behind reverse proxy)", addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Failed to start server: %v", err)
		}
	}
}
