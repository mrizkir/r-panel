package services

import (
	"errors"
	"r-panel/internal/config"
	"r-panel/internal/models"
	"time"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

var (
	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrUserNotFound       = errors.New("user not found")
	ErrUserExists         = errors.New("user already exists")
)

type AuthService struct {
	cfg *config.Config
}

func NewAuthService(cfg *config.Config) *AuthService {
	return &AuthService{cfg: cfg}
}

// HashPassword hashes a password using bcrypt
func (s *AuthService) HashPassword(password string) (string, error) {
	bytes, err := bcrypt.GenerateFromPassword([]byte(password), s.cfg.Security.BcryptCost)
	return string(bytes), err
}

// VerifyPassword verifies a password against a hash
func (s *AuthService) VerifyPassword(hashedPassword, password string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(hashedPassword), []byte(password))
	return err == nil
}

// CreateUser creates a new user
func (s *AuthService) CreateUser(username, password, role string) (*models.User, error) {
	// Check if user exists
	var existingUser models.User
	if err := models.DB.Where("username = ?", username).First(&existingUser).Error; err == nil {
		return nil, ErrUserExists
	}

	// Hash password
	hashedPassword, err := s.HashPassword(password)
	if err != nil {
		return nil, err
	}

	// Create user
	user := &models.User{
		Username:     username,
		PasswordHash: hashedPassword,
		Role:         role,
	}

	if err := models.DB.Create(user).Error; err != nil {
		return nil, err
	}

	return user, nil
}

// Authenticate verifies credentials and returns the user
func (s *AuthService) Authenticate(username, password string) (*models.User, error) {
	var user models.User
	if err := models.DB.Where("username = ?", username).First(&user).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrInvalidCredentials
		}
		return nil, err
	}

	if !s.VerifyPassword(user.PasswordHash, password) {
		return nil, ErrInvalidCredentials
	}

	return &user, nil
}

// CreateDefaultUser creates the default admin user if it doesn't exist
func (s *AuthService) CreateDefaultUser() error {
	var count int64
	models.DB.Model(&models.User{}).Count(&count)

	if count == 0 {
		_, err := s.CreateUser(
			s.cfg.DefaultUser.Username,
			s.cfg.DefaultUser.Password,
			s.cfg.DefaultUser.Role,
		)
		return err
	}

	return nil
}

// CreateSession creates a new session record
func (s *AuthService) CreateSession(userID uint, token string, expiresAt time.Time) error {
	session := &models.Session{
		UserID:    userID,
		Token:     token,
		ExpiresAt: expiresAt,
	}
	return models.DB.Create(session).Error
}

// GetSession retrieves a session by token
func (s *AuthService) GetSession(token string) (*models.Session, error) {
	var session models.Session
	if err := models.DB.Where("token = ? AND expires_at > ?", token, time.Now()).Preload("User").First(&session).Error; err != nil {
		return nil, err
	}
	return &session, nil
}

// DeleteSession deletes a session
func (s *AuthService) DeleteSession(token string) error {
	return models.DB.Where("token = ?", token).Delete(&models.Session{}).Error
}

// DeleteExpiredSessions removes expired sessions
func (s *AuthService) DeleteExpiredSessions() error {
	return models.DB.Where("expires_at < ?", time.Now()).Delete(&models.Session{}).Error
}
