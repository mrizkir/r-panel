package services

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"r-panel/internal/config"
	"r-panel/internal/models"
	"strings"
	"time"

	"gorm.io/gorm"
)

var (
	ErrClientNotFound   = errors.New("client not found")
	ErrClientExists     = errors.New("client already exists")
	ErrCustomerNoExists = errors.New("customer number already exists")
)

type ClientService struct {
	authService *AuthService
}

func NewClientService(cfg *config.Config) *ClientService {
	return &ClientService{
		authService: NewAuthService(cfg),
	}
}

// GetClients returns all clients with preloaded User and ClientLimits
func (s *ClientService) GetClients() ([]models.Client, error) {
	var clients []models.Client
	if err := models.DB.Preload("User").Preload("ClientLimits").Find(&clients).Error; err != nil {
		return nil, err
	}

	// Clear password hashes
	for i := range clients {
		if clients[i].User.ID != 0 {
			clients[i].User.PasswordHash = ""
		}
	}

	return clients, nil
}

// GetClient returns a specific client by ID with preloaded User and ClientLimits
func (s *ClientService) GetClient(id uint) (*models.Client, error) {
	var client models.Client
	if err := models.DB.Preload("User").Preload("ClientLimits").First(&client, id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrClientNotFound
		}
		return nil, err
	}

	if client.User.ID != 0 {
		client.User.PasswordHash = ""
	}

	return &client, nil
}

// GetClientByUserID returns a client by User ID with preloaded ClientLimits
func (s *ClientService) GetClientByUserID(userID uint) (*models.Client, error) {
	var client models.Client
	if err := models.DB.Preload("User").Preload("ClientLimits").Where("user_id = ?", userID).First(&client).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrClientNotFound
		}
		return nil, err
	}

	if client.User.ID != 0 {
		client.User.PasswordHash = ""
	}

	return &client, nil
}

// GenerateCustomerNo generates a unique customer number
func (s *ClientService) GenerateCustomerNo() (string, error) {
	var count int64
	if err := models.DB.Model(&models.Client{}).Count(&count).Error; err != nil {
		return "", err
	}

	customerNo := fmt.Sprintf("C%d", count+1)

	// Check if it exists (shouldn't happen, but just in case)
	var existing models.Client
	if err := models.DB.Where("customer_no = ?", customerNo).First(&existing).Error; err == nil {
		// If exists, try next number
		customerNo = fmt.Sprintf("C%d", count+2)
	}

	return customerNo, nil
}

// createLinuxUser creates a Linux system user for the client
func (s *ClientService) createLinuxUser(username string, homeDir string) error {
	// Skip Linux user creation in test environment
	if os.Getenv("SKIP_LINUX_USER") == "true" || os.Getenv("TEST_MODE") == "true" {
		return nil
	}

	// Check if user already exists
	cmd := exec.Command("id", username)
	if err := cmd.Run(); err == nil {
		// User already exists, return error
		return fmt.Errorf("Linux user '%s' already exists", username)
	}

	// Create user with home directory
	// -m: create home directory
	// -s /bin/bash: set shell to bash
	// -d: specify home directory
	args := []string{"-m", "-s", "/bin/bash"}
	if homeDir != "" {
		args = append(args, "-d", homeDir)
	} else {
		// Default home directory: /home/{username}
		args = append(args, "-d", fmt.Sprintf("/home/%s", username))
	}
	args = append(args, username)

	cmd = exec.Command("useradd", args...)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to create Linux user: %s", string(output))
	}

	return nil
}

// deleteLinuxUser deletes a Linux system user
func (s *ClientService) deleteLinuxUser(username string) error {
	// Check if user exists
	cmd := exec.Command("id", username)
	if err := cmd.Run(); err != nil {
		// User doesn't exist, nothing to delete
		return nil
	}

	// Delete user and home directory
	// -r: remove home directory and mail spool
	cmd = exec.Command("userdel", "-r", username)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to delete Linux user: %s", string(output))
	}

	return nil
}

