package main

import (
	"context"
	_ "embed"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"gymcrm/configs"
	"gymcrm/internal/attendance"
	"gymcrm/internal/auth"
	"gymcrm/internal/dashboard"
	"gymcrm/internal/classes"
	"gymcrm/internal/database"
	"gymcrm/internal/devseed"
	"gymcrm/internal/leads"
	"gymcrm/internal/lifecycle"
	"gymcrm/internal/members"
	"gymcrm/internal/middleware"
	"gymcrm/internal/payments"
	"gymcrm/internal/plans"
	"gymcrm/internal/renewals"
	"gymcrm/internal/reports"
	"gymcrm/internal/retention"
	"gymcrm/internal/users"
)

//go:embed docs/swagger.json
var swaggerJSON []byte

const swaggerHTML = `<!DOCTYPE html>
<html>
<head>
  <title>GymCRM API</title>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
</head>
<body>
<div id="swagger-ui"></div>
<script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
<script>
SwaggerUIBundle({
  url: "/swagger/doc.json",
  dom_id: '#swagger-ui',
  presets: [SwaggerUIBundle.presets.apis, SwaggerUIBundle.SwaggerUIStandalonePreset],
  layout: "BaseLayout",
  persistAuthorization: true
})
</script>
</body>
</html>`

func main() {
	cfg, err := configs.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	db, err := database.Connect(database.Config{
		Host:     cfg.Database.Host,
		Port:     cfg.Database.Port,
		User:     cfg.Database.User,
		Password: cfg.Database.Password,
		DBName:   cfg.Database.Name,
		SSLMode:  cfg.Database.SSLMode,
	})
	if err != nil {
		log.Fatalf("database: %v", err)
	}

	// ── Dev seed ──────────────────────────────────────────────────────────
	// Populates a demo gym/owner/members/etc. on first boot against an empty
	// database. Never runs outside development; no-ops once already seeded.
	if cfg.IsDevelopment() {
		if err := devseed.Run(context.Background(), db); err != nil {
			log.Fatalf("devseed: %v", err)
		}
	}

	// ── Wire modules ──────────────────────────────────────────────────────
	authRepo := auth.NewRepository(db)
	authSvc := auth.NewService(authRepo, cfg.JWT.Secret)
	authHandler := auth.NewHandler(authSvc)

	plansRepo := plans.NewRepository(db)
	plansSvc := plans.NewService(plansRepo)
	plansHandler := plans.NewHandler(plansSvc)

	renewalsRepo := renewals.NewRepository(db)
	renewalsSvc := renewals.NewService(renewalsRepo)
	renewalsHandler := renewals.NewHandler(renewalsSvc)

	membersRepo := members.NewRepository(db)
	membersSvc := members.NewService(membersRepo, renewalsSvc)
	membersHandler := members.NewHandler(membersSvc)

	attendanceRepo := attendance.NewRepository(db)
	attendanceSvc := attendance.NewService(attendanceRepo)
	attendanceHandler := attendance.NewHandler(attendanceSvc)

	paymentsRepo := payments.NewRepository(db)
	paymentsSvc := payments.NewService(paymentsRepo)
	paymentsHandler := payments.NewHandler(paymentsSvc)

	dashboardRepo := dashboard.NewRepository(db)
	dashboardSvc := dashboard.NewService(dashboardRepo)
	dashboardHandler := dashboard.NewHandler(dashboardSvc)

	reportsRepo := reports.NewRepository(db)
	reportsSvc := reports.NewService(reportsRepo)
	reportsHandler := reports.NewHandler(reportsSvc)

	leadsRepo := leads.NewRepository(db)
	leadsSvc := leads.NewService(leadsRepo)
	leadsHandler := leads.NewHandler(leadsSvc)

	usersRepo := users.NewRepository(db)
	usersSvc := users.NewService(usersRepo)
	usersHandler := users.NewHandler(usersSvc)

	retentionRepo := retention.NewRepository(db)
	retentionSvc := retention.NewService(retentionRepo)
	retentionHandler := retention.NewHandler(retentionSvc)

	lifecycleRepo := lifecycle.NewRepository(db)
	lifecycleSvc := lifecycle.NewService(lifecycleRepo)
	lifecycleHandler := lifecycle.NewHandler(lifecycleSvc)

	classesRepo := classes.NewRepository(db)
	classesSvc := classes.NewService(classesRepo)
	classesHandler := classes.NewHandler(classesSvc)

	// ── Router ────────────────────────────────────────────────────────────
	// Single mux. JWT applied per-handler via the jwt() helper below.
	// No double-mux indirection — every route is registered exactly once
	// directly on this mux, which avoids Go's ServeMux prefix-dispatch
	// ambiguity when combining method-qualified patterns with a forwarding mux.
	mux := http.NewServeMux()

	jwt := middleware.JWTMiddleware(cfg.JWT.Secret)

	// ── System ────────────────────────────────────────────────────────────
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"status":"ok","service":"gymcrm"}`))
	})
	mux.HandleFunc("GET /swagger/doc.json", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write(swaggerJSON)
	})
	mux.HandleFunc("GET /swagger/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		_, _ = w.Write([]byte(swaggerHTML))
	})

	// ── Auth — public ──────────────────────────────────────────────────────
	mux.HandleFunc("POST /api/v1/auth/register", authHandler.Register)
	mux.HandleFunc("POST /api/v1/auth/login", authHandler.Login)
	mux.HandleFunc("POST /api/v1/auth/refresh", authHandler.Refresh)

	// ── Auth — protected ───────────────────────────────────────────────────
	mux.Handle("GET /api/v1/auth/me", jwt(http.HandlerFunc(authHandler.Me)))
	mux.Handle("POST /api/v1/auth/logout", jwt(http.HandlerFunc(authHandler.Logout)))

	// ── Members ────────────────────────────────────────────────────────────
	mux.Handle("POST /api/v1/members", jwt(http.HandlerFunc(membersHandler.Create)))
	mux.Handle("GET /api/v1/members", jwt(http.HandlerFunc(membersHandler.List)))
	mux.Handle("GET /api/v1/members/search", jwt(http.HandlerFunc(membersHandler.Search)))
	mux.Handle("GET /api/v1/members/expiring", jwt(http.HandlerFunc(membersHandler.Expiring)))
	mux.Handle("GET /api/v1/members/renewals", jwt(http.HandlerFunc(membersHandler.DueForRenewal)))
	mux.Handle("GET /api/v1/members/{id}", jwt(http.HandlerFunc(membersHandler.GetByID)))
	mux.Handle("PUT /api/v1/members/{id}", jwt(http.HandlerFunc(membersHandler.Update)))
	mux.Handle("DELETE /api/v1/members/{id}", jwt(http.HandlerFunc(membersHandler.Delete)))
	mux.Handle("POST /api/v1/members/{id}/renew", jwt(http.HandlerFunc(membersHandler.Renew)))
	mux.Handle("GET /api/v1/members/{member_id}/renewals", jwt(http.HandlerFunc(renewalsHandler.MemberRenewals)))
	mux.Handle("GET /api/v1/members/{member_id}/payments", jwt(http.HandlerFunc(paymentsHandler.MemberPayments)))
	mux.Handle("GET /api/v1/members/{member_id}/attendance", jwt(http.HandlerFunc(attendanceHandler.ByMember)))

	// ── Plans ──────────────────────────────────────────────────────────────
	mux.Handle("POST /api/v1/plans", jwt(http.HandlerFunc(plansHandler.Create)))
	mux.Handle("GET /api/v1/plans", jwt(http.HandlerFunc(plansHandler.List)))
	mux.Handle("GET /api/v1/plans/active", jwt(http.HandlerFunc(plansHandler.ListActive)))
	mux.Handle("GET /api/v1/plans/{id}", jwt(http.HandlerFunc(plansHandler.GetByID)))
	mux.Handle("PUT /api/v1/plans/{id}", jwt(http.HandlerFunc(plansHandler.Update)))
	mux.Handle("DELETE /api/v1/plans/{id}", jwt(http.HandlerFunc(plansHandler.Delete)))

	// ── Renewals ───────────────────────────────────────────────────────────
	mux.Handle("POST /api/v1/renewals", jwt(http.HandlerFunc(renewalsHandler.Create)))
	mux.Handle("GET /api/v1/renewals", jwt(http.HandlerFunc(renewalsHandler.List)))
	mux.Handle("GET /api/v1/renewals/recent", jwt(http.HandlerFunc(renewalsHandler.Recent)))
	mux.Handle("GET /api/v1/renewals/{id}", jwt(http.HandlerFunc(renewalsHandler.GetByID)))

	// ── Attendance ─────────────────────────────────────────────────────────
	mux.Handle("POST /api/v1/attendance/checkin", jwt(http.HandlerFunc(attendanceHandler.CheckIn)))
	mux.Handle("GET /api/v1/attendance/today", jwt(http.HandlerFunc(attendanceHandler.Today)))
	mux.Handle("GET /api/v1/attendance/recent", jwt(http.HandlerFunc(attendanceHandler.Recent)))
	mux.Handle("GET /api/v1/attendance/date/{date}", jwt(http.HandlerFunc(attendanceHandler.ByDate)))

	// ── Payments ───────────────────────────────────────────────────────────
	mux.Handle("POST /api/v1/payments", jwt(http.HandlerFunc(paymentsHandler.Collect)))
	mux.Handle("GET /api/v1/payments", jwt(http.HandlerFunc(paymentsHandler.List)))
	mux.Handle("GET /api/v1/payments/summary", jwt(http.HandlerFunc(paymentsHandler.Summary)))
	mux.Handle("GET /api/v1/payments/{id}", jwt(http.HandlerFunc(paymentsHandler.GetByID)))

	// ── Dashboard ──────────────────────────────────────────────────────────
	mux.Handle("GET /api/v1/dashboard", jwt(http.HandlerFunc(dashboardHandler.GetDashboard)))

	// ── Leads ──────────────────────────────────────────────────────────────
	mux.Handle("POST /api/v1/leads", jwt(http.HandlerFunc(leadsHandler.Create)))
	mux.Handle("GET /api/v1/leads", jwt(http.HandlerFunc(leadsHandler.List)))
	mux.Handle("GET /api/v1/leads/summary", jwt(http.HandlerFunc(leadsHandler.Summary)))
	mux.Handle("GET /api/v1/leads/followups", jwt(http.HandlerFunc(leadsHandler.FollowUps)))
	mux.Handle("GET /api/v1/leads/analytics", jwt(http.HandlerFunc(leadsHandler.Analytics)))
	mux.Handle("GET /api/v1/leads/assignees", jwt(http.HandlerFunc(leadsHandler.Assignees)))
	mux.Handle("GET /api/v1/leads/{id}/activities", jwt(http.HandlerFunc(leadsHandler.ListActivities)))
	mux.Handle("POST /api/v1/leads/{id}/activities", jwt(http.HandlerFunc(leadsHandler.AddActivity)))
	mux.Handle("PATCH /api/v1/leads/{id}/assign", jwt(http.HandlerFunc(leadsHandler.Assign)))
	mux.Handle("GET /api/v1/leads/{id}", jwt(http.HandlerFunc(leadsHandler.GetByID)))
	mux.Handle("PUT /api/v1/leads/{id}", jwt(http.HandlerFunc(leadsHandler.Update)))
	mux.Handle("PATCH /api/v1/leads/{id}/status", jwt(http.HandlerFunc(leadsHandler.AdvanceStatus)))
	mux.Handle("POST /api/v1/leads/{id}/convert", jwt(http.HandlerFunc(leadsHandler.Convert)))
	mux.Handle("DELETE /api/v1/leads/{id}", jwt(http.HandlerFunc(leadsHandler.Delete)))

	// ── Staff / users ──────────────────────────────────────────────────────
	// Owner-only: staff administration (and password resets in particular)
	// must not be reachable by a regular staff account. OwnerOnly chains after
	// jwt so the tenant context is already populated when it checks the role.
	owner := func(h http.HandlerFunc) http.Handler {
		return jwt(middleware.OwnerOnly(h))
	}
	mux.Handle("GET /api/v1/users", owner(usersHandler.List))
	mux.Handle("POST /api/v1/users", owner(usersHandler.Create))
	mux.Handle("PUT /api/v1/users/{id}", owner(usersHandler.Update))
	mux.Handle("PATCH /api/v1/users/{id}/status", owner(usersHandler.SetStatus))
	mux.Handle("PATCH /api/v1/users/{id}/password", owner(usersHandler.ResetPassword))

	// ── Retention ──────────────────────────────────────────────────────────
	// Member churn-risk alerts. Scan and resolve are staff-actionable (not
	// owner-only) — chasing lapsing members is exactly front-desk work.
	mux.Handle("POST /api/v1/retention/scan", jwt(http.HandlerFunc(retentionHandler.Scan)))
	mux.Handle("GET /api/v1/retention/alerts", jwt(http.HandlerFunc(retentionHandler.ListAlerts)))
	mux.Handle("GET /api/v1/retention/summary", jwt(http.HandlerFunc(retentionHandler.Summary)))
	mux.Handle("PATCH /api/v1/retention/alerts/{id}/resolve", jwt(http.HandlerFunc(retentionHandler.Resolve)))
	mux.Handle("GET /api/v1/retention/staff-activity", jwt(http.HandlerFunc(retentionHandler.StaffActivity)))

	// ── Membership lifecycle ───────────────────────────────────────────────
	// Freeze / unfreeze / upgrade / transfer / terminate, plus the preview
	// endpoints the UI uses to show limits and costs before staff commit.
	// Rules: docs/FR-01-membership-lifecycle.md
	mux.Handle("POST /api/v1/members/{id}/freeze", jwt(http.HandlerFunc(lifecycleHandler.Freeze)))
	mux.Handle("POST /api/v1/members/{id}/unfreeze", jwt(http.HandlerFunc(lifecycleHandler.Unfreeze)))
	mux.Handle("POST /api/v1/members/{id}/upgrade", jwt(http.HandlerFunc(lifecycleHandler.Upgrade)))
	mux.Handle("POST /api/v1/members/{id}/transfer", jwt(http.HandlerFunc(lifecycleHandler.Transfer)))
	mux.Handle("POST /api/v1/members/{id}/terminate", jwt(http.HandlerFunc(lifecycleHandler.Terminate)))
	mux.Handle("GET /api/v1/members/{id}/freeze-eligibility", jwt(http.HandlerFunc(lifecycleHandler.FreezeEligibility)))
	mux.Handle("GET /api/v1/members/{id}/upgrade-quote", jwt(http.HandlerFunc(lifecycleHandler.UpgradeQuote)))
	mux.Handle("GET /api/v1/members/{id}/termination-quote", jwt(http.HandlerFunc(lifecycleHandler.TerminationQuote)))
	mux.Handle("GET /api/v1/members/{id}/lifecycle-events", jwt(http.HandlerFunc(lifecycleHandler.Timeline)))

	// ── Classes & booking ──────────────────────────────────────────────────
	// Class types, recurring schedules, materialized sessions, and member
	// bookings with waitlist. Rules: docs/FR-02-classes-booking.md
	mux.Handle("POST /api/v1/class-types", jwt(http.HandlerFunc(classesHandler.CreateClassType)))
	mux.Handle("GET /api/v1/class-types", jwt(http.HandlerFunc(classesHandler.ListClassTypes)))

	mux.Handle("POST /api/v1/class-schedules", jwt(http.HandlerFunc(classesHandler.CreateSchedule)))
	mux.Handle("GET /api/v1/class-schedules", jwt(http.HandlerFunc(classesHandler.ListSchedules)))
	mux.Handle("POST /api/v1/class-schedules/generate", jwt(http.HandlerFunc(classesHandler.GenerateUpcomingSessions)))

	mux.Handle("POST /api/v1/class-sessions", jwt(http.HandlerFunc(classesHandler.CreateAdHocSession)))
	mux.Handle("GET /api/v1/class-sessions", jwt(http.HandlerFunc(classesHandler.ListSessions)))
	mux.Handle("GET /api/v1/class-sessions/{id}", jwt(http.HandlerFunc(classesHandler.GetSession)))
	mux.Handle("PUT /api/v1/class-sessions/{id}", jwt(http.HandlerFunc(classesHandler.UpdateSession)))
	mux.Handle("POST /api/v1/class-sessions/{id}/cancel", jwt(http.HandlerFunc(classesHandler.CancelSession)))
	mux.Handle("POST /api/v1/class-sessions/{id}/complete", jwt(http.HandlerFunc(classesHandler.CompleteSession)))

	mux.Handle("POST /api/v1/class-sessions/{id}/bookings", jwt(http.HandlerFunc(classesHandler.Book)))
	mux.Handle("GET /api/v1/class-sessions/{id}/bookings", jwt(http.HandlerFunc(classesHandler.SessionBookings)))
	mux.Handle("POST /api/v1/bookings/{id}/cancel", jwt(http.HandlerFunc(classesHandler.CancelBooking)))
	mux.Handle("POST /api/v1/bookings/{id}/attendance", jwt(http.HandlerFunc(classesHandler.MarkAttendance)))
	mux.Handle("GET /api/v1/members/{member_id}/bookings", jwt(http.HandlerFunc(classesHandler.MemberBookings)))

	// ── Reports ────────────────────────────────────────────────────────────
	mux.Handle("GET /api/v1/reports/revenue", jwt(http.HandlerFunc(reportsHandler.Revenue)))
	mux.Handle("GET /api/v1/reports/members", jwt(http.HandlerFunc(reportsHandler.Members)))
	mux.Handle("GET /api/v1/reports/payments", jwt(http.HandlerFunc(reportsHandler.Payments)))
	mux.Handle("GET /api/v1/reports/renewals", jwt(http.HandlerFunc(reportsHandler.Renewals)))
	mux.Handle("GET /api/v1/reports/plans", jwt(http.HandlerFunc(reportsHandler.Plans)))

	// ── Server ────────────────────────────────────────────────────────────
	// CORS wraps the whole mux so preflight OPTIONS requests are answered before
	// they reach the router (which registers only method-qualified routes and
	// would 405 them). No-op for native clients; required for any web build.
	srv := &http.Server{
		Addr:         ":" + cfg.Server.Port,
		Handler:      middleware.CORS(cfg.CORSAllowedOrigins())(mux),
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		log.Printf("server:  http://localhost:%s", cfg.Server.Port)
		log.Printf("swagger: http://localhost:%s/swagger/", cfg.Server.Port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("server: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("server: shutting down...")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("server: forced shutdown: %v", err)
	}
	log.Println("server: stopped")
}
