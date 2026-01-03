package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"log"
	"net/http"
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
		// Check if this is R-Panel domain or client domain
		host := strings.Split(c.Request.Host, ":")[0] // Remove port

		// If TLS enabled and domain matches R-Panel domain, serve R-Panel
		if cfg.Server.TLS.Enabled && cfg.Server.TLS.Domain != "" {
			if host == cfg.Server.TLS.Domain {
				c.File(filepath.Join(frontendDir, "index.html"))
				return
			}
			// For client domains, you might want to proxy or serve client website
			// For now, serve R-Panel as default
		}

		// Default: serve R-Panel
		c.File(filepath.Join(frontendDir, "index.html"))
	})

	// Fallback to index.html for SPA routing (Vue Router)
	r.NoRoute(func(c *gin.Context) {
		path := c.Request.URL.Path
		host := strings.Split(c.Request.Host, ":")[0] // Remove port

		// Check if it's an API route
		if len(path) >= 4 && path[:4] == "/api" {
			// API routes - only for R-Panel domain (if TLS enabled)
			if cfg.Server.TLS.Enabled && cfg.Server.TLS.Domain != "" {
				if host != cfg.Server.TLS.Domain {
					c.JSON(403, gin.H{"error": "API access denied"})
					return
				}
			}
			c.JSON(404, gin.H{"error": "API endpoint not found"})
			return
		}

		// For R-Panel domain, serve index.html (SPA fallback)
		if cfg.Server.TLS.Enabled && cfg.Server.TLS.Domain != "" {
			if host == cfg.Server.TLS.Domain {
				c.File(filepath.Join(frontendDir, "index.html"))
				return
			}
		}

		// Default: serve R-Panel (when TLS disabled or same domain)
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
		// Start HTTP server without TLS
		addr := fmt.Sprintf("%s:%d", cfg.Server.Host, cfg.Server.Port)
		srv.Addr = addr
		log.Printf("Starting R-Panel server on %s", addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Failed to start server: %v", err)
		}
	}
}
