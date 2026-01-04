package routes

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"r-panel/internal/config"
	"r-panel/internal/models"
	"r-panel/internal/services"
	"strconv"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	_ "github.com/go-sql-driver/mysql"
	"github.com/golang-jwt/jwt/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// findTestConfigFile finds the config.yaml file for testing
func findTestConfigFile() string {
	// Try multiple locations relative to backend directory
	possiblePaths := []string{
		"./configs/config.yaml",
		"../configs/config.yaml",
		"../../configs/config.yaml",
	}

	for _, path := range possiblePaths {
		absPath, err := filepath.Abs(path)
		if err == nil {
			if _, err := os.Stat(absPath); err == nil {
				return absPath
			}
		}
	}

	return ""
}

// setupTestDB initializes a test database using existing database from config
func setupTestDB(t *testing.T) *config.Config {
	// Load config from config.yaml file (required)
	configPath := findTestConfigFile()
	require.NotEmpty(t, configPath, "config.yaml file not found. Please create configs/config.yaml")

	baseCfg, err := config.Load(configPath)
	require.NoError(t, err, "Failed to load config from %s", configPath)

	// Use existing database configuration (do not create new database)
	cfg := &config.Config{
		Environment: baseCfg.Environment,
		Database:    baseCfg.Database,
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

	// Initialize database connection (using existing database)
	err = models.InitDB(cfg)
	require.NoError(t, err)

	return cfg
}

// testRecords tracks all records created during test for cleanup
type testRecords struct {
	UserIDs       []uint
	ClientIDs     []uint
	SessionIDs    []uint
	ClientUserIDs []uint // UserIDs that were created for clients
}

// trackTestClient tracks a client created during test for cleanup
func trackTestClient(client *models.Client, records *testRecords) {
	if records != nil && client != nil {
		records.ClientIDs = append(records.ClientIDs, client.ID)
		if client.UserID != 0 {
			records.ClientUserIDs = append(records.ClientUserIDs, client.UserID)
		}
	}
}

// cleanupTestDB deletes only test records and closes database connection
func cleanupTestDB(t *testing.T, cfg *config.Config, records *testRecords) {
	if models.DB == nil {
		return
	}

	// Delete in reverse order of dependencies: ClientLimits -> Client -> Session -> User
	if records != nil {
		// Delete ClientLimits for test clients
		if len(records.ClientIDs) > 0 {
			models.DB.Where("client_id IN ?", records.ClientIDs).Delete(&models.ClientLimits{})
		}

		// Delete test Clients
		if len(records.ClientIDs) > 0 {
			models.DB.Where("id IN ?", records.ClientIDs).Delete(&models.Client{})
		}

		// Delete test Sessions
		if len(records.SessionIDs) > 0 {
			models.DB.Where("id IN ?", records.SessionIDs).Delete(&models.Session{})
		}

		// Delete test Users (including client users)
		allUserIDs := append(records.UserIDs, records.ClientUserIDs...)
		if len(allUserIDs) > 0 {
			// Remove duplicates
			uniqueUserIDs := make(map[uint]bool)
			for _, id := range allUserIDs {
				uniqueUserIDs[id] = true
			}
			userIDs := make([]uint, 0, len(uniqueUserIDs))
			for id := range uniqueUserIDs {
				userIDs = append(userIDs, id)
			}
			models.DB.Where("id IN ?", userIDs).Delete(&models.User{})
		}
	}

	// Close database connection
	sqlDB, err := models.DB.DB()
	if err == nil {
		sqlDB.Close()
	}
	models.DB = nil
}

// createTestUser creates a test user and returns it, tracking in records
func createTestUser(t *testing.T, authService *services.AuthService, username, password, role string, records *testRecords) *models.User {
	user, err := authService.CreateUser(username, password, role)
	require.NoError(t, err)
	if records != nil {
		records.UserIDs = append(records.UserIDs, user.ID)
	}
	return user
}

// createTestToken creates a JWT token for testing, tracking session in records
func createTestToken(t *testing.T, cfg *config.Config, authService *services.AuthService, user *models.User, records *testRecords) string {
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

	// Track session by retrieving it (CreateSession doesn't return the session)
	if records != nil {
		session, err := authService.GetSession(tokenString)
		if err == nil && session != nil {
			records.SessionIDs = append(records.SessionIDs, session.ID)
		}
	}

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
	// Load config to check environment
	configPath := findTestConfigFile()
	if configPath == "" {
		t.Skip("config.yaml file not found. Skipping tests.")
		return
	}

	baseCfg, err := config.Load(configPath)
	if err != nil {
		t.Skipf("Failed to load config: %v. Skipping tests.", err)
		return
	}

	// Skip tests if environment is production
	if baseCfg.Environment == "production" {
		t.Skip("Tests are disabled in production environment. Set environment to 'local' in config.yaml to run tests.")
		return
	}

	// Set environment variable to skip Linux user creation in tests
	os.Setenv("SKIP_LINUX_USER", "true")
	defer os.Unsetenv("SKIP_LINUX_USER")

	cfg := setupTestDB(t)

	// Track all records created during test
	records := &testRecords{
		UserIDs:       []uint{},
		ClientIDs:     []uint{},
		SessionIDs:    []uint{},
		ClientUserIDs: []uint{},
	}
	defer cleanupTestDB(t, cfg, records)

	authService := services.NewAuthService(cfg)

	// Create test users
	adminUser := createTestUser(t, authService, "admin", "admin123", "admin", records)
	regularUser := createTestUser(t, authService, "user", "user123", "user", records)

	t.Run("GET /api/clients - Success with admin", func(t *testing.T) {
		router := setupTestRouter(cfg)
		token := createTestToken(t, cfg, authService, adminUser, records)

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
		token := createTestToken(t, cfg, authService, regularUser, records)

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
		token := createTestToken(t, cfg, authService, adminUser, records)

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
		trackTestClient(client, records)

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
		token := createTestToken(t, cfg, authService, adminUser, records)

		req, _ := http.NewRequest("GET", "/api/clients/99999", nil)
		req.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusNotFound, w.Code)
	})

	t.Run("GET /api/clients/:id - Invalid ID", func(t *testing.T) {
		router := setupTestRouter(cfg)
		token := createTestToken(t, cfg, authService, adminUser, records)

		req, _ := http.NewRequest("GET", "/api/clients/invalid", nil)
		req.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusBadRequest, w.Code)
	})

	t.Run("POST /api/clients - Success (admin)", func(t *testing.T) {
		router := setupTestRouter(cfg)
		token := createTestToken(t, cfg, authService, adminUser, records)

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
		trackTestClient(&response, records)
	})

	t.Run("POST /api/clients - Forbidden (regular user)", func(t *testing.T) {
		router := setupTestRouter(cfg)
		token := createTestToken(t, cfg, authService, regularUser, records)

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
		token := createTestToken(t, cfg, authService, adminUser, records)

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
		token := createTestToken(t, cfg, authService, adminUser, records)

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
		trackTestClient(client, records)

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
		token := createTestToken(t, cfg, authService, regularUser, records)

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
		token := createTestToken(t, cfg, authService, adminUser, records)

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
		trackTestClient(client, records)

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
		token := createTestToken(t, cfg, authService, regularUser, records)

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
		token := createTestToken(t, cfg, authService, adminUser, records)

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
		trackTestClient(client, records)

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
		token := createTestToken(t, cfg, authService, regularUser, records)

		req, _ := http.NewRequest("DELETE", "/api/clients/1", nil)
		req.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusForbidden, w.Code)
	})

	t.Run("DELETE /api/clients/:id - Not Found", func(t *testing.T) {
		router := setupTestRouter(cfg)
		token := createTestToken(t, cfg, authService, adminUser, records)

		req, _ := http.NewRequest("DELETE", "/api/clients/99999", nil)
		req.Header.Set("Authorization", "Bearer "+token)
		w := httptest.NewRecorder()
		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusNotFound, w.Code)
	})
}
