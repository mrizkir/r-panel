package models

import (
	"database/sql/driver"
	"encoding/json"
	"time"
)

// Client represents a client (user with role "user" and additional information)
type Client struct {
	ID        uint      `json:"id" gorm:"primaryKey"`
	UserID    uint      `json:"user_id" gorm:"uniqueIndex;not null"`
	User      User      `json:"user,omitempty" gorm:"foreignKey:UserID"`

	// Company Info
	CompanyName string `json:"company_name" gorm:"type:varchar(255)"`
	VATID       string `json:"vat_id" gorm:"type:varchar(100)"`
	CompanyID   string `json:"company_id" gorm:"type:varchar(100)"`

	// Contact Info
	Gender          string `json:"gender" gorm:"type:varchar(1)"` // m or f
	ContactFirstname string `json:"contact_firstname" gorm:"type:varchar(255)"`
	ContactName     string `json:"contact_name" gorm:"type:varchar(255);not null"`
	Email           string `json:"email" gorm:"type:varchar(255);not null;index"`
	Telephone       string `json:"telephone" gorm:"type:varchar(50)"`
	Mobile          string `json:"mobile" gorm:"type:varchar(50)"`
	Fax             string `json:"fax" gorm:"type:varchar(50)"`

	// Address
	Street  string `json:"street" gorm:"type:varchar(255)"`
	ZIP     string `json:"zip" gorm:"type:varchar(20)"`
	City    string `json:"city" gorm:"type:varchar(100)"`
	State   string `json:"state" gorm:"type:varchar(100)"`
	Country string `json:"country" gorm:"type:varchar(2)"` // ISO country code

	// Bank Info
	BankAccountOwner   string `json:"bank_account_owner" gorm:"type:varchar(255)"`
	BankAccountNumber  string `json:"bank_account_number" gorm:"type:varchar(100)"`
	BankCode           string `json:"bank_code" gorm:"type:varchar(50)"`
	BankName           string `json:"bank_name" gorm:"type:varchar(255)"`
	BankAccountIBAN    string `json:"bank_account_iban" gorm:"type:varchar(50)"`
	BankAccountSWIFT   string `json:"bank_account_swift" gorm:"type:varchar(50)"`

	// Settings
	CustomerNo   string `json:"customer_no" gorm:"type:varchar(50);uniqueIndex"`
	LinuxUsername string `json:"linux_username" gorm:"type:varchar(255);index"` // Linux system username
	Language     string `json:"language" gorm:"type:varchar(10);default:'en'"`
	UserTheme    string `json:"usertheme" gorm:"type:varchar(50);default:'default'"`
	Locked       bool   `json:"locked" gorm:"default:false"`
	Canceled     bool   `json:"canceled" gorm:"default:false"`

	// Metadata
	AddedDate time.Time `json:"added_date"`
	AddedBy   string    `json:"added_by" gorm:"type:varchar(255)"`
	Notes     string    `json:"notes" gorm:"type:text"`
	Internet  string    `json:"internet" gorm:"type:varchar(255)"`
	PaypalEmail string  `json:"paypal_email" gorm:"type:varchar(255)"`

	// Template/Reseller
	TemplateMaster     uint   `json:"template_master" gorm:"default:0"`
	TemplateAdditional StringArray `json:"template_additional" gorm:"type:json"`
	ParentClientID     uint   `json:"parent_client_id" gorm:"default:0"`
	Reseller           bool   `json:"reseller" gorm:"default:false"`

	// Relations
	ClientLimits ClientLimits `json:"client_limits,omitempty" gorm:"foreignKey:ClientID"`

	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// ClientLimits represents resource limits for a client
type ClientLimits struct {
	ID       uint `json:"id" gorm:"primaryKey"`
	ClientID uint `json:"client_id" gorm:"uniqueIndex;not null"`
	Client   *Client `json:"client,omitempty" gorm:"foreignKey:ClientID"`

	// Web Limits
	WebServers          StringArray `json:"web_servers" gorm:"type:json"`
	LimitWebDomain      int         `json:"limit_web_domain" gorm:"default:-1"`      // -1 = unlimited
	LimitWebQuota       int         `json:"limit_web_quota" gorm:"default:-1"`       // MB, -1 = unlimited
	LimitTrafficQuota   int         `json:"limit_traffic_quota" gorm:"default:-1"`   // MB, -1 = unlimited
	WebPHPOptions       StringArray `json:"web_php_options" gorm:"type:json"`       // ["no", "php-fpm"]
	LimitCGI            bool        `json:"limit_cgi" gorm:"default:false"`
	LimitSSI            bool        `json:"limit_ssi" gorm:"default:false"`
	LimitPerl           bool        `json:"limit_perl" gorm:"default:false"`
	LimitRuby           bool        `json:"limit_ruby" gorm:"default:false"`
	LimitPython         bool        `json:"limit_python" gorm:"default:false"`
	ForceSuExec         bool        `json:"force_suexec" gorm:"default:false"`
	LimitHTError        bool        `json:"limit_hterror" gorm:"default:false"`
	LimitWildcard       bool        `json:"limit_wildcard" gorm:"default:false"`
	LimitSSL            bool        `json:"limit_ssl" gorm:"default:false"`
	LimitSSLLetsEncrypt bool        `json:"limit_ssl_letsencrypt" gorm:"default:false"`
	LimitWebAliasdomain int         `json:"limit_web_aliasdomain" gorm:"default:-1"`
	LimitWebSubdomain    int         `json:"limit_web_subdomain" gorm:"default:-1"`
	LimitFTPUser        int         `json:"limit_ftp_user" gorm:"default:-1"`
	LimitShellUser      int         `json:"limit_shell_user" gorm:"default:0"`
	SSHChroot           StringArray `json:"ssh_chroot" gorm:"type:json"` // ["no", "jailkit"]
	LimitWebdavUser     int         `json:"limit_webdav_user" gorm:"default:0"`
	LimitBackup         bool        `json:"limit_backup" gorm:"default:false"`
	LimitDirectiveSnippets bool     `json:"limit_directive_snippets" gorm:"default:false"`

	// Email Limits
	MailServers            StringArray `json:"mail_servers" gorm:"type:json"`
	LimitMaildomain        int         `json:"limit_maildomain" gorm:"default:-1"`
	LimitMailbox           int         `json:"limit_mailbox" gorm:"default:-1"`
	LimitMailalias         int         `json:"limit_mailalias" gorm:"default:-1"`
	LimitMailaliasdomain   int         `json:"limit_mailaliasdomain" gorm:"default:-1"`
	LimitMailmailinglist   int         `json:"limit_mailmailinglist" gorm:"default:-1"`
	LimitMailforward       int         `json:"limit_mailforward" gorm:"default:-1"`
	LimitMailcatchall      int         `json:"limit_mailcatchall" gorm:"default:-1"`
	LimitMailrouting       int         `json:"limit_mailrouting" gorm:"default:0"`
	LimitMailWblist        int         `json:"limit_mail_wblist" gorm:"default:0"`
	LimitMailfilter        int         `json:"limit_mailfilter" gorm:"default:-1"`
	LimitFetchmail         int         `json:"limit_fetchmail" gorm:"default:-1"`
	LimitMailquota         int         `json:"limit_mailquota" gorm:"default:-1"` // MB
	LimitSpamfilterWblist  int         `json:"limit_spamfilter_wblist" gorm:"default:0"`
	LimitSpamfilterUser    int         `json:"limit_spamfilter_user" gorm:"default:0"`
	LimitSpamfilterPolicy  int         `json:"limit_spamfilter_policy" gorm:"default:0"`
	LimitMailBackup        bool        `json:"limit_mail_backup" gorm:"default:false"`

	// XMPP Limits
	XMPPServers        StringArray `json:"xmpp_servers" gorm:"type:json"`
	LimitXMPPDomain    int         `json:"limit_xmpp_domain" gorm:"default:-1"`
	LimitXMPPUser      int         `json:"limit_xmpp_user" gorm:"default:-1"`
	LimitXMPPMuc       bool        `json:"limit_xmpp_muc" gorm:"default:false"`
	LimitXMPPPastebin  bool        `json:"limit_xmpp_pastebin" gorm:"default:false"`
	LimitXMPPHttparchive bool      `json:"limit_xmpp_httparchive" gorm:"default:false"`
	LimitXMPPAnon      bool        `json:"limit_xmpp_anon" gorm:"default:false"`
	LimitXMPPVjud      bool        `json:"limit_xmpp_vjud" gorm:"default:false"`
	LimitXMPPProxy     bool        `json:"limit_xmpp_proxy" gorm:"default:false"`
	LimitXMPPStatus    bool        `json:"limit_xmpp_status" gorm:"default:false"`

	// Database Limits
	DBServers          StringArray `json:"db_servers" gorm:"type:json"`
	LimitDatabase      int          `json:"limit_database" gorm:"default:-1"`
	LimitDatabaseUser  int          `json:"limit_database_user" gorm:"default:-1"`
	LimitDatabaseQuota int          `json:"limit_database_quota" gorm:"default:-1"` // MB

	// Cron Limits
	LimitCron          int    `json:"limit_cron" gorm:"default:0"`
	LimitCronType      string `json:"limit_cron_type" gorm:"type:varchar(20);default:'url'"` // full, chrooted, url
	LimitCronFrequency int    `json:"limit_cron_frequency" gorm:"default:5"` // minutes

	// DNS Limits
	DNSServers            StringArray `json:"dns_servers" gorm:"type:json"`
	LimitDNSZone          int         `json:"limit_dns_zone" gorm:"default:-1"`
	DefaultSlaveDNSServer uint        `json:"default_slave_dnsserver" gorm:"default:0"`
	LimitDNSSlaveZone     int         `json:"limit_dns_slave_zone" gorm:"default:-1"`
	LimitDNSRecord        int         `json:"limit_dns_record" gorm:"default:-1"`

	// Virtualization Limits
	LimitOpenvzVM           int  `json:"limit_openvz_vm" gorm:"default:0"`
	LimitOpenvzVMTemplateID uint `json:"limit_openvz_vm_template_id" gorm:"default:0"`

	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// StringArray is a custom type for JSON array storage
type StringArray []string

// Value implements the driver.Valuer interface
func (a StringArray) Value() (driver.Value, error) {
	if len(a) == 0 {
		return "[]", nil
	}
	return json.Marshal(a)
}

// Scan implements the sql.Scanner interface
func (a *StringArray) Scan(value interface{}) error {
	if value == nil {
		*a = []string{}
		return nil
	}

	var bytes []byte
	switch v := value.(type) {
	case []byte:
		bytes = v
	case string:
		bytes = []byte(v)
	default:
		return nil
	}

	return json.Unmarshal(bytes, a)
}

