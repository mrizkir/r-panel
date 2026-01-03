package handlers

import (
	"r-panel/internal/config"
	"r-panel/internal/models"
	"r-panel/internal/services"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

type AuthHandler struct {
	authService *services.AuthService
	cfg         *config.Config
}

func NewAuthHandler(authService *services.AuthService, cfg *config.Config) *AuthHandler {
	return &AuthHandler{
		authService: authService,
		cfg:         cfg,
	}
}

type LoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

type LoginResponse struct {
	Token string       `json:"token"`
	User  *models.User `json:"user"`
}

// Login handles user login
func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid request", "details": err.Error()})
		return
	}

	// Authenticate user
	user, err := h.authService.Authenticate(req.Username, req.Password)
	if err != nil {
		c.JSON(401, gin.H{"error": "Invalid credentials"})
		return
	}

	// Generate JWT token
	token, expiresAt, err := h.generateToken(user)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to generate token"})
		return
	}

	// Create session
	if err := h.authService.CreateSession(user.ID, token, expiresAt); err != nil {
		c.JSON(500, gin.H{"error": "Failed to create session"})
		return
	}

	// Log audit
	h.logAudit(user.ID, "login", "", "", c.ClientIP(), c.GetHeader("User-Agent"))

	c.JSON(200, LoginResponse{
		Token: token,
		User:  user,
	})
}

// Logout handles user logout
func (h *AuthHandler) Logout(c *gin.Context) {
	session, exists := c.Get("session")
	if !exists {
		c.JSON(401, gin.H{"error": "Not authenticated"})
		return
	}

	sess := session.(*models.Session)
	if err := h.authService.DeleteSession(sess.Token); err != nil {
		c.JSON(500, gin.H{"error": "Failed to logout"})
		return
	}

	user, _ := c.Get("user")
	u := user.(*models.User)
	h.logAudit(u.ID, "logout", "", "", c.ClientIP(), c.GetHeader("User-Agent"))

	c.JSON(200, gin.H{"message": "Logged out successfully"})
}

// GetMe returns current user information
func (h *AuthHandler) GetMe(c *gin.Context) {
	user, exists := c.Get("user")
	if !exists {
		c.JSON(401, gin.H{"error": "Not authenticated"})
		return
	}

	u := user.(*models.User)
	// Don't include password hash in response
	u.PasswordHash = ""
	c.JSON(200, u)
}

// generateToken generates a JWT token for the user
func (h *AuthHandler) generateToken(user *models.User) (string, time.Time, error) {
	// Parse expires_in duration
	expiresIn, err := time.ParseDuration(h.cfg.JWT.ExpiresIn)
	if err != nil {
		expiresIn = 24 * time.Hour // Default to 24 hours
	}

	expiresAt := time.Now().Add(expiresIn)

	// Get JWT secret
	secret := h.cfg.JWT.Secret
	if secret == "" {
		secret = "r-panel-default-secret-change-in-production"
	}

	claims := jwt.MapClaims{
		"user_id":  user.ID,
		"username": user.Username,
		"role":     user.Role,
		"exp":      expiresAt.Unix(),
		"iat":      time.Now().Unix(),
		"iss":      h.cfg.JWT.Issuer,
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString([]byte(secret))
	if err != nil {
		return "", time.Time{}, err
	}

	return tokenString, expiresAt, nil
}

// logAudit logs an audit entry
func (h *AuthHandler) logAudit(userID uint, action, resource, resourceID, ipAddress, userAgent string) {
	auditLog := &models.AuditLog{
		UserID:     userID,
		Action:     action,
		Resource:   resource,
		ResourceID: resourceID,
		IPAddress:  ipAddress,
		UserAgent:  userAgent,
	}
	models.DB.Create(auditLog)
}