// CreateClient creates a new User, Client, and ClientLimits
func (s *ClientService) CreateClient(data *CreateClientData) (*models.Client, error) {
	// Validate required fields
	if data.Username == "" || data.Password == "" || data.Email == "" || data.ContactName == "" {
		return nil, errors.New("username, password, email, and contact_name are required")
	}

	// Check if username already exists
	var existingUser models.User
	if err := models.DB.Where("username = ?", data.Username).First(&existingUser).Error; err == nil {
		return nil, ErrUserExists
	}

	// Check if email already exists
	var existingClient models.Client
	if err := models.DB.Where("email = ?", data.Email).First(&existingClient).Error; err == nil {
		return nil, ErrClientExists
	}

	// Generate customer number
	customerNo, err := s.GenerateCustomerNo()
	if err != nil {
		return nil, err
	}

	// Create User with role "user"
	user, err := s.authService.CreateUser(data.Username, data.Password, "user")
	if err != nil {
		return nil, err
	}

	// Prepare Client data
	client := &models.Client{
		UserID:            user.ID,
		CompanyName:       data.CompanyName,
		VATID:             data.VATID,
		CompanyID:         data.CompanyID,
		Gender:            data.Gender,
		ContactFirstname:  data.ContactFirstname,
		ContactName:       data.ContactName,
		Email:             data.Email,
		Telephone:         data.Telephone,
		Mobile:            data.Mobile,
		Fax:               data.Fax,
		Street:            data.Street,
		ZIP:               data.ZIP,
		City:              data.City,
		State:             data.State,
		Country:           data.Country,
		BankAccountOwner: data.BankAccountOwner,
		BankAccountNumber: data.BankAccountNumber,
		BankCode:          data.BankCode,
		BankName:          data.BankName,
		BankAccountIBAN:   data.BankAccountIBAN,
		BankAccountSWIFT:  data.BankAccountSWIFT,
		CustomerNo:       customerNo,
		Language:          data.Language,
		UserTheme:         data.UserTheme,
		Locked:            data.Locked,
		Canceled:          data.Canceled,
		AddedDate:         data.AddedDate,
		AddedBy:           data.AddedBy,
		Notes:             data.Notes,
		Internet:          data.Internet,
		PaypalEmail:       data.PaypalEmail,
		TemplateMaster:    data.TemplateMaster,
		TemplateAdditional: data.TemplateAdditional,
		ParentClientID:    data.ParentClientID,
		Reseller:          data.Reseller,
	}

	// Set defaults
	if client.Language == "" {
		client.Language = "en"
	}
	if client.UserTheme == "" {
		client.UserTheme = "default"
	}
	if client.AddedDate.IsZero() {
		client.AddedDate = time.Now()
	}

	// Generate Linux username from client username (sanitize for Linux)
	linuxUsername := strings.ToLower(data.Username)
	// Remove invalid characters for Linux username (only allow a-z, 0-9, _, -)
	linuxUsername = strings.Map(func(r rune) rune {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '_' || r == '-' {
			return r
		}
		return -1
	}, linuxUsername)
	// Ensure username starts with a letter
	if len(linuxUsername) > 0 && (linuxUsername[0] < 'a' || linuxUsername[0] > 'z') {
		linuxUsername = "u" + linuxUsername
	}
	// Ensure minimum length
	if len(linuxUsername) < 3 {
		linuxUsername = linuxUsername + "123"
	}
	// Ensure maximum length (Linux username max is 32 chars)
	if len(linuxUsername) > 32 {
		linuxUsername = linuxUsername[:32]
	}

	// Create Linux user
	homeDir := fmt.Sprintf("/home/%s", linuxUsername)
	if err := s.createLinuxUser(linuxUsername, homeDir); err != nil {
		// Rollback: delete user if Linux user creation fails
		models.DB.Delete(user)
		return nil, fmt.Errorf("failed to create Linux user: %w", err)
	}

	client.LinuxUsername = linuxUsername

	// Create Client
	if err := models.DB.Create(client).Error; err != nil {
		// Rollback: delete Linux user and database user if client creation fails
		s.deleteLinuxUser(linuxUsername)
		models.DB.Delete(user)
		return nil, err
	}

	// Create ClientLimits
	limits := &models.ClientLimits{
		ClientID: client.ID,
		WebServers: data.WebServers,
		LimitWebDomain: data.LimitWebDomain,
		LimitWebQuota: data.LimitWebQuota,
		LimitTrafficQuota: data.LimitTrafficQuota,
		WebPHPOptions: data.WebPHPOptions,
		LimitCGI: data.LimitCGI,
		LimitSSI: data.LimitSSI,
		LimitPerl: data.LimitPerl,
		LimitRuby: data.LimitRuby,
		LimitPython: data.LimitPython,
		ForceSuExec: data.ForceSuExec,
		LimitHTError: data.LimitHTError,
		LimitWildcard: data.LimitWildcard,
		LimitSSL: data.LimitSSL,
		LimitSSLLetsEncrypt: data.LimitSSLLetsEncrypt,
		LimitWebAliasdomain: data.LimitWebAliasdomain,
		LimitWebSubdomain: data.LimitWebSubdomain,
		LimitFTPUser: data.LimitFTPUser,
		LimitShellUser: data.LimitShellUser,
		SSHChroot: data.SSHChroot,
		LimitWebdavUser: data.LimitWebdavUser,
		LimitBackup: data.LimitBackup,
		LimitDirectiveSnippets: data.LimitDirectiveSnippets,
		MailServers: data.MailServers,
		LimitMaildomain: data.LimitMaildomain,
		LimitMailbox: data.LimitMailbox,
		LimitMailalias: data.LimitMailalias,
		LimitMailaliasdomain: data.LimitMailaliasdomain,
		LimitMailmailinglist: data.LimitMailmailinglist,
		LimitMailforward: data.LimitMailforward,
		LimitMailcatchall: data.LimitMailcatchall,
		LimitMailrouting: data.LimitMailrouting,
		LimitMailWblist: data.LimitMailWblist,
		LimitMailfilter: data.LimitMailfilter,
		LimitFetchmail: data.LimitFetchmail,
		LimitMailquota: data.LimitMailquota,
		LimitSpamfilterWblist: data.LimitSpamfilterWblist,
		LimitSpamfilterUser: data.LimitSpamfilterUser,
		LimitSpamfilterPolicy: data.LimitSpamfilterPolicy,
		LimitMailBackup: data.LimitMailBackup,
		XMPPServers: data.XMPPServers,
		LimitXMPPDomain: data.LimitXMPPDomain,
		LimitXMPPUser: data.LimitXMPPUser,
		LimitXMPPMuc: data.LimitXMPPMuc,
		LimitXMPPPastebin: data.LimitXMPPPastebin,
		LimitXMPPHttparchive: data.LimitXMPPHttparchive,
		LimitXMPPAnon: data.LimitXMPPAnon,
		LimitXMPPVjud: data.LimitXMPPVjud,
		LimitXMPPProxy: data.LimitXMPPProxy,
		LimitXMPPStatus: data.LimitXMPPStatus,
		DBServers: data.DBServers,
		LimitDatabase: data.LimitDatabase,
		LimitDatabaseUser: data.LimitDatabaseUser,
		LimitDatabaseQuota: data.LimitDatabaseQuota,
		LimitCron: data.LimitCron,
		LimitCronType: data.LimitCronType,
		LimitCronFrequency: data.LimitCronFrequency,
		DNSServers: data.DNSServers,
		LimitDNSZone: data.LimitDNSZone,
		DefaultSlaveDNSServer: data.DefaultSlaveDNSServer,
		LimitDNSSlaveZone: data.LimitDNSSlaveZone,
		LimitDNSRecord: data.LimitDNSRecord,
		LimitOpenvzVM: data.LimitOpenvzVM,
		LimitOpenvzVMTemplateID: data.LimitOpenvzVMTemplateID,
	}

	// Set defaults for limits
	if limits.LimitCronType == "" {
		limits.LimitCronType = "url"
	}
	if limits.LimitCronFrequency == 0 {
		limits.LimitCronFrequency = 5
	}

	if err := models.DB.Create(limits).Error; err != nil {
		// Rollback: delete Linux user, client, and user if limits creation fails
		if client.LinuxUsername != "" {
			s.deleteLinuxUser(client.LinuxUsername)
		}
		models.DB.Delete(client)
		models.DB.Delete(user)
		return nil, err
	}

	client.ClientLimits = *limits
	client.User = *user
	client.User.PasswordHash = ""

	return client, nil
}

