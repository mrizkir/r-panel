package services

import (
	"archive/tar"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"time"
)

type BackupService struct {
	backupsPath string
}

type BackupJob struct {
	ID        int       `json:"id"`
	Name      string    `json:"name"`
	Type      string    `json:"type"`      // file, database
	Source    string    `json:"source"`    // path or database name
	Schedule  string    `json:"schedule"`  // cron format
	Retention int       `json:"retention"` // days
	Enabled   bool      `json:"enabled"`
	LastRun   time.Time `json:"last_run"`
	NextRun   time.Time `json:"next_run"`
}

type BackupFile struct {
	Name      string    `json:"name"`
	Path      string    `json:"path"`
	Size      int64     `json:"size"`
	Type      string    `json:"type"`
	CreatedAt time.Time `json:"created_at"`
}

func NewBackupService(backupsPath string) *BackupService {
	return &BackupService{
		backupsPath: backupsPath,
	}
}

// CreateFileBackup creates a file backup (tar.gz)
func (s *BackupService) CreateFileBackup(sourcePath, backupName string) (string, error) {
	if backupName == "" {
		backupName = fmt.Sprintf("backup_%s_%d.tar.gz", filepath.Base(sourcePath), time.Now().Unix())
	}

	outputPath := filepath.Join(s.backupsPath, backupName)

	// Create tar.gz file
	file, err := os.Create(outputPath)
	if err != nil {
		return "", fmt.Errorf("failed to create backup file: %w", err)
	}
	defer file.Close()

	gzWriter := gzip.NewWriter(file)
	defer gzWriter.Close()

	tarWriter := tar.NewWriter(gzWriter)
	defer tarWriter.Close()

	// Walk source directory and add files to archive
	err = filepath.Walk(sourcePath, func(filePath string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		// Skip directories themselves, only add files
		if info.IsDir() {
			return nil
		}

		// Open file
		srcFile, err := os.Open(filePath)
		if err != nil {
			return err
		}
		defer srcFile.Close()

		// Create tar header
		header, err := tar.FileInfoHeader(info, "")
		if err != nil {
			return err
		}

		// Set relative path
		relPath, err := filepath.Rel(sourcePath, filePath)
		if err != nil {
			return err
		}
		header.Name = relPath

		// Write header
		if err := tarWriter.WriteHeader(header); err != nil {
			return err
		}

		// Copy file content
		if _, err := io.Copy(tarWriter, srcFile); err != nil {
			return err
		}

		return nil
	})

	if err != nil {
		return "", fmt.Errorf("failed to create archive: %w", err)
	}

	return outputPath, nil
}

// CreateDatabaseBackup creates a database backup using mysqldump
func (s *BackupService) CreateDatabaseBackup(database, backupName string) (string, error) {
	if backupName == "" {
		backupName = fmt.Sprintf("db_%s_%d.sql.gz", database, time.Now().Unix())
	}

	outputPath := filepath.Join(s.backupsPath, backupName)

	// Run mysqldump
	cmd := exec.Command("mysqldump", "--single-transaction", "--routines", "--triggers", database)
	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("failed to dump database: %w", err)
	}

	// Compress with gzip
	file, err := os.Create(outputPath)
	if err != nil {
		return "", fmt.Errorf("failed to create backup file: %w", err)
	}
	defer file.Close()

	gzWriter := gzip.NewWriter(file)
	defer gzWriter.Close()

	if _, err := gzWriter.Write(output); err != nil {
		return "", fmt.Errorf("failed to compress backup: %w", err)
	}

	return outputPath, nil
}

// ListBackups returns list of backup files
func (s *BackupService) ListBackups() ([]BackupFile, error) {
	files, err := os.ReadDir(s.backupsPath)
	if err != nil {
		return nil, err
	}

	var backups []BackupFile
	for _, entry := range files {
		if entry.IsDir() {
			continue
		}

		info, err := entry.Info()
		if err != nil {
			continue
		}

		backupType := "file"
		if filepath.Ext(entry.Name()) == ".sql" || filepath.Ext(entry.Name()) == ".sql.gz" {
			backupType = "database"
		}

		backups = append(backups, BackupFile{
			Name:      entry.Name(),
			Path:      filepath.Join(s.backupsPath, entry.Name()),
			Size:      info.Size(),
			Type:      backupType,
			CreatedAt: info.ModTime(),
		})
	}

	return backups, nil
}

// DeleteBackup deletes a backup file
func (s *BackupService) DeleteBackup(backupName string) error {
	backupPath := filepath.Join(s.backupsPath, backupName)
	return os.Remove(backupPath)
}

// RestoreFileBackup restores a file backup
func (s *BackupService) RestoreFileBackup(backupPath, targetPath string) error {
	// Open backup file
	file, err := os.Open(backupPath)
	if err != nil {
		return fmt.Errorf("failed to open backup file: %w", err)
	}
	defer file.Close()

	// Decompress gzip
	gzReader, err := gzip.NewReader(file)
	if err != nil {
		return fmt.Errorf("failed to read gzip: %w", err)
	}
	defer gzReader.Close()

	// Extract tar
	tarReader := tar.NewReader(gzReader)
	for {
		header, err := tarReader.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("failed to read tar: %w", err)
		}

		targetFilePath := filepath.Join(targetPath, header.Name)

		// Create directory if needed
		if header.Typeflag == tar.TypeDir {
			os.MkdirAll(targetFilePath, os.FileMode(header.Mode))
			continue
		}

		// Create file
		targetFile, err := os.Create(targetFilePath)
		if err != nil {
			return fmt.Errorf("failed to create file: %w", err)
		}

		if _, err := io.Copy(targetFile, tarReader); err != nil {
			targetFile.Close()
			return fmt.Errorf("failed to extract file: %w", err)
		}
		targetFile.Close()

		// Set permissions
		os.Chmod(targetFilePath, os.FileMode(header.Mode))
	}

	return nil
}

// CleanOldBackups removes backups older than retention days
func (s *BackupService) CleanOldBackups(retentionDays int) error {
	backups, err := s.ListBackups()
	if err != nil {
		return err
	}

	cutoffTime := time.Now().AddDate(0, 0, -retentionDays)

	for _, backup := range backups {
		if backup.CreatedAt.Before(cutoffTime) {
			if err := s.DeleteBackup(backup.Name); err != nil {
				// Log error but continue
				continue
			}
		}
	}

	return nil
}
