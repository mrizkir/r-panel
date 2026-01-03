package models

import (
	"time"
)

type User struct {
	ID           uint      `json:"id" gorm:"primaryKey"`
	Username     string    `json:"username" gorm:"type:varchar(255);uniqueIndex;not null"`
	PasswordHash string    `json:"-" gorm:"type:varchar(255);not null"`
	Role         string    `json:"role" gorm:"type:varchar(50);default:'user'"` // admin, user, readonly
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

type Session struct {
	ID        uint      `json:"id" gorm:"primaryKey"`
	UserID    uint      `json:"user_id" gorm:"not null;index"`
	Token     string    `json:"token" gorm:"type:varchar(500);uniqueIndex;not null"`
	ExpiresAt time.Time `json:"expires_at" gorm:"not null;index"`
	CreatedAt time.Time `json:"created_at"`
	User      User      `json:"user,omitempty" gorm:"foreignKey:UserID"`
}

type AuditLog struct {
	ID         uint      `json:"id" gorm:"primaryKey"`
	UserID     uint      `json:"user_id" gorm:"index"`
	Action     string    `json:"action" gorm:"type:varchar(50);not null"` // login, logout, create, update, delete
	Resource   string    `json:"resource" gorm:"type:varchar(100)"`       // phpfpm, nginx, mysql, etc.
	ResourceID string    `json:"resource_id" gorm:"type:varchar(255)"`
	Details    string    `json:"details" gorm:"type:text"` // JSON or text details
	IPAddress  string    `json:"ip_address" gorm:"type:varchar(45)"`
	UserAgent  string    `json:"user_agent" gorm:"type:varchar(500)"`
	CreatedAt  time.Time `json:"created_at" gorm:"index"`
	User       User      `json:"user,omitempty" gorm:"foreignKey:UserID"`
}
