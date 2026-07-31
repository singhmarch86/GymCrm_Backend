package pagination

import (
	"math"
	"net/http"
	"strconv"

	"gymcrm/internal/shared/response"
)

const (
	DefaultPage    = 1
	DefaultPerPage = 20
	MaxPerPage     = 100
)

// Params holds validated pagination parameters extracted from query string.
type Params struct {
	Page    int
	PerPage int
	Offset  int
}

// FromRequest parses ?page=&per_page= from the request URL.
// Falls back to defaults on missing/invalid values. Never errors.
func FromRequest(r *http.Request) Params {
	page := parseIntQuery(r, "page", DefaultPage)
	perPage := parseIntQuery(r, "per_page", DefaultPerPage)

	if page < 1 {
		page = 1
	}
	if perPage < 1 {
		perPage = DefaultPerPage
	}
	if perPage > MaxPerPage {
		perPage = MaxPerPage
	}

	return Params{
		Page:    page,
		PerPage: perPage,
		Offset:  (page - 1) * perPage,
	}
}

// BuildMeta constructs the response.Meta for a paginated list response.
func BuildMeta(p Params, total int64) *response.Meta {
	totalPages := int(math.Ceil(float64(total) / float64(p.PerPage)))
	if totalPages < 1 {
		totalPages = 1
	}
	return &response.Meta{
		Page:       p.Page,
		PerPage:    p.PerPage,
		Total:      total,
		TotalPages: totalPages,
	}
}

func parseIntQuery(r *http.Request, key string, defaultVal int) int {
	raw := r.URL.Query().Get(key)
	if raw == "" {
		return defaultVal
	}
	val, err := strconv.Atoi(raw)
	if err != nil {
		return defaultVal
	}
	return val
}
