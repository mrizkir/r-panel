package services

import (
	"errors"
	"r-panel/internal/config"
	"r-panel/internal/models"

	"gorm.io/gorm"
)

type UserService struct {
	authService *AuthService
}

func NewUserService(cfg *config.Config) *UserService {
	return &UserService{
		authService: NewAuthService(cfg),
	}
}

// GetUsers returns all users
func (s *UserService) GetUsers() ([]models.User, error) {
	var users []models.User
	if err := models.DB.Find(&users).Error; err != nil {
		return nil, err
	}

	// Clear password hashes
	for i := range users {
		users[i].PasswordHash = ""
	}

	return users, nil
}

// GetUser returns a specific user by ID
func (s *UserService) GetUser(id uint) (*models.User, error) {
	var user models.User
	if err := models.DB.First(&user, id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrUserNotFound
		}
		return nil, err
	}

	user.PasswordHash = ""
	return &user, nil
}

// CreateUser creates a new user
func (s *UserService) CreateUser(username, password, role string) (*models.User, error) {
	user, err := s.authService.CreateUser(username, password, role)
	if err != nil {
		return nil, err
	}

	user.PasswordHash = ""
	return user, nil
}

// UpdateUser updates user information (except password)
func (s *UserService) UpdateUser(id uint, username, role string) (*models.User, error) {
	var user models.User
	if err := models.DB.First(&user, id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrUserNotFound
		}
		return nil, err
	}

	// Check if username is taken by another user
	if username != user.Username {
		var existingUser models.User
		if err := models.DB.Where("username = ? AND id != ?", username, id).First(&existingUser).Error; err == nil {
			return nil, ErrUserExists
		}
	}

	user.Username = username
	user.Role = role

	if err := models.DB.Save(&user).Error; err != nil {
		return nil, err
	}

	user.PasswordHash = ""
	return &user, nil
}

// UpdatePassword updates user password
func (s *UserService) UpdatePassword(id uint, newPassword string) error {
	var user models.User
	if err := models.DB.First(&user, id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrUserNotFound
		}
		return err
	}

	hashedPassword, err := s.authService.HashPassword(newPassword)
	if err != nil {
		return err
	}

	user.PasswordHash = hashedPassword
	return models.DB.Save(&user).Error
}

// DeleteUser deletes a user
func (s *UserService) DeleteUser(id uint) error {
	var user models.User
	if err := models.DB.First(&user, id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrUserNotFound
		}
		return err
	}

	// Don't allow deleting the last admin user
	var adminCount int64
	models.DB.Model(&models.User{}).Where("role = ?", "admin").Count(&adminCount)
	if user.Role == "admin" && adminCount <= 1 {
		return errors.New("cannot delete the last admin user")
	}

	return models.DB.Delete(&user).Error
}

// GetSessions returns active sessions for a user
func (s *UserService) GetSessions(userID uint) ([]models.Session, error) {
	var sessions []models.Session
	if err := models.DB.Where("user_id = ?", userID).Preload("User").Find(&sessions).Error; err != nil {
		return nil, err
	}
	return sessions, nil
}
