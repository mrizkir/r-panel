package routes

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"r-panel/internal/config"
	"r-panel/internal/models"
	"r-panel/internal/services"
	"strconv"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// setupTestDB initializes a test database
func setupTestDB(t *testing.T) *config.Config {
	// Create temporary directory for test database
	tmpDir := os.TempDir()
	testDBPath := fmt.Sprintf("%s/rpanel_test_%d.db", tmpDir, time.Now().UnixNano())

	// Create a temporary config for testing
	cfg := &config.Config{
		Database: config.DatabaseConfig{
			Type: "sqlite",
			SQLite: config.SQLiteConfig{
				Path: testDBPath,
			},
		},
		JWT: config.JWTConfig{
			Secret:    "test-secret-key-for-testing-only",
			ExpiresIn: "24h",
			Issuer:    "r-panel-test",
		},
		Security: config.SecurityConfig{
			BcryptCost: 10,
		},
		Paths: config.PathsConfig{
			Backups: "./tmp/test-backups",
		},
	}

	// Create backups directory if it doesn't exist
	os.MkdirAll("./tmp/test-backups", 0755)

	// Initialize database
	err := models.InitDB(cfg)
	require.NoError(t, err)

	return cfg
}

// cleanupTestDB cleans up test database
func cleanupTestDB(t *testing.T, cfg *config.Config) {
	if models.DB != nil {
		sqlDB, err := models.DB.DB()
		if err == nil {
			sqlDB.Close()
		}
		// Try to remove test database file
		if cfg != nil && cfg.Database.Type == "sqlite" {
			os.Remove(cfg.Database.SQLite.Path)
		}
	}
	models.DB = nil
}

// createTestUser creates a test user and returns it
func createTestUser(t *testing.T, authService *services.AuthService, username, password, role string) *models.User {
	user, err := authService.CreateUser(username, password, role)
	require.NoError(t, err)
	return user
}

// createTestToken creates a JWT token for testing
func createTestToken(t *testing.T, cfg *config.Config, authService *services.AuthService, user *models.User) string {
	expiresIn, _ := time.ParseDuration(cfg.JWT.ExpiresIn)
	if expiresIn == 0 {
		expiresIn = 24 * time.Hour
	}
	now := time.Now()
	expiresAt := now.Add(expiresIn)

	// Add jti (JWT ID) with nanosecond timestamp to ensure uniqueness
	claims := jwt.MapClaims{
		"user_id":  user.ID,
		"username": user.Username,
		"role":     user.Role,
		"exp":      expiresAt.Unix(),
		"iat":      now.Unix(),
		"iss":      cfg.JWT.Issuer,
		"jti":      fmt.Sprintf("%d-%d", user.ID, now.UnixNano()), // Unique JWT ID
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString([]byte(cfg.JWT.Secret))
	require.NoError(t, err)

	// Create session in database
	err = authService.CreateSession(user.ID, tokenString, expiresAt)
	require.NoError(t, err)

	return tokenString
}

// setupTestRouter creates a test router with routes
func setupTestRouter(cfg *config.Config) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	SetupRoutes(r, cfg)
	return r
}