// UpdateClient updates client data and limits
func (s *ClientService) UpdateClient(id uint, data *UpdateClientData) (*models.Client, error) {
	var client models.Client
	if err := models.DB.Preload("User").Preload("ClientLimits").First(&client, id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return nil, ErrClientNotFound
		}
		return nil, err
	}

	// Update client fields if provided
	if data.CompanyName != nil {
		client.CompanyName = *data.CompanyName
	}
	if data.VATID != nil {
		client.VATID = *data.VATID
	}
	if data.CompanyID != nil {
		client.CompanyID = *data.CompanyID
	}
	if data.Gender != nil {
		client.Gender = *data.Gender
	}
	if data.ContactFirstname != nil {
		client.ContactFirstname = *data.ContactFirstname
	}
	if data.ContactName != nil {
		client.ContactName = *data.ContactName
	}
	if data.Email != nil {
		// Check if email is already taken by another client
		var existing models.Client
		if err := models.DB.Where("email = ? AND id != ?", *data.Email, id).First(&existing).Error; err == nil {
			return nil, ErrClientExists
		}
		client.Email = *data.Email
	}
	if data.Telephone != nil {
		client.Telephone = *data.Telephone
	}
	if data.Mobile != nil {
		client.Mobile = *data.Mobile
	}
	if data.Fax != nil {
		client.Fax = *data.Fax
	}
	if data.Street != nil {
		client.Street = *data.Street
	}
	if data.ZIP != nil {
		client.ZIP = *data.ZIP
	}
	if data.City != nil {
		client.City = *data.City
	}
	if data.State != nil {
		client.State = *data.State
	}
	if data.Country != nil {
		client.Country = *data.Country
	}
	if data.BankAccountOwner != nil {
		client.BankAccountOwner = *data.BankAccountOwner
	}
	if data.BankAccountNumber != nil {
		client.BankAccountNumber = *data.BankAccountNumber
	}
	if data.BankCode != nil {
		client.BankCode = *data.BankCode
	}
	if data.BankName != nil {
		client.BankName = *data.BankName
	}
	if data.BankAccountIBAN != nil {
		client.BankAccountIBAN = *data.BankAccountIBAN
	}
	if data.BankAccountSWIFT != nil {
		client.BankAccountSWIFT = *data.BankAccountSWIFT
	}
	if data.CustomerNo != nil {
		// Check if customer_no is already taken
		var existing models.Client
		if err := models.DB.Where("customer_no = ? AND id != ?", *data.CustomerNo, id).First(&existing).Error; err == nil {
			return nil, ErrCustomerNoExists
		}
		client.CustomerNo = *data.CustomerNo
	}
	if data.Language != nil {
		client.Language = *data.Language
	}
	if data.UserTheme != nil {
		client.UserTheme = *data.UserTheme
	}
	if data.Locked != nil {
		client.Locked = *data.Locked
	}
	if data.Canceled != nil {
		client.Canceled = *data.Canceled
	}
	if data.Notes != nil {
		client.Notes = *data.Notes
	}
	if data.Internet != nil {
		client.Internet = *data.Internet
	}
	if data.PaypalEmail != nil {
		client.PaypalEmail = *data.PaypalEmail
	}
	if data.TemplateMaster != nil {
		client.TemplateMaster = *data.TemplateMaster
	}
	if data.TemplateAdditional != nil {
		client.TemplateAdditional = *data.TemplateAdditional
	}
	if data.ParentClientID != nil {
		client.ParentClientID = *data.ParentClientID
	}
	if data.Reseller != nil {
		client.Reseller = *data.Reseller
	}

	// Update client
	if err := models.DB.Save(&client).Error; err != nil {
		return nil, err
	}

	// Update limits if provided
	if data.Limits != nil {
		if err := s.UpdateClientLimits(client.ID, data.Limits); err != nil {
			return nil, err
		}
		// Reload limits
		models.DB.Preload("ClientLimits").First(&client, id)
	}

	// Reload with relations
	models.DB.Preload("User").Preload("ClientLimits").First(&client, id)
	client.User.PasswordHash = ""

	return &client, nil
}

