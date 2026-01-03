package services

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

type SystemStats struct {
	CPU    CPUStats    `json:"cpu"`
	Memory MemoryStats `json:"memory"`
	Disk   []DiskStats `json:"disk"`
	Uptime string      `json:"uptime"`
}

type CPUStats struct {
	UsagePercent float64 `json:"usage_percent"`
	Cores        int     `json:"cores"`
}

type MemoryStats struct {
	Total       uint64  `json:"total"`
	Used        uint64  `json:"used"`
	Free        uint64  `json:"free"`
	Cached      uint64  `json:"cached"`
	Buffers     uint64  `json:"buffers"`
	UsedPercent float64 `json:"used_percent"`
}

type DiskStats struct {
	Filesystem string `json:"filesystem"`
	Size       string `json:"size"`
	Used       string `json:"used"`
	Avail      string `json:"avail"`
	UsePercent string `json:"use_percent"`
	MountedOn  string `json:"mounted_on"`
}

type ServiceStatus struct {
	Name   string `json:"name"`
	Status string `json:"status"` // active, inactive, failed
	Active bool   `json:"active"`
}

type ProcessInfo struct {
	PID     int     `json:"pid"`
	User    string  `json:"user"`
	CPU     float64 `json:"cpu"`
	Memory  float64 `json:"memory"`
	Command string  `json:"command"`
}

type SystemService struct{}

func NewSystemService() *SystemService {
	return &SystemService{}
}

// GetStats returns current system statistics
func (s *SystemService) GetStats() (*SystemStats, error) {
	cpu, err := s.getCPUStats()
	if err != nil {
		return nil, fmt.Errorf("failed to get CPU stats: %w", err)
	}

	memory, err := s.getMemoryStats()
	if err != nil {
		return nil, fmt.Errorf("failed to get memory stats: %w", err)
	}

	disk, err := s.getDiskStats()
	if err != nil {
		return nil, fmt.Errorf("failed to get disk stats: %w", err)
	}

	uptime, err := s.getUptime()
	if err != nil {
		uptime = "unknown"
	}

	return &SystemStats{
		CPU:    *cpu,
		Memory: *memory,
		Disk:   disk,
		Uptime: uptime,
	}, nil
}

// getCPUStats reads CPU usage from /proc/stat
func (s *SystemService) getCPUStats() (*CPUStats, error) {
	// First reading
	file1, err := os.Open("/proc/stat")
	if err != nil {
		return nil, err
	}
	defer file1.Close()

	var user1, nice1, system1, idle1 int64
	scanner := bufio.NewScanner(file1)
	if scanner.Scan() {
		line := scanner.Text()
		fmt.Sscanf(line, "cpu %d %d %d %d", &user1, &nice1, &system1, &idle1)
	}

	// Wait a bit
	time.Sleep(100 * time.Millisecond)

	// Second reading
	file2, err := os.Open("/proc/stat")
	if err != nil {
		return nil, err
	}
	defer file2.Close()

	var user2, nice2, system2, idle2 int64
	scanner2 := bufio.NewScanner(file2)
	if scanner2.Scan() {
		line := scanner2.Text()
		fmt.Sscanf(line, "cpu %d %d %d %d", &user2, &nice2, &system2, &idle2)
	}

	total1 := user1 + nice1 + system1 + idle1
	total2 := user2 + nice2 + system2 + idle2
	totalDelta := total2 - total1
	idleDelta := idle2 - idle1

	var usagePercent float64
	if totalDelta > 0 {
		usagePercent = float64(totalDelta-idleDelta) / float64(totalDelta) * 100
	}

	// Get CPU cores
	cores, _ := s.getCPUCores()

	return &CPUStats{
		UsagePercent: usagePercent,
		Cores:        cores,
	}, nil
}

// getCPUCores returns number of CPU cores
func (s *SystemService) getCPUCores() (int, error) {
	data, err := os.ReadFile("/proc/cpuinfo")
	if err != nil {
		return 0, err
	}

	content := string(data)
	count := strings.Count(content, "processor")
	return count, nil
}

