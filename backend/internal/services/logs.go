package services

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

type LogsService struct {
	nginxLogsPath string
}

type LogEntry struct {
	Timestamp string `json:"timestamp"`
	Level     string `json:"level"`
	Message   string `json:"message"`
	Source    string `json:"source"`
}

func NewLogsService(nginxLogsPath string) *LogsService {
	return &LogsService{
		nginxLogsPath: nginxLogsPath,
	}
}

// GetSystemLogs reads system logs using journalctl
func (s *LogsService) GetSystemLogs(unit string, lines int) ([]string, error) {
	args := []string{"-n", strconv.Itoa(lines), "--no-pager"}
	if unit != "" {
		args = append(args, "-u", unit)
	}

	cmd := exec.Command("journalctl", args...)
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to read system logs: %w", err)
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

// GetNginxLogs reads Nginx logs
func (s *LogsService) GetNginxLogs(logType string, lines int) ([]string, error) {
	var logFile string

	switch logType {
	case "access":
		logFile = fmt.Sprintf("%s/access.log", s.nginxLogsPath)
	case "error":
		logFile = fmt.Sprintf("%s/error.log", s.nginxLogsPath)
	default:
		return nil, fmt.Errorf("invalid log type: %s", logType)
	}

	cmd := exec.Command("tail", "-n", strconv.Itoa(lines), logFile)
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

// GetPHPFPMLogs reads PHP-FPM logs
func (s *LogsService) GetPHPFPMLogs(phpVersion string, lines int) ([]string, error) {
	logFile := fmt.Sprintf("/var/log/php%s-fpm.log", phpVersion)

	cmd := exec.Command("tail", "-n", strconv.Itoa(lines), logFile)
	output, err := cmd.Output()
	if err != nil {
		// Try alternative log path
		logFile = fmt.Sprintf("/var/log/php/php%s-fpm.log", phpVersion)
		cmd := exec.Command("tail", "-n", strconv.Itoa(lines), logFile)
		output, err = cmd.Output()
		if err != nil {
			return nil, fmt.Errorf("failed to read PHP-FPM logs: %w", err)
		}
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

// TailLogs tails a log file (returns last N lines)
func (s *LogsService) TailLogs(source, logFile string, lines int) ([]string, error) {
	switch source {
	case "system":
		return s.GetSystemLogs("", lines)
	case "nginx-access":
		return s.GetNginxLogs("access", lines)
	case "nginx-error":
		return s.GetNginxLogs("error", lines)
	case "phpfpm":
		return s.GetPHPFPMLogs("8.1", lines) // Default to 8.1, could be parameterized
	default:
		// Try to read file directly
		data, err := os.ReadFile(logFile)
		if err != nil {
			return nil, fmt.Errorf("failed to read log file: %w", err)
		}

		logLines := strings.Split(string(data), "\n")
		if len(logLines) > lines {
			logLines = logLines[len(logLines)-lines:]
		}

		var result []string
		for _, line := range logLines {
			if strings.TrimSpace(line) != "" {
				result = append(result, line)
			}
		}

		return result, nil
	}
}