// UpdateClientLimits updates only the limits for a client
func (s *ClientService) UpdateClientLimits(clientID uint, data *UpdateClientLimitsData) error {
	var limits models.ClientLimits
	if err := models.DB.Where("client_id = ?", clientID).First(&limits).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			// Create if doesn't exist
			limits.ClientID = clientID
		} else {
			return err
		}
	}

	// Update all limit fields
	if data.WebServers != nil {
		limits.WebServers = *data.WebServers
	}
	if data.LimitWebDomain != nil {
		limits.LimitWebDomain = *data.LimitWebDomain
	}
	if data.LimitWebQuota != nil {
		limits.LimitWebQuota = *data.LimitWebQuota
	}
	if data.LimitTrafficQuota != nil {
		limits.LimitTrafficQuota = *data.LimitTrafficQuota
	}
	if data.WebPHPOptions != nil {
		limits.WebPHPOptions = *data.WebPHPOptions
	}
	if data.LimitCGI != nil {
		limits.LimitCGI = *data.LimitCGI
	}
	if data.LimitSSI != nil {
		limits.LimitSSI = *data.LimitSSI
	}
	if data.LimitPerl != nil {
		limits.LimitPerl = *data.LimitPerl
	}
	if data.LimitRuby != nil {
		limits.LimitRuby = *data.LimitRuby
	}
	if data.LimitPython != nil {
		limits.LimitPython = *data.LimitPython
	}
	if data.ForceSuExec != nil {
		limits.ForceSuExec = *data.ForceSuExec
	}
	if data.LimitHTError != nil {
		limits.LimitHTError = *data.LimitHTError
	}
	if data.LimitWildcard != nil {
		limits.LimitWildcard = *data.LimitWildcard
	}
	if data.LimitSSL != nil {
		limits.LimitSSL = *data.LimitSSL
	}
	if data.LimitSSLLetsEncrypt != nil {
		limits.LimitSSLLetsEncrypt = *data.LimitSSLLetsEncrypt
	}
	if data.LimitWebAliasdomain != nil {
		limits.LimitWebAliasdomain = *data.LimitWebAliasdomain
	}
	if data.LimitWebSubdomain != nil {
		limits.LimitWebSubdomain = *data.LimitWebSubdomain
	}
	if data.LimitFTPUser != nil {
		limits.LimitFTPUser = *data.LimitFTPUser
	}
	if data.LimitShellUser != nil {
		limits.LimitShellUser = *data.LimitShellUser
	}
	if data.SSHChroot != nil {
		limits.SSHChroot = *data.SSHChroot
	}
	if data.LimitWebdavUser != nil {
		limits.LimitWebdavUser = *data.LimitWebdavUser
	}
	if data.LimitBackup != nil {
		limits.LimitBackup = *data.LimitBackup
	}
	if data.LimitDirectiveSnippets != nil {
		limits.LimitDirectiveSnippets = *data.LimitDirectiveSnippets
	}
	if data.MailServers != nil {
		limits.MailServers = *data.MailServers
	}
	if data.LimitMaildomain != nil {
		limits.LimitMaildomain = *data.LimitMaildomain
	}
	if data.LimitMailbox != nil {
		limits.LimitMailbox = *data.LimitMailbox
	}
	if data.LimitMailalias != nil {
		limits.LimitMailalias = *data.LimitMailalias
	}
	if data.LimitMailaliasdomain != nil {
		limits.LimitMailaliasdomain = *data.LimitMailaliasdomain
	}
	if data.LimitMailmailinglist != nil {
		limits.LimitMailmailinglist = *data.LimitMailmailinglist
	}
	if data.LimitMailforward != nil {
		limits.LimitMailforward = *data.LimitMailforward
	}
	if data.LimitMailcatchall != nil {
		limits.LimitMailcatchall = *data.LimitMailcatchall
	}
	if data.LimitMailrouting != nil {
		limits.LimitMailrouting = *data.LimitMailrouting
	}
	if data.LimitMailWblist != nil {
		limits.LimitMailWblist = *data.LimitMailWblist
	}
	if data.LimitMailfilter != nil {
		limits.LimitMailfilter = *data.LimitMailfilter
	}
	if data.LimitFetchmail != nil {
		limits.LimitFetchmail = *data.LimitFetchmail
	}
	if data.LimitMailquota != nil {
		limits.LimitMailquota = *data.LimitMailquota
	}
	if data.LimitSpamfilterWblist != nil {
		limits.LimitSpamfilterWblist = *data.LimitSpamfilterWblist
	}
	if data.LimitSpamfilterUser != nil {
		limits.LimitSpamfilterUser = *data.LimitSpamfilterUser
	}
	if data.LimitSpamfilterPolicy != nil {
		limits.LimitSpamfilterPolicy = *data.LimitSpamfilterPolicy
	}
	if data.LimitMailBackup != nil {
		limits.LimitMailBackup = *data.LimitMailBackup
	}
	if data.XMPPServers != nil {
		limits.XMPPServers = *data.XMPPServers
	}
	if data.LimitXMPPDomain != nil {
		limits.LimitXMPPDomain = *data.LimitXMPPDomain
	}
	if data.LimitXMPPUser != nil {
		limits.LimitXMPPUser = *data.LimitXMPPUser
	}
	if data.LimitXMPPMuc != nil {
		limits.LimitXMPPMuc = *data.LimitXMPPMuc
	}
	if data.LimitXMPPPastebin != nil {
		limits.LimitXMPPPastebin = *data.LimitXMPPPastebin
	}
	if data.LimitXMPPHttparchive != nil {
		limits.LimitXMPPHttparchive = *data.LimitXMPPHttparchive
	}
	if data.LimitXMPPAnon != nil {
		limits.LimitXMPPAnon = *data.LimitXMPPAnon
	}
	if data.LimitXMPPVjud != nil {
		limits.LimitXMPPVjud = *data.LimitXMPPVjud
	}
	if data.LimitXMPPProxy != nil {
		limits.LimitXMPPProxy = *data.LimitXMPPProxy
	}
	if data.LimitXMPPStatus != nil {
		limits.LimitXMPPStatus = *data.LimitXMPPStatus
	}
	if data.DBServers != nil {
		limits.DBServers = *data.DBServers
	}
	if data.LimitDatabase != nil {
		limits.LimitDatabase = *data.LimitDatabase
	}
	if data.LimitDatabaseUser != nil {
		limits.LimitDatabaseUser = *data.LimitDatabaseUser
	}
	if data.LimitDatabaseQuota != nil {
		limits.LimitDatabaseQuota = *data.LimitDatabaseQuota
	}
	if data.LimitCron != nil {
		limits.LimitCron = *data.LimitCron
	}
	if data.LimitCronType != nil {
		limits.LimitCronType = *data.LimitCronType
	}
	if data.LimitCronFrequency != nil {
		limits.LimitCronFrequency = *data.LimitCronFrequency
	}
	if data.DNSServers != nil {
		limits.DNSServers = *data.DNSServers
	}
	if data.LimitDNSZone != nil {
		limits.LimitDNSZone = *data.LimitDNSZone
	}
	if data.DefaultSlaveDNSServer != nil {
		limits.DefaultSlaveDNSServer = *data.DefaultSlaveDNSServer
	}
	if data.LimitDNSSlaveZone != nil {
		limits.LimitDNSSlaveZone = *data.LimitDNSSlaveZone
	}
	if data.LimitDNSRecord != nil {
		limits.LimitDNSRecord = *data.LimitDNSRecord
	}
	if data.LimitOpenvzVM != nil {
		limits.LimitOpenvzVM = *data.LimitOpenvzVM
	}
	if data.LimitOpenvzVMTemplateID != nil {
		limits.LimitOpenvzVMTemplateID = *data.LimitOpenvzVMTemplateID
	}

	return models.DB.Save(&limits).Error
}

