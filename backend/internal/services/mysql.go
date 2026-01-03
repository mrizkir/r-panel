package services

import (
	"database/sql"
	"fmt"
	"os"
	"os/exec"
	"strings"

	_ "github.com/go-sql-driver/mysql"
)

type MySQLService struct {
	dsn string
	db  *sql.DB
}

type Database struct {
	Name string `json:"name"`
	Size string `json:"size"`
}

type MySQLUser struct {
	User       string   `json:"user"`
	Host       string   `json:"host"`
	Privileges []string `json:"privileges"`
}

func NewMySQLService(dsn string) (*MySQLService, error) {
	db, err := sql.Open("mysql", dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to MySQL: %w", err)
	}

	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping MySQL: %w", err)
	}

	return &MySQLService{
		dsn: dsn,
		db:  db,
	}, nil
}

// GetDatabases returns list of all databases
func (s *MySQLService) GetDatabases() ([]Database, error) {
	rows, err := s.db.Query("SHOW DATABASES")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var databases []Database
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			continue
		}

		// Skip system databases
		if name == "information_schema" || name == "mysql" || name == "performance_schema" || name == "sys" {
			continue
		}

		// Get database size
		size, _ := s.getDatabaseSize(name)

		databases = append(databases, Database{
			Name: name,
			Size: size,
		})
	}

	return databases, nil
}

// CreateDatabase creates a new database
func (s *MySQLService) CreateDatabase(name string) error {
	query := fmt.Sprintf("CREATE DATABASE `%s` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci", name)
	_, err := s.db.Exec(query)
	return err
}

// DeleteDatabase deletes a database
func (s *MySQLService) DeleteDatabase(name string) error {
	query := fmt.Sprintf("DROP DATABASE `%s`", name)
	_, err := s.db.Exec(query)
	return err
}

// GetUsers returns list of MySQL users
func (s *MySQLService) GetUsers() ([]MySQLUser, error) {
	rows, err := s.db.Query("SELECT User, Host FROM mysql.user")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []MySQLUser
	userMap := make(map[string]*MySQLUser)

	for rows.Next() {
		var user, host string
		if err := rows.Scan(&user, &host); err != nil {
			continue
		}

		key := fmt.Sprintf("%s@%s", user, host)
		if _, exists := userMap[key]; !exists {
			userMap[key] = &MySQLUser{
				User:       user,
				Host:       host,
				Privileges: []string{},
			}
		}
	}

	// Get privileges for each user
	for key, user := range userMap {
		privs, _ := s.getUserPrivileges(user.User, user.Host)
		user.Privileges = privs
		users = append(users, *userMap[key])
	}

	return users, nil
}

// CreateUser creates a new MySQL user
func (s *MySQLService) CreateUser(username, password, host string) error {
	query := fmt.Sprintf("CREATE USER '%s'@'%s' IDENTIFIED BY '%s'", username, host, password)
	_, err := s.db.Exec(query)
	return err
}

// DeleteUser deletes a MySQL user
func (s *MySQLService) DeleteUser(username, host string) error {
	query := fmt.Sprintf("DROP USER '%s'@'%s'", username, host)
	_, err := s.db.Exec(query)
	return err
}

// GrantPrivileges grants privileges to a user
func (s *MySQLService) GrantPrivileges(username, host, database, privileges string) error {
	var query string
	if database == "*" {
		query = fmt.Sprintf("GRANT %s ON *.* TO '%s'@'%s'", privileges, username, host)
	} else {
		query = fmt.Sprintf("GRANT %s ON `%s`.* TO '%s'@'%s'", privileges, database, username, host)
	}

	_, err := s.db.Exec(query)
	if err != nil {
		return err
	}

	_, err = s.db.Exec("FLUSH PRIVILEGES")
	return err
}

// ExecuteQuery executes a SQL query (read-only by default)
func (s *MySQLService) ExecuteQuery(query string, readOnly bool) ([]map[string]interface{}, error) {
	if readOnly && !s.isReadOnlyQuery(query) {
		return nil, fmt.Errorf("write operations are not allowed")
	}

	rows, err := s.db.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	columns, err := rows.Columns()
	if err != nil {
		return nil, err
	}

	var results []map[string]interface{}
	for rows.Next() {
		values := make([]interface{}, len(columns))
		valuePtrs := make([]interface{}, len(columns))
		for i := range values {
			valuePtrs[i] = &values[i]
		}

		if err := rows.Scan(valuePtrs...); err != nil {
			return nil, err
		}

		result := make(map[string]interface{})
		for i, col := range columns {
			result[col] = values[i]
		}
		results = append(results, result)
	}

	return results, nil
}

// ExportDatabase exports a database to SQL file
func (s *MySQLService) ExportDatabase(database, outputPath string) error {
	cmd := exec.Command("mysqldump", "--single-transaction", "--routines", "--triggers", database)
	output, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("failed to export database: %w", err)
	}

	if err := os.WriteFile(outputPath, output, 0644); err != nil {
		return fmt.Errorf("failed to write export file: %w", err)
	}

	return nil
}

// ImportDatabase imports a database from SQL file
func (s *MySQLService) ImportDatabase(database, filePath string) error {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return fmt.Errorf("failed to read import file: %w", err)
	}

	_, err = s.db.Exec(fmt.Sprintf("USE `%s`", database))
	if err != nil {
		return fmt.Errorf("failed to use database: %w", err)
	}

	// Execute SQL statements
	statements := strings.Split(string(data), ";")
	for _, stmt := range statements {
		stmt = strings.TrimSpace(stmt)
		if stmt == "" {
			continue
		}
		if _, err := s.db.Exec(stmt); err != nil {
			return fmt.Errorf("failed to execute statement: %w", err)
		}
	}

	return nil
}

// Helper functions

func (s *MySQLService) getDatabaseSize(name string) (string, error) {
	query := fmt.Sprintf(`
		SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS size_mb
		FROM information_schema.tables
		WHERE table_schema = '%s'
	`, name)

	var size sql.NullFloat64
	err := s.db.QueryRow(query).Scan(&size)
	if err != nil {
		return "0 MB", err
	}

	if size.Valid {
		return fmt.Sprintf("%.2f MB", size.Float64), nil
	}
	return "0 MB", nil
}

func (s *MySQLService) getUserPrivileges(user, host string) ([]string, error) {
	query := fmt.Sprintf("SHOW GRANTS FOR '%s'@'%s'", user, host)
	rows, err := s.db.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var privileges []string
	for rows.Next() {
		var grant string
		if err := rows.Scan(&grant); err != nil {
			continue
		}
		privileges = append(privileges, grant)
	}

	return privileges, nil
}

func (s *MySQLService) isReadOnlyQuery(query string) bool {
	query = strings.ToUpper(strings.TrimSpace(query))
	writeKeywords := []string{"INSERT", "UPDATE", "DELETE", "DROP", "CREATE", "ALTER", "TRUNCATE"}
	for _, keyword := range writeKeywords {
		if strings.HasPrefix(query, keyword) {
			return false
		}
	}
	return true
}
