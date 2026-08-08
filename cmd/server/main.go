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
	"gymcrm/internal/branches"
	"gymcrm/internal/dashboard"
	"gymcrm/internal/classes"
	"gymcrm/internal/database"
	"gymcrm/internal/devseed"
	"gymcrm/internal/importer"
	"gymcrm/internal/invoicing"
	"gymcrm/internal/leads"
	"gymcrm/internal/lifecycle"
	"gymcrm/internal/members"
	"gymcrm/internal/middleware"
	"gymcrm/internal/payments"
	"gymcrm/internal/plans"
	"gymcrm/internal/pos"
	"gymcrm/internal/pt"
	"gymcrm/internal/renewals"
	"gymcrm/internal/referrals"
	"gymcrm/internal/reports"
	"gymcrm/internal/retention"
	"gymcrm/internal/trainers"
	"gymcrm/internal/users"
	"gymcrm/internal/visitors"
	"gymcrm/internal/wallet"
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

	visitorsRepo := visitors.NewRepository(db)
	visitorsSvc := visitors.NewService(visitorsRepo, leadsSvc)
	visitorsHandler := visitors.NewHandler(visitorsSvc)

	referralsRepo := referrals.NewRepository(db)
	referralsSvc := referrals.NewService(referralsRepo)
	referralsHandler := referrals.NewHandler(referralsSvc)

	trainersRepo := trainers.NewRepository(db)
	trainersSvc := trainers.NewService(trainersRepo)
	trainersHandler := trainers.NewHandler(trainersSvc)

	ptRepo := pt.NewRepository(db)
	ptSvc := pt.NewService(ptRepo)
	ptHandler := pt.NewHandler(ptSvc)

	invoicingRepo := invoicing.NewRepository(db)
	invoicingSvc := invoicing.NewService(invoicingRepo)
	invoicingHandler := invoicing.NewHandler(invoicingSvc)

	importerRepo := importer.NewRepository(db)
	importerSvc := importer.NewService(importerRepo)
	importerHandler := importer.NewHandler(importerSvc)

	posRepo := pos.NewRepository(db)
	posSvc := pos.NewService(posRepo)
	posHandler := pos.NewHandler(posSvc)

	walletRepo := wallet.NewRepository(db)
	walletSvc := wallet.NewService(walletRepo)
	walletHandler := wallet.NewHandler(walletSvc)

	branchesRepo := branches.NewRepository(db)
	branchesSvc := branches.NewService(branchesRepo, cfg.JWT.Secret)
	branchesHandler := branches.NewHandler(branchesSvc)

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
	mux.Handle("PUT /api/v1/class-types/{id}", jwt(http.HandlerFunc(classesHandler.UpdateClassType)))

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

	// ── Visitors (walk-ins) ─────────────────────────────────────────────────
	mux.Handle("POST /api/v1/visitors/check-in", jwt(http.HandlerFunc(visitorsHandler.CheckIn)))
	mux.Handle("POST /api/v1/visitors/{id}/check-out", jwt(http.HandlerFunc(visitorsHandler.CheckOut)))
	mux.Handle("POST /api/v1/visitors/{id}/convert-to-lead", jwt(http.HandlerFunc(visitorsHandler.ConvertToLead)))
	mux.Handle("GET /api/v1/visitors", jwt(http.HandlerFunc(visitorsHandler.List)))

	// ── Referrals ───────────────────────────────────────────────────────────
	mux.Handle("POST /api/v1/referrals", jwt(http.HandlerFunc(referralsHandler.Create)))
	mux.Handle("GET /api/v1/referrals", jwt(http.HandlerFunc(referralsHandler.List)))
	mux.Handle("POST /api/v1/referrals/{id}/mark-joined", jwt(http.HandlerFunc(referralsHandler.MarkJoined)))
	mux.Handle("POST /api/v1/referrals/{id}/reward", jwt(http.HandlerFunc(referralsHandler.Reward)))
	mux.Handle("POST /api/v1/referrals/{id}/expire", jwt(http.HandlerFunc(referralsHandler.Expire)))
	mux.Handle("GET /api/v1/members/{member_id}/referrals", jwt(http.HandlerFunc(referralsHandler.MemberReferrals)))

	// ── Trainers ────────────────────────────────────────────────────────────
	mux.Handle("POST /api/v1/trainers", jwt(http.HandlerFunc(trainersHandler.Create)))
	mux.Handle("GET /api/v1/trainers", jwt(http.HandlerFunc(trainersHandler.List)))
	mux.Handle("PUT /api/v1/trainers/{id}", jwt(http.HandlerFunc(trainersHandler.Update)))

	// ── PT packages & appointments ──────────────────────────────────────────
	mux.Handle("POST /api/v1/pt-packages", jwt(http.HandlerFunc(ptHandler.CreatePackage)))
	mux.Handle("GET /api/v1/pt-packages", jwt(http.HandlerFunc(ptHandler.ListPackages)))
	mux.Handle("PATCH /api/v1/pt-packages/{id}/status", jwt(http.HandlerFunc(ptHandler.UpdatePackageStatus)))
	mux.Handle("GET /api/v1/members/{member_id}/pt-packages", jwt(http.HandlerFunc(ptHandler.MemberPackages)))
	mux.Handle("POST /api/v1/pt-appointments", jwt(http.HandlerFunc(ptHandler.Book)))
	mux.Handle("GET /api/v1/pt-appointments", jwt(http.HandlerFunc(ptHandler.ListAppointments)))
	mux.Handle("POST /api/v1/pt-appointments/{id}/outcome", jwt(http.HandlerFunc(ptHandler.SetOutcome)))

	// ── Invoicing & discounts ──────────────────────────────────────────────
	mux.Handle("POST /api/v1/invoices", jwt(http.HandlerFunc(invoicingHandler.Create)))
	mux.Handle("GET /api/v1/invoices", jwt(http.HandlerFunc(invoicingHandler.List)))
	mux.Handle("GET /api/v1/invoices/{id}", jwt(http.HandlerFunc(invoicingHandler.Get)))
	mux.Handle("DELETE /api/v1/invoices/{id}", jwt(http.HandlerFunc(invoicingHandler.DeleteDraft)))
	mux.Handle("POST /api/v1/invoices/{id}/items", jwt(http.HandlerFunc(invoicingHandler.AddItem)))
	mux.Handle("POST /api/v1/invoices/{id}/plan-items", jwt(http.HandlerFunc(invoicingHandler.AddPlanItem)))
	mux.Handle("DELETE /api/v1/invoices/{id}/items/{item_id}", jwt(http.HandlerFunc(invoicingHandler.RemoveItem)))
	mux.Handle("POST /api/v1/invoices/{id}/discount", jwt(http.HandlerFunc(invoicingHandler.ApplyDiscount)))
	mux.Handle("POST /api/v1/invoices/{id}/issue", jwt(http.HandlerFunc(invoicingHandler.Issue)))
	mux.Handle("POST /api/v1/invoices/{id}/cancel", jwt(http.HandlerFunc(invoicingHandler.Cancel)))
	mux.Handle("GET /api/v1/members/{member_id}/invoices", jwt(http.HandlerFunc(invoicingHandler.MemberInvoices)))

	mux.Handle("POST /api/v1/discounts", jwt(http.HandlerFunc(invoicingHandler.CreateDiscount)))
	mux.Handle("GET /api/v1/discounts", jwt(http.HandlerFunc(invoicingHandler.ListDiscounts)))
	mux.Handle("PUT /api/v1/discounts/{id}", jwt(http.HandlerFunc(invoicingHandler.UpdateDiscount)))

	mux.Handle("GET /api/v1/billing-settings", jwt(http.HandlerFunc(invoicingHandler.GetSettings)))
	mux.Handle("PUT /api/v1/billing-settings", jwt(http.HandlerFunc(invoicingHandler.UpdateSettings)))

	// ── Retail: products, stock, sales ─────────────────────────────────────
	mux.Handle("POST /api/v1/products", jwt(http.HandlerFunc(posHandler.CreateProduct)))
	mux.Handle("GET /api/v1/products", jwt(http.HandlerFunc(posHandler.ListProducts)))
	mux.Handle("PUT /api/v1/products/{id}", jwt(http.HandlerFunc(posHandler.UpdateProduct)))
	mux.Handle("DELETE /api/v1/products/{id}", jwt(http.HandlerFunc(posHandler.DeleteProduct)))
	mux.Handle("POST /api/v1/products/{id}/stock", jwt(http.HandlerFunc(posHandler.AdjustStock)))
	mux.Handle("GET /api/v1/products/{id}/stock-history", jwt(http.HandlerFunc(posHandler.StockHistory)))
	mux.Handle("POST /api/v1/sales", jwt(http.HandlerFunc(posHandler.RecordSale)))
	mux.Handle("GET /api/v1/sales", jwt(http.HandlerFunc(posHandler.ListSales)))
	mux.Handle("GET /api/v1/sales/{id}", jwt(http.HandlerFunc(posHandler.GetSale)))
	mux.Handle("POST /api/v1/sales/{id}/refund", jwt(http.HandlerFunc(posHandler.Refund)))
	mux.Handle("GET /api/v1/retail/summary", jwt(http.HandlerFunc(posHandler.Summary)))

	// ── Member wallet ──────────────────────────────────────────────────────
	mux.Handle("GET /api/v1/members/{member_id}/wallet", jwt(http.HandlerFunc(walletHandler.Get)))
	mux.Handle("POST /api/v1/members/{member_id}/wallet/topup", jwt(http.HandlerFunc(walletHandler.TopUp)))
	mux.Handle("POST /api/v1/members/{member_id}/wallet/spend", jwt(http.HandlerFunc(walletHandler.Spend)))
	mux.Handle("POST /api/v1/members/{member_id}/wallet/adjust", jwt(http.HandlerFunc(walletHandler.Adjust)))

	// ── Branches & organizations ───────────────────────────────────────────
	mux.Handle("GET /api/v1/branches", jwt(http.HandlerFunc(branchesHandler.MyBranches)))
	mux.Handle("POST /api/v1/branches", jwt(http.HandlerFunc(branchesHandler.CreateBranch)))
	mux.Handle("POST /api/v1/branches/switch", jwt(http.HandlerFunc(branchesHandler.Switch)))
	mux.Handle("POST /api/v1/branches/access", jwt(http.HandlerFunc(branchesHandler.GrantAccess)))
	mux.Handle("DELETE /api/v1/branches/{gym_id}/access/{user_id}", jwt(http.HandlerFunc(branchesHandler.RevokeAccess)))
	mux.Handle("GET /api/v1/org/summary", jwt(http.HandlerFunc(branchesHandler.ChainSummary)))
	mux.Handle("GET /api/v1/org/report", jwt(http.HandlerFunc(branchesHandler.PeriodReport)))
	mux.Handle("PUT /api/v1/branches/{gym_id}/targets", jwt(http.HandlerFunc(branchesHandler.SetTargets)))
	mux.Handle("POST /api/v1/branches/transfer-member", jwt(http.HandlerFunc(branchesHandler.TransferMember)))
	mux.Handle("POST /api/v1/branches/transfer-staff", jwt(http.HandlerFunc(branchesHandler.TransferStaff)))
	mux.Handle("POST /api/v1/branches/transfer-trainer", jwt(http.HandlerFunc(branchesHandler.TransferTrainer)))

	// ── Data import ────────────────────────────────────────────────────────
	mux.Handle("POST /api/v1/imports", jwt(http.HandlerFunc(importerHandler.Validate)))
	mux.Handle("GET /api/v1/imports", jwt(http.HandlerFunc(importerHandler.List)))
	mux.Handle("GET /api/v1/imports/template", jwt(http.HandlerFunc(importerHandler.Template)))
	mux.Handle("GET /api/v1/imports/{id}", jwt(http.HandlerFunc(importerHandler.Get)))
	mux.Handle("POST /api/v1/imports/{id}/commit", jwt(http.HandlerFunc(importerHandler.Commit)))
	mux.Handle("DELETE /api/v1/imports/{id}", jwt(http.HandlerFunc(importerHandler.Discard)))

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