// DeleteClient deletes a client, its limits, and the associated user
func (s *ClientService) DeleteClient(id uint) error {
	var client models.Client
	if err := models.DB.First(&client, id).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrClientNotFound
		}
		return err
	}

	// Store Linux username before deletion
	linuxUsername := client.LinuxUsername

	// Delete limits first
	models.DB.Where("client_id = ?", id).Delete(&models.ClientLimits{})

	// Delete client
	if err := models.DB.Delete(&client).Error; err != nil {
		return err
	}

	// Delete Linux user if exists
	if linuxUsername != "" {
		if err := s.deleteLinuxUser(linuxUsername); err != nil {
			// Log error but don't fail the deletion
			// The Linux user might have been manually deleted
			fmt.Printf("Warning: failed to delete Linux user '%s': %v\n", linuxUsername, err)
		}
	}

	// Delete associated user
	if client.UserID != 0 {
		if err := models.DB.Delete(&models.User{}, client.UserID).Error; err != nil {
			return err
		}
	}

	return nil
}

// Data structures for service methods

type CreateClientData struct {
	// User fields
	Username string
	Password string

	// Client fields
	CompanyName        string
	VATID              string
	CompanyID          string
	Gender             string
	ContactFirstname   string
	ContactName        string
	Email              string
	Telephone          string
	Mobile             string
	Fax                string
	Street             string
	ZIP                string
	City               string
	State              string
	Country            string
	BankAccountOwner   string
	BankAccountNumber  string
	BankCode           string
	BankName           string
	BankAccountIBAN    string
	BankAccountSWIFT   string
	Language           string
	UserTheme          string
	Locked             bool
	Canceled           bool
	AddedDate          time.Time
	AddedBy            string
	Notes              string
	Internet           string
	PaypalEmail        string
	TemplateMaster     uint
	TemplateAdditional models.StringArray
	ParentClientID     uint
	Reseller           bool

	// Limits
	WebServers            models.StringArray
	LimitWebDomain        int
	LimitWebQuota         int
	LimitTrafficQuota     int
	WebPHPOptions         models.StringArray
	LimitCGI              bool
	LimitSSI              bool
	LimitPerl             bool
	LimitRuby             bool
	LimitPython           bool
	ForceSuExec           bool
	LimitHTError          bool
	LimitWildcard         bool
	LimitSSL              bool
	LimitSSLLetsEncrypt   bool
	LimitWebAliasdomain   int
	LimitWebSubdomain     int
	LimitFTPUser          int
	LimitShellUser        int
	SSHChroot             models.StringArray
	LimitWebdavUser       int
	LimitBackup           bool
	LimitDirectiveSnippets bool
	MailServers           models.StringArray
	LimitMaildomain       int
	LimitMailbox          int
	LimitMailalias        int
	LimitMailaliasdomain  int
	LimitMailmailinglist  int
	LimitMailforward      int
	LimitMailcatchall     int
	LimitMailrouting      int
	LimitMailWblist       int
	LimitMailfilter       int
	LimitFetchmail        int
	LimitMailquota        int
	LimitSpamfilterWblist int
	LimitSpamfilterUser   int
	LimitSpamfilterPolicy int
	LimitMailBackup       bool
	XMPPServers           models.StringArray
	LimitXMPPDomain       int
	LimitXMPPUser         int
	LimitXMPPMuc          bool
	LimitXMPPPastebin     bool
	LimitXMPPHttparchive  bool
	LimitXMPPAnon         bool
	LimitXMPPVjud         bool
	LimitXMPPProxy        bool
	LimitXMPPStatus       bool
	DBServers             models.StringArray
	LimitDatabase         int
	LimitDatabaseUser     int
	LimitDatabaseQuota    int
	LimitCron             int
	LimitCronType         string
	LimitCronFrequency    int
	DNSServers            models.StringArray
	LimitDNSZone          int
	DefaultSlaveDNSServer  uint
	LimitDNSSlaveZone     int
	LimitDNSRecord        int
	LimitOpenvzVM         int
	LimitOpenvzVMTemplateID uint
}

