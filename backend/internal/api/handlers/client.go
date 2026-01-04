package handlers

import (
	"r-panel/internal/config"
	"r-panel/internal/models"
	"r-panel/internal/services"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
)

type ClientHandler struct {
	clientService *services.ClientService
}

func NewClientHandler(cfg *config.Config) *ClientHandler {
	return &ClientHandler{
		clientService: services.NewClientService(cfg),
	}
}

type CreateClientRequest struct {
	// User fields
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`

	// Client fields
	CompanyName        string                `json:"company_name"`
	VATID              string                `json:"vat_id"`
	CompanyID          string                `json:"company_id"`
	Gender             string                `json:"gender"`
	ContactFirstname   string                `json:"contact_firstname"`
	ContactName        string                `json:"contact_name" binding:"required"`
	Email              string                `json:"email" binding:"required"`
	Telephone          string                `json:"telephone"`
	Mobile             string                `json:"mobile"`
	Fax                string                `json:"fax"`
	Street             string                `json:"street"`
	ZIP                string                `json:"zip"`
	City               string                `json:"city"`
	State              string                `json:"state"`
	Country            string                `json:"country"`
	BankAccountOwner   string                `json:"bank_account_owner"`
	BankAccountNumber  string                `json:"bank_account_number"`
	BankCode           string                `json:"bank_code"`
	BankName           string                `json:"bank_name"`
	BankAccountIBAN    string                `json:"bank_account_iban"`
	BankAccountSWIFT   string                `json:"bank_account_swift"`
	Language           string                `json:"language"`
	UserTheme          string                `json:"usertheme"`
	Locked             bool                  `json:"locked"`
	Canceled           bool                  `json:"canceled"`
	AddedDate          string                `json:"added_date"`
	AddedBy            string                `json:"added_by"`
	Notes              string                `json:"notes"`
	Internet           string                `json:"internet"`
	PaypalEmail        string                `json:"paypal_email"`
	TemplateMaster     uint                  `json:"template_master"`
	TemplateAdditional []string              `json:"template_additional"`
	ParentClientID     uint                  `json:"parent_client_id"`
	Reseller           bool                  `json:"reseller"`

	// Limits
	WebServers            []string `json:"web_servers"`
	LimitWebDomain        int      `json:"limit_web_domain"`
	LimitWebQuota         int      `json:"limit_web_quota"`
	LimitTrafficQuota     int      `json:"limit_traffic_quota"`
	WebPHPOptions         []string `json:"web_php_options"`
	LimitCGI              bool     `json:"limit_cgi"`
	LimitSSI              bool     `json:"limit_ssi"`
	LimitPerl             bool     `json:"limit_perl"`
	LimitRuby             bool     `json:"limit_ruby"`
	LimitPython           bool     `json:"limit_python"`
	ForceSuExec           bool     `json:"force_suexec"`
	LimitHTError          bool     `json:"limit_hterror"`
	LimitWildcard         bool     `json:"limit_wildcard"`
	LimitSSL              bool     `json:"limit_ssl"`
	LimitSSLLetsEncrypt   bool     `json:"limit_ssl_letsencrypt"`
	LimitWebAliasdomain   int      `json:"limit_web_aliasdomain"`
	LimitWebSubdomain     int      `json:"limit_web_subdomain"`
	LimitFTPUser          int      `json:"limit_ftp_user"`
	LimitShellUser        int      `json:"limit_shell_user"`
	SSHChroot             []string `json:"ssh_chroot"`
	LimitWebdavUser       int      `json:"limit_webdav_user"`
	LimitBackup           bool     `json:"limit_backup"`
	LimitDirectiveSnippets bool    `json:"limit_directive_snippets"`
	MailServers           []string `json:"mail_servers"`
	LimitMaildomain       int      `json:"limit_maildomain"`
	LimitMailbox          int      `json:"limit_mailbox"`
	LimitMailalias        int      `json:"limit_mailalias"`
	LimitMailaliasdomain  int      `json:"limit_mailaliasdomain"`
	LimitMailmailinglist  int      `json:"limit_mailmailinglist"`
	LimitMailforward      int      `json:"limit_mailforward"`
	LimitMailcatchall     int      `json:"limit_mailcatchall"`
	LimitMailrouting      int      `json:"limit_mailrouting"`
	LimitMailWblist       int      `json:"limit_mail_wblist"`
	LimitMailfilter       int      `json:"limit_mailfilter"`
	LimitFetchmail        int      `json:"limit_fetchmail"`
	LimitMailquota        int      `json:"limit_mailquota"`
	LimitSpamfilterWblist int      `json:"limit_spamfilter_wblist"`
	LimitSpamfilterUser   int      `json:"limit_spamfilter_user"`
	LimitSpamfilterPolicy int      `json:"limit_spamfilter_policy"`
	LimitMailBackup       bool     `json:"limit_mail_backup"`
	XMPPServers           []string `json:"xmpp_servers"`
	LimitXMPPDomain       int      `json:"limit_xmpp_domain"`
	LimitXMPPUser         int      `json:"limit_xmpp_user"`
	LimitXMPPMuc          bool     `json:"limit_xmpp_muc"`
	LimitXMPPPastebin     bool     `json:"limit_xmpp_pastebin"`
	LimitXMPPHttparchive  bool     `json:"limit_xmpp_httparchive"`
	LimitXMPPAnon         bool     `json:"limit_xmpp_anon"`
	LimitXMPPVjud          bool     `json:"limit_xmpp_vjud"`
	LimitXMPPProxy         bool     `json:"limit_xmpp_proxy"`
	LimitXMPPStatus        bool     `json:"limit_xmpp_status"`
	DBServers             []string `json:"db_servers"`
	LimitDatabase         int      `json:"limit_database"`
	LimitDatabaseUser     int      `json:"limit_database_user"`
	LimitDatabaseQuota    int      `json:"limit_database_quota"`
	LimitCron             int      `json:"limit_cron"`
	LimitCronType         string   `json:"limit_cron_type"`
	LimitCronFrequency    int      `json:"limit_cron_frequency"`
	DNSServers            []string `json:"dns_servers"`
	LimitDNSZone          int      `json:"limit_dns_zone"`
	DefaultSlaveDNSServer uint     `json:"default_slave_dnsserver"`
	LimitDNSSlaveZone     int      `json:"limit_dns_slave_zone"`
	LimitDNSRecord        int      `json:"limit_dns_record"`
	LimitOpenvzVM         int      `json:"limit_openvz_vm"`
	LimitOpenvzVMTemplateID uint   `json:"limit_openvz_vm_template_id"`
}

type UpdateClientRequest struct {
	CompanyName        *string   `json:"company_name"`
	VATID              *string   `json:"vat_id"`
	CompanyID          *string   `json:"company_id"`
	Gender             *string   `json:"gender"`
	ContactFirstname   *string   `json:"contact_firstname"`
	ContactName        *string   `json:"contact_name"`
	Email              *string   `json:"email"`
	Telephone          *string   `json:"telephone"`
	Mobile             *string   `json:"mobile"`
	Fax                *string   `json:"fax"`
	Street             *string   `json:"street"`
	ZIP                *string   `json:"zip"`
	City               *string   `json:"city"`
	State              *string   `json:"state"`
	Country            *string   `json:"country"`
	BankAccountOwner   *string   `json:"bank_account_owner"`
	BankAccountNumber  *string   `json:"bank_account_number"`
	BankCode           *string   `json:"bank_code"`
	BankName           *string   `json:"bank_name"`
	BankAccountIBAN    *string   `json:"bank_account_iban"`
	BankAccountSWIFT   *string   `json:"bank_account_swift"`
	CustomerNo         *string   `json:"customer_no"`
	Language           *string   `json:"language"`
	UserTheme          *string   `json:"usertheme"`
	Locked             *bool     `json:"locked"`
	Canceled           *bool     `json:"canceled"`
	Notes              *string   `json:"notes"`
	Internet           *string   `json:"internet"`
	PaypalEmail        *string   `json:"paypal_email"`
	TemplateMaster     *uint     `json:"template_master"`
	TemplateAdditional *[]string `json:"template_additional"`
	ParentClientID     *uint     `json:"parent_client_id"`
	Reseller           *bool     `json:"reseller"`
	Limits             *UpdateClientLimitsRequest `json:"limits"`
}

type UpdateClientLimitsRequest struct {
	WebServers            *[]string `json:"web_servers"`
	LimitWebDomain        *int      `json:"limit_web_domain"`
	LimitWebQuota         *int      `json:"limit_web_quota"`
	LimitTrafficQuota     *int      `json:"limit_traffic_quota"`
	WebPHPOptions         *[]string `json:"web_php_options"`
	LimitCGI              *bool     `json:"limit_cgi"`
	LimitSSI              *bool     `json:"limit_ssi"`
	LimitPerl             *bool     `json:"limit_perl"`
	LimitRuby             *bool     `json:"limit_ruby"`
	LimitPython           *bool     `json:"limit_python"`
	ForceSuExec           *bool     `json:"force_suexec"`
	LimitHTError          *bool     `json:"limit_hterror"`
	LimitWildcard         *bool     `json:"limit_wildcard"`
	LimitSSL              *bool     `json:"limit_ssl"`
	LimitSSLLetsEncrypt   *bool     `json:"limit_ssl_letsencrypt"`
	LimitWebAliasdomain   *int      `json:"limit_web_aliasdomain"`
	LimitWebSubdomain     *int      `json:"limit_web_subdomain"`
	LimitFTPUser          *int      `json:"limit_ftp_user"`
	LimitShellUser        *int      `json:"limit_shell_user"`
	SSHChroot             *[]string `json:"ssh_chroot"`
	LimitWebdavUser       *int      `json:"limit_webdav_user"`
	LimitBackup           *bool     `json:"limit_backup"`
	LimitDirectiveSnippets *bool    `json:"limit_directive_snippets"`
	MailServers           *[]string `json:"mail_servers"`
	LimitMaildomain       *int      `json:"limit_maildomain"`
	LimitMailbox          *int      `json:"limit_mailbox"`
	LimitMailalias        *int      `json:"limit_mailalias"`
	LimitMailaliasdomain  *int      `json:"limit_mailaliasdomain"`
	LimitMailmailinglist  *int      `json:"limit_mailmailinglist"`
	LimitMailforward      *int      `json:"limit_mailforward"`
	LimitMailcatchall     *int      `json:"limit_mailcatchall"`
	LimitMailrouting      *int      `json:"limit_mailrouting"`
	LimitMailWblist       *int      `json:"limit_mail_wblist"`
	LimitMailfilter       *int      `json:"limit_mailfilter"`
	LimitFetchmail        *int      `json:"limit_fetchmail"`
	LimitMailquota        *int      `json:"limit_mailquota"`
	LimitSpamfilterWblist *int      `json:"limit_spamfilter_wblist"`
	LimitSpamfilterUser   *int      `json:"limit_spamfilter_user"`
	LimitSpamfilterPolicy *int      `json:"limit_spamfilter_policy"`
	LimitMailBackup       *bool     `json:"limit_mail_backup"`
	XMPPServers           *[]string `json:"xmpp_servers"`
	LimitXMPPDomain       *int      `json:"limit_xmpp_domain"`
	LimitXMPPUser         *int      `json:"limit_xmpp_user"`
	LimitXMPPMuc          *bool     `json:"limit_xmpp_muc"`
	LimitXMPPPastebin     *bool     `json:"limit_xmpp_pastebin"`
	LimitXMPPHttparchive  *bool     `json:"limit_xmpp_httparchive"`
	LimitXMPPAnon         *bool     `json:"limit_xmpp_anon"`
	LimitXMPPVjud         *bool     `json:"limit_xmpp_vjud"`
	LimitXMPPProxy        *bool     `json:"limit_xmpp_proxy"`
	LimitXMPPStatus       *bool     `json:"limit_xmpp_status"`
	DBServers             *[]string `json:"db_servers"`
	LimitDatabase         *int      `json:"limit_database"`
	LimitDatabaseUser     *int      `json:"limit_database_user"`
	LimitDatabaseQuota    *int      `json:"limit_database_quota"`
	LimitCron             *int      `json:"limit_cron"`
	LimitCronType         *string   `json:"limit_cron_type"`
	LimitCronFrequency    *int      `json:"limit_cron_frequency"`
	DNSServers            *[]string `json:"dns_servers"`
	LimitDNSZone          *int      `json:"limit_dns_zone"`
	DefaultSlaveDNSServer *uint     `json:"default_slave_dnsserver"`
	LimitDNSSlaveZone     *int      `json:"limit_dns_slave_zone"`
	LimitDNSRecord        *int      `json:"limit_dns_record"`
	LimitOpenvzVM         *int      `json:"limit_openvz_vm"`
	LimitOpenvzVMTemplateID *uint  `json:"limit_openvz_vm_template_id"`
}

// GetClients returns all clients with pagination support
func (h *ClientHandler) GetClients(c *gin.Context) {
	// Check if pagination is requested
	pageParam := c.DefaultQuery("page", "")
	limitParam := c.DefaultQuery("limit", "")

	if pageParam == "" && limitParam == "" {
		// No pagination - return all clients (backward compatibility)
		clients, err := h.clientService.GetClients()
		if err != nil {
			c.JSON(500, gin.H{"error": "Failed to get clients", "details": err.Error()})
			return
		}
		c.JSON(200, gin.H{"clients": clients})
		return
	}

	// Parse pagination parameters
	page := 1
	limit := 15

	if pageParam != "" {
		if parsedPage, err := strconv.Atoi(pageParam); err == nil && parsedPage > 0 {
			page = parsedPage
		}
	}

	if limitParam != "" {
		if parsedLimit, err := strconv.Atoi(limitParam); err == nil && parsedLimit > 0 {
			limit = parsedLimit
		}
	}

	// Get paginated clients
	result, err := h.clientService.GetClientsPaginated(page, limit)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to get clients", "details": err.Error()})
		return
	}

	c.JSON(200, gin.H{
		"clients":     result.Data,
		"total":       result.Total,
		"page":        result.Page,
		"limit":       result.Limit,
		"total_pages": result.TotalPages,
	})
}

// GetClient returns a specific client
func (h *ClientHandler) GetClient(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(400, gin.H{"error": "Invalid client ID"})
		return
	}

	client, err := h.clientService.GetClient(uint(id))
	if err != nil {
		if err == services.ErrClientNotFound {
			c.JSON(404, gin.H{"error": err.Error()})
		} else {
			c.JSON(500, gin.H{"error": "Failed to get client", "details": err.Error()})
		}
		return
	}

	c.JSON(200, client)
}

// CreateClient creates a new client
func (h *ClientHandler) CreateClient(c *gin.Context) {
	var req CreateClientRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid request", "details": err.Error()})
		return
	}

	// Parse added_date if provided
	var addedDate time.Time
	if req.AddedDate != "" {
		parsed, err := time.Parse("2006-01-02", req.AddedDate)
		if err == nil {
			addedDate = parsed
		}
	}

	// Convert slices to StringArray
	data := &services.CreateClientData{
		Username:            req.Username,
		Password:             req.Password,
		CompanyName:          req.CompanyName,
		VATID:                req.VATID,
		CompanyID:            req.CompanyID,
		Gender:               req.Gender,
		ContactFirstname:     req.ContactFirstname,
		ContactName:          req.ContactName,
		Email:                req.Email,
		Telephone:            req.Telephone,
		Mobile:               req.Mobile,
		Fax:                  req.Fax,
		Street:               req.Street,
		ZIP:                  req.ZIP,
		City:                 req.City,
		State:                req.State,
		Country:              req.Country,
		BankAccountOwner:     req.BankAccountOwner,
		BankAccountNumber:    req.BankAccountNumber,
		BankCode:             req.BankCode,
		BankName:             req.BankName,
		BankAccountIBAN:      req.BankAccountIBAN,
		BankAccountSWIFT:     req.BankAccountSWIFT,
		Language:             req.Language,
		UserTheme:            req.UserTheme,
		Locked:               req.Locked,
		Canceled:             req.Canceled,
		AddedDate:            addedDate,
		AddedBy:              req.AddedBy,
		Notes:                req.Notes,
		Internet:             req.Internet,
		PaypalEmail:          req.PaypalEmail,
		TemplateMaster:       req.TemplateMaster,
		TemplateAdditional:   models.StringArray(req.TemplateAdditional),
		ParentClientID:       req.ParentClientID,
		Reseller:             req.Reseller,
		WebServers:           models.StringArray(req.WebServers),
		LimitWebDomain:       req.LimitWebDomain,
		LimitWebQuota:        req.LimitWebQuota,
		LimitTrafficQuota:    req.LimitTrafficQuota,
		WebPHPOptions:        models.StringArray(req.WebPHPOptions),
		LimitCGI:             req.LimitCGI,
		LimitSSI:             req.LimitSSI,
		LimitPerl:            req.LimitPerl,
		LimitRuby:            req.LimitRuby,
		LimitPython:          req.LimitPython,
		ForceSuExec:          req.ForceSuExec,
		LimitHTError:         req.LimitHTError,
		LimitWildcard:        req.LimitWildcard,
		LimitSSL:             req.LimitSSL,
		LimitSSLLetsEncrypt:  req.LimitSSLLetsEncrypt,
		LimitWebAliasdomain:  req.LimitWebAliasdomain,
		LimitWebSubdomain:    req.LimitWebSubdomain,
		LimitFTPUser:         req.LimitFTPUser,
		LimitShellUser:       req.LimitShellUser,
		SSHChroot:            models.StringArray(req.SSHChroot),
		LimitWebdavUser:      req.LimitWebdavUser,
		LimitBackup:          req.LimitBackup,
		LimitDirectiveSnippets: req.LimitDirectiveSnippets,
		MailServers:          models.StringArray(req.MailServers),
		LimitMaildomain:      req.LimitMaildomain,
		LimitMailbox:         req.LimitMailbox,
		LimitMailalias:       req.LimitMailalias,
		LimitMailaliasdomain: req.LimitMailaliasdomain,
		LimitMailmailinglist: req.LimitMailmailinglist,
		LimitMailforward:     req.LimitMailforward,
		LimitMailcatchall:    req.LimitMailcatchall,
		LimitMailrouting:     req.LimitMailrouting,
		LimitMailWblist:      req.LimitMailWblist,
		LimitMailfilter:      req.LimitMailfilter,
		LimitFetchmail:       req.LimitFetchmail,
		LimitMailquota:       req.LimitMailquota,
		LimitSpamfilterWblist: req.LimitSpamfilterWblist,
		LimitSpamfilterUser:  req.LimitSpamfilterUser,
		LimitSpamfilterPolicy: req.LimitSpamfilterPolicy,
		LimitMailBackup:      req.LimitMailBackup,
		XMPPServers:          models.StringArray(req.XMPPServers),
		LimitXMPPDomain:      req.LimitXMPPDomain,
		LimitXMPPUser:        req.LimitXMPPUser,
		LimitXMPPMuc:         req.LimitXMPPMuc,
		LimitXMPPPastebin:    req.LimitXMPPPastebin,
		LimitXMPPHttparchive: req.LimitXMPPHttparchive,
		LimitXMPPAnon:        req.LimitXMPPAnon,
		LimitXMPPVjud:        req.LimitXMPPVjud,
		LimitXMPPProxy:       req.LimitXMPPProxy,
		LimitXMPPStatus:      req.LimitXMPPStatus,
		DBServers:            models.StringArray(req.DBServers),
		LimitDatabase:        req.LimitDatabase,
		LimitDatabaseUser:    req.LimitDatabaseUser,
		LimitDatabaseQuota:   req.LimitDatabaseQuota,
		LimitCron:            req.LimitCron,
		LimitCronType:        req.LimitCronType,
		LimitCronFrequency:   req.LimitCronFrequency,
		DNSServers:           models.StringArray(req.DNSServers),
		LimitDNSZone:         req.LimitDNSZone,
		DefaultSlaveDNSServer: req.DefaultSlaveDNSServer,
		LimitDNSSlaveZone:    req.LimitDNSSlaveZone,
		LimitDNSRecord:       req.LimitDNSRecord,
		LimitOpenvzVM:        req.LimitOpenvzVM,
		LimitOpenvzVMTemplateID: req.LimitOpenvzVMTemplateID,
	}

	client, err := h.clientService.CreateClient(data)
	if err != nil {
		if err == services.ErrUserExists || err == services.ErrClientExists || err == services.ErrCustomerNoExists {
			c.JSON(400, gin.H{"error": err.Error()})
		} else {
			c.JSON(500, gin.H{"error": "Failed to create client", "details": err.Error()})
		}
		return
	}

	c.JSON(201, client)
}

// UpdateClient updates a client
func (h *ClientHandler) UpdateClient(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(400, gin.H{"error": "Invalid client ID"})
		return
	}

	var req UpdateClientRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid request", "details": err.Error()})
		return
	}

	// Convert request to service data
	data := &services.UpdateClientData{
		CompanyName:        req.CompanyName,
		VATID:              req.VATID,
		CompanyID:          req.CompanyID,
		Gender:             req.Gender,
		ContactFirstname:   req.ContactFirstname,
		ContactName:        req.ContactName,
		Email:              req.Email,
		Telephone:          req.Telephone,
		Mobile:             req.Mobile,
		Fax:                req.Fax,
		Street:             req.Street,
		ZIP:                req.ZIP,
		City:               req.City,
		State:              req.State,
		Country:            req.Country,
		BankAccountOwner:   req.BankAccountOwner,
		BankAccountNumber:  req.BankAccountNumber,
		BankCode:           req.BankCode,
		BankName:           req.BankName,
		BankAccountIBAN:    req.BankAccountIBAN,
		BankAccountSWIFT:    req.BankAccountSWIFT,
		CustomerNo:         req.CustomerNo,
		Language:           req.Language,
		UserTheme:          req.UserTheme,
		Locked:             req.Locked,
		Canceled:           req.Canceled,
		Notes:              req.Notes,
		Internet:           req.Internet,
		PaypalEmail:        req.PaypalEmail,
		TemplateMaster:     req.TemplateMaster,
		ParentClientID:     req.ParentClientID,
		Reseller:           req.Reseller,
	}

	if req.TemplateAdditional != nil {
		templateAdditional := models.StringArray(*req.TemplateAdditional)
		data.TemplateAdditional = &templateAdditional
	}

	// Convert limits if provided
	if req.Limits != nil {
		limitsData := &services.UpdateClientLimitsData{}
		if req.Limits.WebServers != nil {
			webServers := models.StringArray(*req.Limits.WebServers)
			limitsData.WebServers = &webServers
		}
		if req.Limits.WebPHPOptions != nil {
			webPHPOptions := models.StringArray(*req.Limits.WebPHPOptions)
			limitsData.WebPHPOptions = &webPHPOptions
		}
		if req.Limits.SSHChroot != nil {
			sshChroot := models.StringArray(*req.Limits.SSHChroot)
			limitsData.SSHChroot = &sshChroot
		}
		if req.Limits.MailServers != nil {
			mailServers := models.StringArray(*req.Limits.MailServers)
			limitsData.MailServers = &mailServers
		}
		if req.Limits.XMPPServers != nil {
			xmppServers := models.StringArray(*req.Limits.XMPPServers)
			limitsData.XMPPServers = &xmppServers
		}
		if req.Limits.DBServers != nil {
			dbServers := models.StringArray(*req.Limits.DBServers)
			limitsData.DBServers = &dbServers
		}
		if req.Limits.DNSServers != nil {
			dnsServers := models.StringArray(*req.Limits.DNSServers)
			limitsData.DNSServers = &dnsServers
		}

		// Copy all other limit fields
		limitsData.LimitWebDomain = req.Limits.LimitWebDomain
		limitsData.LimitWebQuota = req.Limits.LimitWebQuota
		limitsData.LimitTrafficQuota = req.Limits.LimitTrafficQuota
		limitsData.LimitCGI = req.Limits.LimitCGI
		limitsData.LimitSSI = req.Limits.LimitSSI
		limitsData.LimitPerl = req.Limits.LimitPerl
		limitsData.LimitRuby = req.Limits.LimitRuby
		limitsData.LimitPython = req.Limits.LimitPython
		limitsData.ForceSuExec = req.Limits.ForceSuExec
		limitsData.LimitHTError = req.Limits.LimitHTError
		limitsData.LimitWildcard = req.Limits.LimitWildcard
		limitsData.LimitSSL = req.Limits.LimitSSL
		limitsData.LimitSSLLetsEncrypt = req.Limits.LimitSSLLetsEncrypt
		limitsData.LimitWebAliasdomain = req.Limits.LimitWebAliasdomain
		limitsData.LimitWebSubdomain = req.Limits.LimitWebSubdomain
		limitsData.LimitFTPUser = req.Limits.LimitFTPUser
		limitsData.LimitShellUser = req.Limits.LimitShellUser
		limitsData.LimitWebdavUser = req.Limits.LimitWebdavUser
		limitsData.LimitBackup = req.Limits.LimitBackup
		limitsData.LimitDirectiveSnippets = req.Limits.LimitDirectiveSnippets
		limitsData.LimitMaildomain = req.Limits.LimitMaildomain
		limitsData.LimitMailbox = req.Limits.LimitMailbox
		limitsData.LimitMailalias = req.Limits.LimitMailalias
		limitsData.LimitMailaliasdomain = req.Limits.LimitMailaliasdomain
		limitsData.LimitMailmailinglist = req.Limits.LimitMailmailinglist
		limitsData.LimitMailforward = req.Limits.LimitMailforward
		limitsData.LimitMailcatchall = req.Limits.LimitMailcatchall
		limitsData.LimitMailrouting = req.Limits.LimitMailrouting
		limitsData.LimitMailWblist = req.Limits.LimitMailWblist
		limitsData.LimitMailfilter = req.Limits.LimitMailfilter
		limitsData.LimitFetchmail = req.Limits.LimitFetchmail
		limitsData.LimitMailquota = req.Limits.LimitMailquota
		limitsData.LimitSpamfilterWblist = req.Limits.LimitSpamfilterWblist
		limitsData.LimitSpamfilterUser = req.Limits.LimitSpamfilterUser
		limitsData.LimitSpamfilterPolicy = req.Limits.LimitSpamfilterPolicy
		limitsData.LimitMailBackup = req.Limits.LimitMailBackup
		limitsData.LimitXMPPDomain = req.Limits.LimitXMPPDomain
		limitsData.LimitXMPPUser = req.Limits.LimitXMPPUser
		limitsData.LimitXMPPMuc = req.Limits.LimitXMPPMuc
		limitsData.LimitXMPPPastebin = req.Limits.LimitXMPPPastebin
		limitsData.LimitXMPPHttparchive = req.Limits.LimitXMPPHttparchive
		limitsData.LimitXMPPAnon = req.Limits.LimitXMPPAnon
		limitsData.LimitXMPPVjud = req.Limits.LimitXMPPVjud
		limitsData.LimitXMPPProxy = req.Limits.LimitXMPPProxy
		limitsData.LimitXMPPStatus = req.Limits.LimitXMPPStatus
		limitsData.LimitDatabase = req.Limits.LimitDatabase
		limitsData.LimitDatabaseUser = req.Limits.LimitDatabaseUser
		limitsData.LimitDatabaseQuota = req.Limits.LimitDatabaseQuota
		limitsData.LimitCron = req.Limits.LimitCron
		limitsData.LimitCronType = req.Limits.LimitCronType
		limitsData.LimitCronFrequency = req.Limits.LimitCronFrequency
		limitsData.LimitDNSZone = req.Limits.LimitDNSZone
		limitsData.DefaultSlaveDNSServer = req.Limits.DefaultSlaveDNSServer
		limitsData.LimitDNSSlaveZone = req.Limits.LimitDNSSlaveZone
		limitsData.LimitDNSRecord = req.Limits.LimitDNSRecord
		limitsData.LimitOpenvzVM = req.Limits.LimitOpenvzVM
		limitsData.LimitOpenvzVMTemplateID = req.Limits.LimitOpenvzVMTemplateID

		data.Limits = limitsData
	}

	client, err := h.clientService.UpdateClient(uint(id), data)
	if err != nil {
		if err == services.ErrClientNotFound || err == services.ErrClientExists || err == services.ErrCustomerNoExists {
			c.JSON(400, gin.H{"error": err.Error()})
		} else {
			c.JSON(500, gin.H{"error": "Failed to update client", "details": err.Error()})
		}
		return
	}

	c.JSON(200, client)
}

// UpdateClientLimits updates only the limits for a client
func (h *ClientHandler) UpdateClientLimits(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(400, gin.H{"error": "Invalid client ID"})
		return
	}

	var req UpdateClientLimitsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "Invalid request", "details": err.Error()})
		return
	}

	// Convert request to service data
	limitsData := &services.UpdateClientLimitsData{}

	if req.WebServers != nil {
		webServers := models.StringArray(*req.WebServers)
		limitsData.WebServers = &webServers
	}
	if req.WebPHPOptions != nil {
		webPHPOptions := models.StringArray(*req.WebPHPOptions)
		limitsData.WebPHPOptions = &webPHPOptions
	}
	if req.SSHChroot != nil {
		sshChroot := models.StringArray(*req.SSHChroot)
		limitsData.SSHChroot = &sshChroot
	}
	if req.MailServers != nil {
		mailServers := models.StringArray(*req.MailServers)
		limitsData.MailServers = &mailServers
	}
	if req.XMPPServers != nil {
		xmppServers := models.StringArray(*req.XMPPServers)
		limitsData.XMPPServers = &xmppServers
	}
	if req.DBServers != nil {
		dbServers := models.StringArray(*req.DBServers)
		limitsData.DBServers = &dbServers
	}
	if req.DNSServers != nil {
		dnsServers := models.StringArray(*req.DNSServers)
		limitsData.DNSServers = &dnsServers
	}

	// Copy all other limit fields
	limitsData.LimitWebDomain = req.LimitWebDomain
	limitsData.LimitWebQuota = req.LimitWebQuota
	limitsData.LimitTrafficQuota = req.LimitTrafficQuota
	limitsData.LimitCGI = req.LimitCGI
	limitsData.LimitSSI = req.LimitSSI
	limitsData.LimitPerl = req.LimitPerl
	limitsData.LimitRuby = req.LimitRuby
	limitsData.LimitPython = req.LimitPython
	limitsData.ForceSuExec = req.ForceSuExec
	limitsData.LimitHTError = req.LimitHTError
	limitsData.LimitWildcard = req.LimitWildcard
	limitsData.LimitSSL = req.LimitSSL
	limitsData.LimitSSLLetsEncrypt = req.LimitSSLLetsEncrypt
	limitsData.LimitWebAliasdomain = req.LimitWebAliasdomain
	limitsData.LimitWebSubdomain = req.LimitWebSubdomain
	limitsData.LimitFTPUser = req.LimitFTPUser
	limitsData.LimitShellUser = req.LimitShellUser
	limitsData.LimitWebdavUser = req.LimitWebdavUser
	limitsData.LimitBackup = req.LimitBackup
	limitsData.LimitDirectiveSnippets = req.LimitDirectiveSnippets
	limitsData.LimitMaildomain = req.LimitMaildomain
	limitsData.LimitMailbox = req.LimitMailbox
	limitsData.LimitMailalias = req.LimitMailalias
	limitsData.LimitMailaliasdomain = req.LimitMailaliasdomain
	limitsData.LimitMailmailinglist = req.LimitMailmailinglist
	limitsData.LimitMailforward = req.LimitMailforward
	limitsData.LimitMailcatchall = req.LimitMailcatchall
	limitsData.LimitMailrouting = req.LimitMailrouting
	limitsData.LimitMailWblist = req.LimitMailWblist
	limitsData.LimitMailfilter = req.LimitMailfilter
	limitsData.LimitFetchmail = req.LimitFetchmail
	limitsData.LimitMailquota = req.LimitMailquota
	limitsData.LimitSpamfilterWblist = req.LimitSpamfilterWblist
	limitsData.LimitSpamfilterUser = req.LimitSpamfilterUser
	limitsData.LimitSpamfilterPolicy = req.LimitSpamfilterPolicy
	limitsData.LimitMailBackup = req.LimitMailBackup
	limitsData.LimitXMPPDomain = req.LimitXMPPDomain
	limitsData.LimitXMPPUser = req.LimitXMPPUser
	limitsData.LimitXMPPMuc = req.LimitXMPPMuc
	limitsData.LimitXMPPPastebin = req.LimitXMPPPastebin
	limitsData.LimitXMPPHttparchive = req.LimitXMPPHttparchive
	limitsData.LimitXMPPAnon = req.LimitXMPPAnon
	limitsData.LimitXMPPVjud = req.LimitXMPPVjud
	limitsData.LimitXMPPProxy = req.LimitXMPPProxy
	limitsData.LimitXMPPStatus = req.LimitXMPPStatus
	limitsData.LimitDatabase = req.LimitDatabase
	limitsData.LimitDatabaseUser = req.LimitDatabaseUser
	limitsData.LimitDatabaseQuota = req.LimitDatabaseQuota
	limitsData.LimitCron = req.LimitCron
	limitsData.LimitCronType = req.LimitCronType
	limitsData.LimitCronFrequency = req.LimitCronFrequency
	limitsData.LimitDNSZone = req.LimitDNSZone
	limitsData.DefaultSlaveDNSServer = req.DefaultSlaveDNSServer
	limitsData.LimitDNSSlaveZone = req.LimitDNSSlaveZone
	limitsData.LimitDNSRecord = req.LimitDNSRecord
	limitsData.LimitOpenvzVM = req.LimitOpenvzVM
	limitsData.LimitOpenvzVMTemplateID = req.LimitOpenvzVMTemplateID

	if err := h.clientService.UpdateClientLimits(uint(id), limitsData); err != nil {
		if err == services.ErrClientNotFound {
			c.JSON(404, gin.H{"error": err.Error()})
		} else {
			c.JSON(500, gin.H{"error": "Failed to update client limits", "details": err.Error()})
		}
		return
	}

	// Return updated client with limits
	client, err := h.clientService.GetClient(uint(id))
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to get updated client", "details": err.Error()})
		return
	}

	c.JSON(200, client)
}

// DeleteClient deletes a client
func (h *ClientHandler) DeleteClient(c *gin.Context) {
	id, err := strconv.ParseUint(c.Param("id"), 10, 32)
	if err != nil {
		c.JSON(400, gin.H{"error": "Invalid client ID"})
		return
	}

	if err := h.clientService.DeleteClient(uint(id)); err != nil {
		if err == services.ErrClientNotFound {
			c.JSON(404, gin.H{"error": err.Error()})
		} else {
			c.JSON(500, gin.H{"error": "Failed to delete client", "details": err.Error()})
		}
		return
	}

	c.JSON(200, gin.H{"message": "Client deleted successfully"})
}

