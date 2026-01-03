package services

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

type PHPFPMService struct {
	poolsPath string
}

type PHPPool struct {
	Name       string `json:"name"`
	PHPVersion string `json:"php_version"`
	Path       string `json:"path"`
	Status     string `json:"status"` // active, inactive
	Config     string `json:"config"`
}

func NewPHPFPMService(poolsPath string) *PHPFPMService {
	return &PHPFPMService{
		poolsPath: poolsPath,
	}
}

// GetPHPVersions returns list of installed PHP versions
func (s *PHPFPMService) GetPHPVersions() ([]string, error) {
	var versions []string

	// Check common PHP FPM paths
	phpPaths := []string{
		"/etc/php/7.4/fpm/pool.d",
		"/etc/php/8.0/fpm/pool.d",
		"/etc/php/8.1/fpm/pool.d",
		"/etc/php/8.2/fpm/pool.d",
		"/etc/php/8.3/fpm/pool.d",
	}

	for _, path := range phpPaths {
		if _, err := os.Stat(path); err == nil {
			// Extract version from path
			parts := strings.Split(path, "/")
			if len(parts) >= 3 {
				version := parts[2]
				versions = append(versions, version)
			}
		}
	}

	return versions, nil
}

// GetPools returns all PHP-FPM pools
func (s *PHPFPMService) GetPools() ([]PHPPool, error) {
	var pools []PHPPool

	versions, err := s.GetPHPVersions()
	if err != nil {
		return nil, err
	}

	for _, version := range versions {
		poolsPath := fmt.Sprintf("/etc/php/%s/fpm/pool.d", version)
		files, err := os.ReadDir(poolsPath)
		if err != nil {
			continue
		}

		for _, entry := range files {
			if entry.IsDir() {
				continue
			}

			filename := entry.Name()
			// Skip .conf backup files and default www.conf
			if strings.HasSuffix(filename, ".conf") && filename != "www.conf" {
				poolName := strings.TrimSuffix(filename, ".conf")
				poolPath := filepath.Join(poolsPath, filename)

				config, _ := s.GetPoolConfig(version, poolName)
				status := "inactive"
				if s.isPoolActive(version, poolName) {
					status = "active"
				}

				pools = append(pools, PHPPool{
					Name:       poolName,
					PHPVersion: version,
					Path:       poolPath,
					Status:     status,
					Config:     config,
				})
			}
		}
	}

	return pools, nil
}

// GetPool returns a specific pool
func (s *PHPFPMService) GetPool(phpVersion, poolName string) (*PHPPool, error) {
	poolPath := fmt.Sprintf("/etc/php/%s/fpm/pool.d/%s.conf", phpVersion, poolName)

	_, err := os.Stat(poolPath)
	if err != nil {
		return nil, fmt.Errorf("pool not found")
	}

	config, _ := s.GetPoolConfig(phpVersion, poolName)
	status := "inactive"
	if s.isPoolActive(phpVersion, poolName) {
		status = "active"
	}

	return &PHPPool{
		Name:       poolName,
		PHPVersion: phpVersion,
		Path:       poolPath,
		Status:     status,
		Config:     config,
	}, nil
}

// GetPoolConfig reads pool configuration file
func (s *PHPFPMService) GetPoolConfig(phpVersion, poolName string) (string, error) {
	poolPath := fmt.Sprintf("/etc/php/%s/fpm/pool.d/%s.conf", phpVersion, poolName)
	data, err := os.ReadFile(poolPath)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// CreatePool creates a new PHP-FPM pool
func (s *PHPFPMService) CreatePool(phpVersion, poolName, config string) error {
	poolPath := fmt.Sprintf("/etc/php/%s/fpm/pool.d/%s.conf", phpVersion, poolName)

	// Check if pool already exists
	if _, err := os.Stat(poolPath); err == nil {
		return fmt.Errorf("pool already exists")
	}

	// Write configuration file
	if err := os.WriteFile(poolPath, []byte(config), 0644); err != nil {
		return fmt.Errorf("failed to write pool config: %w", err)
	}

	return nil
}

// UpdatePool updates an existing pool configuration
func (s *PHPFPMService) UpdatePool(phpVersion, poolName, config string) error {
	poolPath := fmt.Sprintf("/etc/php/%s/fpm/pool.d/%s.conf", phpVersion, poolName)

	// Check if pool exists
	if _, err := os.Stat(poolPath); err != nil {
		return fmt.Errorf("pool not found")
	}

	// Write configuration file
	if err := os.WriteFile(poolPath, []byte(config), 0644); err != nil {
		return fmt.Errorf("failed to write pool config: %w", err)
	}

	return nil
}

// DeletePool deletes a pool configuration
func (s *PHPFPMService) DeletePool(phpVersion, poolName string) error {
	poolPath := fmt.Sprintf("/etc/php/%s/fpm/pool.d/%s.conf", phpVersion, poolName)

	// Check if pool exists
	if _, err := os.Stat(poolPath); err != nil {
		return fmt.Errorf("pool not found")
	}

	if err := os.Remove(poolPath); err != nil {
		return fmt.Errorf("failed to delete pool: %w", err)
	}

	return nil
}

// ReloadPHPFPM reloads PHP-FPM service for a specific version
func (s *PHPFPMService) ReloadPHPFPM(phpVersion string) error {
	serviceName := fmt.Sprintf("php%s-fpm", phpVersion)
	cmd := exec.Command("systemctl", "reload", serviceName)
	return cmd.Run()
}

// TestPHPFPMConfig tests PHP-FPM configuration
func (s *PHPFPMService) TestPHPFPMConfig(phpVersion string) error {
	fpmBin := fmt.Sprintf("/usr/sbin/php-fpm%s", phpVersion)
	cmd := exec.Command(fpmBin, "-t")
	return cmd.Run()
}

// isPoolActive checks if a pool is active (simple check)
func (s *PHPFPMService) isPoolActive(phpVersion, poolName string) bool {
	poolPath := fmt.Sprintf("/etc/php/%s/fpm/pool.d/%s.conf", phpVersion, poolName)
	_, err := os.Stat(poolPath)
	return err == nil
}

// GeneratePoolConfig generates a default pool configuration
func (s *PHPFPMService) GeneratePoolConfig(poolName, user, group string) string {
	config := fmt.Sprintf(`[%s]
user = %s
group = %s
listen = /run/php/php-fpm-%s.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 35
pm.max_requests = 500

php_admin_value[memory_limit] = 128M
php_admin_value[max_execution_time] = 30
php_admin_value[disable_functions] = exec,passthru,shell_exec,system,proc_open,popen

`, poolName, user, group, poolName)
	return config
}
