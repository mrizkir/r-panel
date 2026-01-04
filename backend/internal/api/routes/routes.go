package routes

import (
	"r-panel/internal/api/handlers"
	"r-panel/internal/api/middleware"
	"r-panel/internal/config"
	"r-panel/internal/services"

	"github.com/gin-gonic/gin"
)

func SetupRoutes(r *gin.Engine, cfg *config.Config) {
  // Initialize services
  authService := services.NewAuthService(cfg)

  // Initialize handlers
  authHandler := handlers.NewAuthHandler(authService, cfg)
  monitoringHandler := handlers.NewMonitoringHandler()
  phpfpmHandler := handlers.NewPHPFPMHandler(cfg)
  nginxHandler := handlers.NewNginxHandler(cfg)
  backupHandler := handlers.NewBackupHandler(cfg)
  userHandler := handlers.NewUserHandler(cfg)
  clientHandler := handlers.NewClientHandler(cfg)
  logsHandler := handlers.NewLogsHandler(cfg)

  // Initialize MySQL handler (may fail if MySQL not configured)
  mysqlHandler, _ := handlers.NewMySQLHandler(cfg)

  // Middleware
  r.Use(middleware.CORSMiddleware())
  r.Use(middleware.ErrorHandler())

  // Public routes
  api := r.Group("/api")
  {
    api.GET("/health", func(c *gin.Context) {
      c.JSON(200, gin.H{
        "status":  "ok",
        "message": "R-Panel API is running",
      })
    })

    // Auth routes (public)
    auth := api.Group("/auth")
    {
      auth.POST("/login", authHandler.Login)
    }
  }

  // Protected routes
  protected := api.Group("")
  protected.Use(middleware.AuthMiddleware(authService))
  {
    // Auth routes (protected)
    protected.POST("/auth/logout", authHandler.Logout)
    protected.GET("/auth/me", authHandler.GetMe)

    // Monitoring routes
    monitoring := protected.Group("/monitoring")
    {
      monitoring.GET("/stats", monitoringHandler.GetStats)
      monitoring.GET("/services", monitoringHandler.GetServices)
      monitoring.GET("/processes", monitoringHandler.GetProcesses)
    }

    // PHP-FPM routes
    phpfpm := protected.Group("/phpfpm")
    {
      phpfpm.GET("/versions", phpfpmHandler.GetVersions)
      phpfpm.GET("/pools", phpfpmHandler.GetPools)
      phpfpm.GET("/pools/:version/:name", phpfpmHandler.GetPool)
      phpfpm.POST("/pools", phpfpmHandler.CreatePool)
      phpfpm.PUT("/pools/:version/:name", phpfpmHandler.UpdatePool)
      phpfpm.DELETE("/pools/:version/:name", phpfpmHandler.DeletePool)
      phpfpm.POST("/reload/:version", phpfpmHandler.ReloadPHPFPM)
    }

    // Nginx routes
    nginx := protected.Group("/nginx")
    {
      nginx.GET("/sites", nginxHandler.GetSites)
      nginx.GET("/sites/:domain", nginxHandler.GetSite)
      nginx.POST("/sites", nginxHandler.CreateSite)
      nginx.PUT("/sites/:domain", nginxHandler.UpdateSite)
      nginx.DELETE("/sites/:domain", nginxHandler.DeleteSite)
      nginx.POST("/sites/:domain/enable", nginxHandler.EnableSite)
      nginx.POST("/sites/:domain/disable", nginxHandler.DisableSite)
      nginx.POST("/test", nginxHandler.TestConfig)
      nginx.POST("/reload", nginxHandler.Reload)
      nginx.GET("/logs/:type", nginxHandler.GetLogs)
    }

    // MySQL routes (if configured)
    if mysqlHandler != nil {
      mysql := protected.Group("/mysql")
      {
        mysql.GET("/databases", mysqlHandler.GetDatabases)
        mysql.POST("/databases", mysqlHandler.CreateDatabase)
        mysql.DELETE("/databases/:name", mysqlHandler.DeleteDatabase)
        mysql.GET("/users", mysqlHandler.GetUsers)
        mysql.POST("/users", mysqlHandler.CreateUser)
        mysql.DELETE("/users/:user", mysqlHandler.DeleteUser)
        mysql.POST("/users/:user/privileges", mysqlHandler.GrantPrivileges)
        mysql.POST("/query", mysqlHandler.ExecuteQuery)
        mysql.POST("/export/:database", mysqlHandler.ExportDatabase)
        mysql.POST("/import/:database", mysqlHandler.ImportDatabase)
      }
    }

    // Backup routes
    backups := protected.Group("/backups")
    {
      backups.GET("", backupHandler.GetBackups)
      backups.POST("", backupHandler.CreateBackup)
      backups.DELETE("/:id", backupHandler.DeleteBackup)
      backups.POST("/restore", backupHandler.RestoreBackup)
    }

    // User management routes
    users := protected.Group("/users")
    {
      users.GET("", userHandler.GetUsers)
      users.GET("/:id", userHandler.GetUser)
      users.POST("", middleware.RequireRole("admin"), userHandler.CreateUser)
      users.PUT("/:id", middleware.RequireRole("admin"), userHandler.UpdateUser)
      users.DELETE("/:id", middleware.RequireRole("admin"), userHandler.DeleteUser)
      users.POST("/:id/password", userHandler.UpdatePassword)
      users.GET("/sessions", userHandler.GetSessions)
    }

    // Client management routes
    clients := protected.Group("/clients")
    {
      clients.GET("", clientHandler.GetClients)
      clients.GET("/:id", clientHandler.GetClient)
      clients.POST("", middleware.RequireRole("admin"), clientHandler.CreateClient)
      clients.PUT("/:id", middleware.RequireRole("admin"), clientHandler.UpdateClient)
      clients.PUT("/:id/limits", middleware.RequireRole("admin"), clientHandler.UpdateClientLimits)
      clients.DELETE("/:id", middleware.RequireRole("admin"), clientHandler.DeleteClient)
    }

    // Logs routes
    logs := protected.Group("/logs")
    {
      logs.GET("/system", logsHandler.GetSystemLogs)
      logs.GET("/nginx/:type", logsHandler.GetNginxLogs)
      logs.GET("/phpfpm", logsHandler.GetPHPFPMLogs)
      logs.GET("/tail/:source", logsHandler.TailLogs)
    }
  }
}