// getMemoryStats reads memory info from /proc/meminfo
func (s *SystemService) getMemoryStats() (*MemoryStats, error) {
	file, err := os.Open("/proc/meminfo")
	if err != nil {
		return nil, err
	}
	defer file.Close()

	stats := &MemoryStats{}
	scanner := bufio.NewScanner(file)

	for scanner.Scan() {
		line := scanner.Text()
		fields := strings.Fields(line)
		if len(fields) < 2 {
			continue
		}

		value, err := strconv.ParseUint(fields[1], 10, 64)
		if err != nil {
			continue
		}
		value *= 1024 // Convert from KB to bytes

		switch fields[0] {
		case "MemTotal:":
			stats.Total = value
		case "MemFree:":
			stats.Free = value
		case "MemAvailable:":
			// Use MemAvailable if available (Linux 3.14+)
			stats.Free = value
		case "Cached:":
			stats.Cached = value
		case "Buffers:":
			stats.Buffers = value
		}
	}

	stats.Used = stats.Total - stats.Free - stats.Cached - stats.Buffers
	if stats.Total > 0 {
		stats.UsedPercent = float64(stats.Used) / float64(stats.Total) * 100
	}

	return stats, nil
}

// getDiskStats runs df command to get disk usage
func (s *SystemService) getDiskStats() ([]DiskStats, error) {
	cmd := exec.Command("df", "-h")
	output, err := cmd.Output()
	if err != nil {
		return nil, err
	}

	var disks []DiskStats
	lines := strings.Split(string(output), "\n")

	for i, line := range lines {
		if i == 0 || strings.TrimSpace(line) == "" {
			continue // Skip header
		}

		fields := strings.Fields(line)
		if len(fields) < 6 {
			continue
		}

		disks = append(disks, DiskStats{
			Filesystem: fields[0],
			Size:       fields[1],
			Used:       fields[2],
			Avail:      fields[3],
			UsePercent: fields[4],
			MountedOn:  fields[5],
		})
	}

	return disks, nil
}

// getUptime reads system uptime
func (s *SystemService) getUptime() (string, error) {
	data, err := os.ReadFile("/proc/uptime")
	if err != nil {
		return "", err
	}

	fields := strings.Fields(string(data))
	if len(fields) < 1 {
		return "", fmt.Errorf("invalid uptime format")
	}

	uptimeSeconds, err := strconv.ParseFloat(fields[0], 64)
	if err != nil {
		return "", err
	}

	uptime := time.Duration(uptimeSeconds) * time.Second
	days := int(uptime.Hours()) / 24
	hours := int(uptime.Hours()) % 24
	minutes := int(uptime.Minutes()) % 60

	return fmt.Sprintf("%dd %dh %dm", days, hours, minutes), nil
}

// GetServiceStatus checks status of a systemd service
func (s *SystemService) GetServiceStatus(serviceName string) (*ServiceStatus, error) {
	cmd := exec.Command("systemctl", "is-active", serviceName)
	output, err := cmd.Output()
	if err != nil {
		return &ServiceStatus{
			Name:   serviceName,
			Status: "inactive",
			Active: false,
		}, nil
	}

	status := strings.TrimSpace(string(output))
	active := status == "active"

	return &ServiceStatus{
		Name:   serviceName,
		Status: status,
		Active: active,
	}, nil
}

// GetServicesStatus checks status of multiple services
func (s *SystemService) GetServicesStatus(serviceNames []string) ([]ServiceStatus, error) {
	var services []ServiceStatus

	for _, name := range serviceNames {
		status, err := s.GetServiceStatus(name)
		if err != nil {
			continue
		}
		services = append(services, *status)
	}

	return services, nil
}

// GetTopProcesses returns top processes by CPU and Memory
func (s *SystemService) GetTopProcesses(limit int) ([]ProcessInfo, error) {
	cmd := exec.Command("ps", "aux", "--sort=-%cpu", "--no-headers")
	output, err := cmd.Output()
	if err != nil {
		return nil, err
	}

	var processes []ProcessInfo
	lines := strings.Split(string(output), "\n")

	count := 0
	for _, line := range lines {
		if count >= limit {
			break
		}

		fields := strings.Fields(line)
		if len(fields) < 11 {
			continue
		}

		pid, _ := strconv.Atoi(fields[1])
		cpu, _ := strconv.ParseFloat(fields[2], 64)
		mem, _ := strconv.ParseFloat(fields[3], 64)

		command := strings.Join(fields[10:], " ")
		if len(command) > 100 {
			command = command[:100] + "..."
		}

		processes = append(processes, ProcessInfo{
			PID:     pid,
			User:    fields[0],
			CPU:     cpu,
			Memory:  mem,
			Command: command,
		})

		count++
	}

	return processes, nil
}
