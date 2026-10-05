package configs

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

// Config holds all application configuration.
// Loaded once at startup from environment variables.
// No .env file parsing — use Docker environment or system env.
type Config struct {
	Server   ServerConfig
	Database DatabaseConfig
	JWT      JWTConfig
}

type ServerConfig struct {
	Port string // e.g. "8080"
	Env  string // "development" | "production"

	// PublicBaseURL is where a gym's public advertisement page is actually
	// reachable — used only to build the page_url a gym owner is shown in
	// the app (e.g. "https://regulars.app"), never for anything the API
	// itself calls out to.
	PublicBaseURL string
}

type DatabaseConfig struct {
	Host     string
	Port     string
	User     string
	Password string
	Name     string
	SSLMode  string
}

type JWTConfig struct {
	Secret             string
	AccessTokenMinutes int
	RefreshTokenDays   int
}

// Load reads config from environment. Returns error on missing required values.
func Load() (*Config, error) {
	cfg := &Config{
		Server: ServerConfig{
			Port:          getEnv("PORT", "8080"),
			Env:           getEnv("APP_ENV", "development"),
			PublicBaseURL: getEnv("PUBLIC_BASE_URL", "http://localhost:8080"),
		},
		Database: DatabaseConfig{
			Host:     getEnv("DB_HOST", "localhost"),
			Port:     getEnv("DB_PORT", "5432"),
			User:     requireEnv("DB_USER"),
			Password: requireEnv("DB_PASSWORD"),
			Name:     requireEnv("DB_NAME"),
			SSLMode:  getEnv("DB_SSLMODE", "disable"),
		},
		JWT: JWTConfig{
			Secret:             requireEnv("JWT_SECRET"),
			AccessTokenMinutes: getEnvInt("JWT_ACCESS_TOKEN_MINUTES", 15),
			RefreshTokenDays:   getEnvInt("JWT_REFRESH_TOKEN_DAYS", 30),
		},
	}

	if err := cfg.validate(); err != nil {
		return nil, err
	}
	return cfg, nil
}

func (c *Config) validate() error {
	if len(c.JWT.Secret) < 32 {
		return fmt.Errorf("JWT_SECRET must be at least 32 characters")
	}
	return nil
}

func (c *Config) IsDevelopment() bool { return c.Server.Env == "development" }
func (c *Config) IsProduction() bool  { return c.Server.Env == "production" }

// CORSAllowedOrigins returns the origins permitted to make browser (CORS)
// requests. Development allows any origin, so a Flutter web build served from
// any localhost port can reach the API. Production requires an explicit
// comma-separated CORS_ALLOWED_ORIGINS list; when that is unset it returns nil,
// which disables CORS entirely — the correct default for native-only clients,
// and it avoids ever shipping a wide-open policy by accident.
func (c *Config) CORSAllowedOrigins() []string {
	if raw := os.Getenv("CORS_ALLOWED_ORIGINS"); raw != "" {
		return strings.Split(raw, ",")
	}
	if c.IsDevelopment() {
		return []string{"*"}
	}
	return nil
}

// ─── Registration policy ──────────────────────────────────────────────────────

// RegistrationMode describes who may create a gym on this deployment.
type RegistrationMode int

const (
	// RegistrationOpen — anyone who can reach the endpoint may create a gym.
	RegistrationOpen RegistrationMode = iota
	// RegistrationInvite — a gym may be created only with the invite code.
	RegistrationInvite
	// RegistrationClosed — nobody may create a gym over HTTP.
	RegistrationClosed
)

// Registration decides whether POST /api/v1/auth/register is usable.
//
// The endpoint creates a gym AND its owner account, and it is unauthenticated
// by necessity — there is nobody to authenticate as before the gym exists. On
// a public server that means anyone who finds the URL can write a tenant into
// the production database, so the default in production is CLOSED. Opening it
// has to be a deliberate act, not something inherited from the dev defaults.
//
// Development is unchanged and stays open, so the local workflow and the
// demo seeder keep working.
func (c *Config) Registration() RegistrationMode {
	if !c.IsProduction() {
		return RegistrationOpen
	}
	if os.Getenv("REGISTRATION_INVITE_CODE") != "" {
		return RegistrationInvite
	}
	// Self-serve signup is a legitimate business model, but it must be chosen
	// out loud rather than arrived at by forgetting to set something.
	if strings.EqualFold(os.Getenv("ALLOW_PUBLIC_REGISTRATION"), "true") {
		return RegistrationOpen
	}
	return RegistrationClosed
}

// RegistrationInviteCode is the shared secret required when Registration() is
// RegistrationInvite. Empty in every other mode.
func (c *Config) RegistrationInviteCode() string {
	return os.Getenv("REGISTRATION_INVITE_CODE")
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

func requireEnv(key string) string {
	val := os.Getenv(key)
	if val == "" {
		panic(fmt.Sprintf("required environment variable %q is not set", key))
	}
	return val
}

func getEnv(key, fallback string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return fallback
}

func getEnvInt(key string, fallback int) int {
	val := os.Getenv(key)
	if val == "" {
		return fallback
	}
	n, err := strconv.Atoi(val)
	if err != nil {
		return fallback
	}
	return n
}