type UpdateClientData struct {
	CompanyName        *string
	VATID              *string
	CompanyID          *string
	Gender             *string
	ContactFirstname   *string
	ContactName        *string
	Email              *string
	Telephone          *string
	Mobile             *string
	Fax                *string
	Street             *string
	ZIP                *string
	City               *string
	State              *string
	Country            *string
	BankAccountOwner   *string
	BankAccountNumber  *string
	BankCode           *string
	BankName           *string
	BankAccountIBAN    *string
	BankAccountSWIFT    *string
	CustomerNo         *string
	Language           *string
	UserTheme          *string
	Locked             *bool
	Canceled           *bool
	Notes              *string
	Internet           *string
	PaypalEmail        *string
	TemplateMaster     *uint
	TemplateAdditional *models.StringArray
	ParentClientID     *uint
	Reseller           *bool
	Limits             *UpdateClientLimitsData
}

type UpdateClientLimitsData struct {
	WebServers            *models.StringArray
	LimitWebDomain        *int
	LimitWebQuota         *int
	LimitTrafficQuota     *int
	WebPHPOptions         *models.StringArray
	LimitCGI              *bool
	LimitSSI              *bool
	LimitPerl             *bool
	LimitRuby             *bool
	LimitPython           *bool
	ForceSuExec           *bool
	LimitHTError          *bool
	LimitWildcard         *bool
	LimitSSL              *bool
	LimitSSLLetsEncrypt   *bool
	LimitWebAliasdomain   *int
	LimitWebSubdomain     *int
	LimitFTPUser          *int
	LimitShellUser        *int
	SSHChroot             *models.StringArray
	LimitWebdavUser       *int
	LimitBackup           *bool
	LimitDirectiveSnippets *bool
	MailServers           *models.StringArray
	LimitMaildomain       *int
	LimitMailbox          *int
	LimitMailalias        *int
	LimitMailaliasdomain  *int
	LimitMailmailinglist  *int
	LimitMailforward      *int
	LimitMailcatchall     *int
	LimitMailrouting      *int
	LimitMailWblist       *int
	LimitMailfilter       *int
	LimitFetchmail        *int
	LimitMailquota        *int
	LimitSpamfilterWblist *int
	LimitSpamfilterUser   *int
	LimitSpamfilterPolicy *int
	LimitMailBackup       *bool
	XMPPServers           *models.StringArray
	LimitXMPPDomain       *int
	LimitXMPPUser         *int
	LimitXMPPMuc          *bool
	LimitXMPPPastebin     *bool
	LimitXMPPHttparchive  *bool
	LimitXMPPAnon         *bool
	LimitXMPPVjud         *bool
	LimitXMPPProxy        *bool
	LimitXMPPStatus       *bool
	DBServers             *models.StringArray
	LimitDatabase         *int
	LimitDatabaseUser     *int
	LimitDatabaseQuota    *int
	LimitCron             *int
	LimitCronType         *string
	LimitCronFrequency    *int
	DNSServers            *models.StringArray
	LimitDNSZone          *int
	DefaultSlaveDNSServer  *uint
	LimitDNSSlaveZone     *int
	LimitDNSRecord        *int
	LimitOpenvzVM         *int
	LimitOpenvzVMTemplateID *uint
}

