package main

import (
	"github.com/gin-gonic/gin"
)

func main() {
	// Buat router Gin
	r := gin.Default()

	// Route sederhana
	r.GET("/", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"message": "Welcome to R-Panel!",
			"status":  "running",
		})
	})

	// Jalankan server di port 8080
	r.Run(":8080")
}
