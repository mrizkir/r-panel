package services

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

type NginxService struct {
	sitesAvailablePath string
	sitesEnabledPath   string
	logsPath           string
}

type NginxSite struct {
	Domain   string `json:"domain"`
	Enabled  bool   `json:"enabled"`
	Config   string `json:"config"`
	FilePath string `json:"file_path"`
}

func NewNginxService(sitesAvailable, sitesEnabled, logsPath string) *NginxService {
	return &NginxService{
		sitesAvailablePath: sitesAvailable,
		sitesEnabledPath:   sitesEnabled,
		logsPath:           logsPath,
	}
}

// GetSites returns all Nginx sites
func (s *NginxService) GetSites() ([]NginxSite, error) {
	var sites []NginxSite

	files, err := os.ReadDir(s.sitesAvailablePath)
	if err != nil {
		return nil, fmt.Errorf("failed to read sites-available: %w", err)
	}

	for _, entry := range files {
		if entry.IsDir() {
			continue
		}

		domain := entry.Name()
		filePath := filepath.Join(s.sitesAvailablePath, domain)
		enabledPath := filepath.Join(s.sitesEnabledPath, domain)

		// Check if site is enabled
		enabled := false
		if _, err := os.Stat(enabledPath); err == nil {
			enabled = true
		}

		config, _ := s.GetSiteConfig(domain)

		sites = append(sites, NginxSite{
			Domain:   domain,
			Enabled:  enabled,
			Config:   config,
			FilePath: filePath,
		})
	}

	return sites, nil
}

// GetSite returns a specific site
func (s *NginxService) GetSite(domain string) (*NginxSite, error) {
	filePath := filepath.Join(s.sitesAvailablePath, domain)

	_, err := os.Stat(filePath)
	if err != nil {
		return nil, fmt.Errorf("site not found")
	}

	enabledPath := filepath.Join(s.sitesEnabledPath, domain)
	enabled := false
	if _, err := os.Stat(enabledPath); err == nil {
		enabled = true
	}

	config, _ := s.GetSiteConfig(domain)

	return &NginxSite{
		Domain:   domain,
		Enabled:  enabled,
		Config:   config,
		FilePath: filePath,
	}, nil
}

// GetSiteConfig reads site configuration
func (s *NginxService) GetSiteConfig(domain string) (string, error) {
	filePath := filepath.Join(s.sitesAvailablePath, domain)
	data, err := os.ReadFile(filePath)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// CreateSite creates a new Nginx site
func (s *NginxService) CreateSite(domain, config string) error {
	filePath := filepath.Join(s.sitesAvailablePath, domain)

	// Check if site already exists
	if _, err := os.Stat(filePath); err == nil {
		return fmt.Errorf("site already exists")
	}

	// Write configuration file
	if err := os.WriteFile(filePath, []byte(config), 0644); err != nil {
		return fmt.Errorf("failed to write site config: %w", err)
	}

	return nil
}

// UpdateSite updates an existing site configuration
func (s *NginxService) UpdateSite(domain, config string) error {
	filePath := filepath.Join(s.sitesAvailablePath, domain)

	// Check if site exists
	if _, err := os.Stat(filePath); err != nil {
		return fmt.Errorf("site not found")
	}

	// Write configuration file
	if err := os.WriteFile(filePath, []byte(config), 0644); err != nil {
		return fmt.Errorf("failed to write site config: %w", err)
	}

	return nil
}

// DeleteSite deletes a site
func (s *NginxService) DeleteSite(domain string) error {
	availablePath := filepath.Join(s.sitesAvailablePath, domain)
	enabledPath := filepath.Join(s.sitesEnabledPath, domain)

	// Check if site exists
	if _, err := os.Stat(availablePath); err != nil {
		return fmt.Errorf("site not found")
	}

	// Remove from enabled if exists
	if _, err := os.Stat(enabledPath); err == nil {
		if err := os.Remove(enabledPath); err != nil {
			return fmt.Errorf("failed to remove enabled link: %w", err)
		}
	}

	// Remove from available
	if err := os.Remove(availablePath); err != nil {
		return fmt.Errorf("failed to delete site: %w", err)
	}

	return nil
}

// EnableSite enables a site by creating symlink
func (s *NginxService) EnableSite(domain string) error {
	availablePath := filepath.Join(s.sitesAvailablePath, domain)
	enabledPath := filepath.Join(s.sitesEnabledPath, domain)

	// Check if site exists
	if _, err := os.Stat(availablePath); err != nil {
		return fmt.Errorf("site not found")
	}

	// Check if already enabled
	if _, err := os.Stat(enabledPath); err == nil {
		return nil // Already enabled
	}

	// Create symlink
	if err := os.Symlink(availablePath, enabledPath); err != nil {
		return fmt.Errorf("failed to enable site: %w", err)
	}

	return nil
}

// DisableSite disables a site by removing symlink
func (s *NginxService) DisableSite(domain string) error {
	enabledPath := filepath.Join(s.sitesEnabledPath, domain)

	// Check if enabled
	if _, err := os.Stat(enabledPath); err != nil {
		return nil // Already disabled
	}

	// Remove symlink
	if err := os.Remove(enabledPath); err != nil {
		return fmt.Errorf("failed to disable site: %w", err)
	}

	return nil
}

// TestConfig tests Nginx configuration
func (s *NginxService) TestConfig() error {
	cmd := exec.Command("nginx", "-t")
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("nginx config test failed: %s", string(output))
	}
	return nil
}

// Reload reloads Nginx service
func (s *NginxService) Reload() error {
	cmd := exec.Command("systemctl", "reload", "nginx")
	return cmd.Run()
}

// GetLogs reads Nginx logs
func (s *NginxService) GetLogs(logType string, lines int) ([]string, error) {
	var logFile string

	switch logType {
	case "access":
		logFile = filepath.Join(s.logsPath, "access.log")
	case "error":
		logFile = filepath.Join(s.logsPath, "error.log")
	default:
		return nil, fmt.Errorf("invalid log type: %s", logType)
	}

	// Use tail command to get last N lines
	cmd := exec.Command("tail", "-n", fmt.Sprintf("%d", lines), logFile)
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to read logs: %w", err)
	}

	logLines := strings.Split(string(output), "\n")
	var result []string
	for _, line := range logLines {
		if strings.TrimSpace(line) != "" {
			result = append(result, line)
		}
	}

	return result, nil
}

// GenerateSiteConfig generates a default Nginx site configuration
func (s *NginxService) GenerateSiteConfig(domain, root, poolName string) string {
	config := fmt.Sprintf(`server {
    listen 80;
    listen [::]:80;
    server_name %s;
    root %s;
    index index.php index.html index.htm;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/%s;
    }

    location ~ /\.ht {
        deny all;
    }
}
`, domain, root, poolName)
	return config
}