func TestClientsRoutes(t *testing.T) {
	// Set environment variable to skip Linux user creation in tests
	os.Setenv("SKIP_LINUX_USER", "true")
	defer os.Unsetenv("SKIP_LINUX_USER")

	cfg := setupTestDB(t)
	defer cleanupTestDB(t, cfg)

	authService := services.NewAuthService(cfg)

	// Create test users
	adminUser := createTestUser(t, authService, "admin", "admin123", "admin")
	regularUser := createTestUser(t, authService, "user", "user123", "user")

	t.Run("GET /api/clients - Success with admin", func(t *testing.T) {
		router := setupTestRouter(cfg)
		token := createTestToken(t, cfg, authService, adminUser)

		req, _ := http.NewRequest("GET", "/api/clients", nil)
		req.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusOK, w.Code)
		var response map[string]interface{}
		err := json.Unmarshal(w.Body.Bytes(), &response)
		assert.NoError(t, err)
		assert.Contains(t, response, "clients")
	})

	t.Run("GET /api/clients - Success with regular user", func(t *testing.T) {
		router := setupTestRouter(cfg)
		token := createTestToken(t, cfg, authService, regularUser)

		req, _ := http.NewRequest("GET", "/api/clients", nil)
		req.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusOK, w.Code)
	})

	t.Run("GET /api/clients - Unauthorized (no token)", func(t *testing.T) {
		router := setupTestRouter(cfg)

		req, _ := http.NewRequest("GET", "/api/clients", nil)
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusUnauthorized, w.Code)
	})

	t.Run("GET /api/clients/:id - Success", func(t *testing.T) {
		router := setupTestRouter(cfg)
		token := createTestToken(t, cfg, authService, adminUser)

		// Create a test client first
		clientService := services.NewClientService(cfg)
		clientData := &services.CreateClientData{
			Username:    "testclient",
			Password:    "testpass123",
			ContactName: "Test Client",
			Email:       "test@example.com",
		}
		client, err := clientService.CreateClient(clientData)
		require.NoError(t, err)

		req, _ := http.NewRequest("GET", "/api/clients/"+strconv.FormatUint(uint64(client.ID), 10), nil)
		req.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusOK, w.Code)
		var response models.Client
		err = json.Unmarshal(w.Body.Bytes(), &response)
		assert.NoError(t, err)
		assert.Equal(t, client.ID, response.ID)
	})

	t.Run("GET /api/clients/:id - Not Found", func(t *testing.T) {
		router := setupTestRouter(cfg)
		token := createTestToken(t, cfg, authService, adminUser)

		req, _ := http.NewRequest("GET", "/api/clients/99999", nil)
		req.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusNotFound, w.Code)
	})

	t.Run("GET /api/clients/:id - Invalid ID", func(t *testing.T) {
		router := setupTestRouter(cfg)
		token := createTestToken(t, cfg, authService, adminUser)

		req, _ := http.NewRequest("GET", "/api/clients/invalid", nil)
		req.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("POST /api/clients - Success (admin)", func(t *testing.T) {
		router := setupTestRouter(cfg)
		token := createTestToken(t, cfg, authService, adminUser)

		createRequest := map[string]interface{}{
			"username":     "newclient",
			"password":     "newpass123",
			"contact_name": "New Client",
			"email":        "newclient@example.com",
		}
		jsonData, _ := json.Marshal(createRequest)

		req, _ := http.NewRequest("POST", "/api/clients", bytes.NewBuffer(jsonData))
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusCreated, w.Code)
		var response models.Client
		err := json.Unmarshal(w.Body.Bytes(), &response)
		assert.NoError(t, err)
		assert.Equal(t, "newclient@example.com", response.Email)
	})

	t.Run("POST /api/clients - Forbidden (regular user)", func(t *testing.T) {
		router := setupTestRouter(cfg)
		token := createTestToken(t, cfg, authService, regularUser)

		createRequest := map[string]interface{}{
			"username":     "newclient2",
			"password":     "newpass123",
			"contact_name": "New Client 2",
			"email":        "newclient2@example.com",
		}
		jsonData, _ := json.Marshal(createRequest)

		req, _ := http.NewRequest("POST", "/api/clients", bytes.NewBuffer(jsonData))
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusForbidden, w.Code)
	})

	t.Run("POST /api/clients - Bad Request (missing required fields)", func(t *testing.T) {
		router := setupTestRouter(cfg)
		token := createTestToken(t, cfg, authService, adminUser)

		createRequest := map[string]interface{}{
			"username": "newclient3",
			// Missing password, contact_name, email
		}
		jsonData, _ := json.Marshal(createRequest)

		req, _ := http.NewRequest("POST", "/api/clients", bytes.NewBuffer(jsonData))
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("PUT /api/clients/:id - Success (admin)", func(t *testing.T) {
		router := setupTestRouter(cfg)
		token := createTestToken(t, cfg, authService, adminUser)

		// Create a test client first
		clientService := services.NewClientService(cfg)
		clientData := &services.CreateClientData{
			Username:    "updateclient",
			Password:    "testpass123",
			ContactName: "Update Client",
			Email:       "update@example.com",
		}
		client, err := clientService.CreateClient(clientData)
		require.NoError(t, err)

		updateRequest := map[string]interface{}{
			"contact_name": "Updated Client Name",
			"email":        "updated@example.com",
		}
		jsonData, _ := json.Marshal(updateRequest)

		req, _ := http.NewRequest("PUT", "/api/clients/"+strconv.FormatUint(uint64(client.ID), 10), bytes.NewBuffer(jsonData))
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusOK, w.Code)
		var response models.Client
		err = json.Unmarshal(w.Body.Bytes(), &response)
		assert.NoError(t, err)
		assert.Equal(t, "Updated Client Name", response.ContactName)
		assert.Equal(t, "updated@example.com", response.Email)
	})

	t.Run("PUT /api/clients/:id - Forbidden (regular user)", func(t *testing.T) {
		router := setupTestRouter(cfg)
		token := createTestToken(t, cfg, authService, regularUser)

		updateRequest := map[string]interface{}{
			"contact_name": "Should Fail",
		}
		jsonData, _ := json.Marshal(updateRequest)

		req, _ := http.NewRequest("PUT", "/api/clients/1", bytes.NewBuffer(jsonData))
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusForbidden, w.Code)
	})

	t.Run("PUT /api/clients/:id/limits - Success (admin)", func(t *testing.T) {
		router := setupTestRouter(cfg)
		token := createTestToken(t, cfg, authService, adminUser)

		// Create a test client first
		clientService := services.NewClientService(cfg)
		clientData := &services.CreateClientData{
			Username:    "limitsclient",
			Password:    "testpass123",
			ContactName: "Limits Client",
			Email:       "limits@example.com",
		}
		client, err := clientService.CreateClient(clientData)
		require.NoError(t, err)

		updateLimitsRequest := map[string]interface{}{
			"limit_web_domain":      10,
			"limit_web_quota":       1000,
			"limit_ssl":             true,
			"limit_ssl_letsencrypt": true,
		}
		jsonData, _ := json.Marshal(updateLimitsRequest)

		req, _ := http.NewRequest("PUT", "/api/clients/"+strconv.FormatUint(uint64(client.ID), 10)+"/limits", bytes.NewBuffer(jsonData))
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusOK, w.Code)
		var response models.Client
		err = json.Unmarshal(w.Body.Bytes(), &response)
		assert.NoError(t, err)
		require.NotNil(t, response.ClientLimits)
		assert.Equal(t, 10, response.ClientLimits.LimitWebDomain)
		assert.Equal(t, true, response.ClientLimits.LimitSSL)
	})

	t.Run("PUT /api/clients/:id/limits - Forbidden (regular user)", func(t *testing.T) {
		router := setupTestRouter(cfg)
		token := createTestToken(t, cfg, authService, regularUser)

		updateLimitsRequest := map[string]interface{}{
			"limit_web_domain": 5,
		}
		jsonData, _ := json.Marshal(updateLimitsRequest)

		req, _ := http.NewRequest("PUT", "/api/clients/1/limits", bytes.NewBuffer(jsonData))
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Content-Type", "application/json")
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusForbidden, w.Code)
	})

	t.Run("DELETE /api/clients/:id - Success (admin)", func(t *testing.T) {
		router := setupTestRouter(cfg)
		token := createTestToken(t, cfg, authService, adminUser)

		// Create a test client first
		clientService := services.NewClientService(cfg)
		clientData := &services.CreateClientData{
			Username:    "deleteclient",
			Password:    "testpass123",
			ContactName: "Delete Client",
			Email:       "delete@example.com",
		}
		client, err := clientService.CreateClient(clientData)
		require.NoError(t, err)

		req, _ := http.NewRequest("DELETE", "/api/clients/"+strconv.FormatUint(uint64(client.ID), 10), nil)
		req.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusOK, w.Code)
		var response map[string]interface{}
		err = json.Unmarshal(w.Body.Bytes(), &response)
		assert.NoError(t, err)
		assert.Contains(t, response, "message")

		// Verify client is deleted
		_, err = clientService.GetClient(client.ID)
		assert.Error(t, err)
	})

	t.Run("DELETE /api/clients/:id - Forbidden (regular user)", func(t *testing.T) {
		router := setupTestRouter(cfg)
		token := createTestToken(t, cfg, authService, regularUser)

		req, _ := http.NewRequest("DELETE", "/api/clients/1", nil)
		req.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusForbidden, w.Code)
	})

	t.Run("DELETE /api/clients/:id - Not Found", func(t *testing.T) {
		router := setupTestRouter(cfg)
		token := createTestToken(t, cfg, authService, adminUser)

		req, _ := http.NewRequest("DELETE", "/api/clients/99999", nil)
		req.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusNotFound, w.Code)
	})
}
