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
	"gymcrm/internal/activation"
	"gymcrm/internal/attendance"
	"gymcrm/internal/auth"
	"gymcrm/internal/branches"
	"gymcrm/internal/classes"
	"gymcrm/internal/counter"
	"gymcrm/internal/dashboard"
	"gymcrm/internal/database"
	"gymcrm/internal/devseed"
	"gymcrm/internal/entitlements"
	"gymcrm/internal/gyms"
	"gymcrm/internal/importer"
	"gymcrm/internal/invoicing"
	"gymcrm/internal/leads"
	"gymcrm/internal/lifecycle"
	"gymcrm/internal/members"
	"gymcrm/internal/middleware"
	"gymcrm/internal/payments"
	"gymcrm/internal/payouts"
	"gymcrm/internal/plans"
	"gymcrm/internal/pos"
	"gymcrm/internal/pt"
	"gymcrm/internal/ptfeedback"
	"gymcrm/internal/ptreport"
	"gymcrm/internal/queues"
	"gymcrm/internal/recognition"
	"gymcrm/internal/referrals"
	"gymcrm/internal/renewals"
	"gymcrm/internal/reports"
	"gymcrm/internal/retention"
	"gymcrm/internal/rhythm"
	"gymcrm/internal/staffwork"
	"gymcrm/internal/stockreport"
	"gymcrm/internal/stocktransfer"
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
	authHandler := auth.NewHandler(authSvc, cfg)

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

	payoutsRepo := payouts.NewRepository(db)
	payoutsSvc := payouts.NewService(payoutsRepo)
	payoutsHandler := payouts.NewHandler(payoutsSvc)

	queuesRepo := queues.NewRepository(db)
	queuesSvc := queues.NewService(queuesRepo, invoicingSvc)
	queuesHandler := queues.NewHandler(queuesSvc)

	walletRepo := wallet.NewRepository(db)
	walletSvc := wallet.NewService(walletRepo)
	walletHandler := wallet.NewHandler(walletSvc)

	branchesRepo := branches.NewRepository(db)
	branchesSvc := branches.NewService(branchesRepo, cfg.JWT.Secret)
	branchesHandler := branches.NewHandler(branchesSvc)

	gymsRepo := gyms.NewRepository(db)
	gymsSvc := gyms.NewService(gymsRepo)
	gymsHandler := gyms.NewHandler(gymsRepo, gymsSvc, cfg.Server.PublicBaseURL)

	usersRepo := users.NewRepository(db)
	usersSvc := users.NewService(usersRepo)
	usersHandler := users.NewHandler(usersSvc)

	retentionRepo := retention.NewRepository(db)
	retentionSvc := retention.NewService(retentionRepo)
	retentionHandler := retention.NewHandler(retentionSvc)

	stockReportRepo := stockreport.NewRepository(db)
	stockReportSvc := stockreport.NewService(stockReportRepo)
	stockReportHandler := stockreport.NewHandler(stockReportSvc)

	stockTransferRepo := stocktransfer.NewRepository(db)
	stockTransferSvc := stocktransfer.NewService(stockTransferRepo, db)
	stockTransferHandler := stocktransfer.NewHandler(stockTransferSvc)

	ptFeedbackRepo := ptfeedback.NewRepository(db)
	ptFeedbackSvc := ptfeedback.NewService(ptFeedbackRepo, db)
	ptFeedbackHandler := ptfeedback.NewHandler(ptFeedbackSvc)

	ptReportRepo := ptreport.NewRepository(db)
	ptReportSvc := ptreport.NewService(ptReportRepo, ptFeedbackSvc)
	ptReportHandler := ptreport.NewHandler(ptReportSvc)

	recognitionRepo := recognition.NewRepository(db)
	recognitionSvc := recognition.NewService(recognitionRepo, db)
	recognitionHandler := recognition.NewHandler(recognitionSvc)

	staffWorkRepo := staffwork.NewRepository(db)
	staffWorkSvc := staffwork.NewService(staffWorkRepo)
	staffWorkHandler := staffwork.NewHandler(staffWorkSvc)

	rhythmRepo := rhythm.NewRepository(db)
	rhythmSvc := rhythm.NewService(rhythmRepo)
	rhythmHandler := rhythm.NewHandler(rhythmSvc)

	activationRepo := activation.NewRepository(db)
	activationSvc := activation.NewService(activationRepo)
	activationHandler := activation.NewHandler(activationSvc)

	counterRepo := counter.NewRepository(db)
	counterSvc := counter.NewService(counterRepo)
	counterHandler := counter.NewHandler(counterSvc)

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

	// gated wraps a route with a pricing-tier check — see
	// internal/entitlements. Chains after jwt for the same reason owner
	// does: the tenant context (which gym is calling) must already exist
	// before a feature gate can look up that gym's plan.
	gated := func(feature entitlements.Feature, h http.HandlerFunc) http.Handler {
		return jwt(entitlements.RequireFeature(gymsRepo, feature)(h))
	}

	// ── Auth — public ──────────────────────────────────────────────────────
	mux.HandleFunc("POST /api/v1/auth/register", authHandler.Register)
	mux.HandleFunc("POST /api/v1/auth/login", authHandler.Login)
	mux.HandleFunc("POST /api/v1/auth/refresh", authHandler.Refresh)

	// ── Auth — protected ───────────────────────────────────────────────────
	mux.Handle("GET /api/v1/auth/me", jwt(http.HandlerFunc(authHandler.Me)))
	mux.Handle("POST /api/v1/auth/logout", jwt(http.HandlerFunc(authHandler.Logout)))

	// ── Gym public advertisement page — public, no jwt (see gyms.Repository's
	// own comment: this is the one route on this server meant for an
	// anonymous visitor or a search-engine crawler) ─────────────────────────
	mux.HandleFunc("GET /api/v1/public/gyms/{slug}", gymsHandler.GetPublicProfile)

	// ── Gym public advertisement page — settings screen (protected) ────────
	mux.Handle("GET /api/v1/gyms/public-profile", jwt(http.HandlerFunc(gymsHandler.GetPublicProfileSettings)))
	mux.Handle("PATCH /api/v1/gyms/public-profile", jwt(http.HandlerFunc(gymsHandler.UpdatePublicProfile)))

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
	mux.Handle("GET /api/v1/leads/followups", gated(entitlements.FeatureLeadsFollowUps, leadsHandler.FollowUps))
	mux.Handle("GET /api/v1/leads/analytics", gated(entitlements.FeatureLeadAnalytics, leadsHandler.Analytics))
	mux.Handle("GET /api/v1/leads/assignees", jwt(http.HandlerFunc(leadsHandler.Assignees)))

	// The lead workflow (FR-18). Registered before /leads/{id} so the literal
	// paths win — Go's mux prefers the more specific pattern, but keeping them
	// adjacent makes that visible rather than incidental.
	mux.Handle("GET /api/v1/leads/workflow", gated(entitlements.FeatureLeadsWorkflow, leadsHandler.Workflow))
	mux.Handle("GET /api/v1/leads/next-steps", gated(entitlements.FeatureLeadsWorkflow, leadsHandler.NextStepOptions))
	mux.Handle("PATCH /api/v1/leads/{id}/next-step", gated(entitlements.FeatureLeadsWorkflow, leadsHandler.SetNextStep))
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
	// Medium plan and up (pricing sheet: "At Risk / retention system — all
	// 9 retention signals").
	mux.Handle("POST /api/v1/retention/scan", gated(entitlements.FeatureRetentionSignals, retentionHandler.Scan))
	mux.Handle("GET /api/v1/retention/alerts", gated(entitlements.FeatureRetentionSignals, retentionHandler.ListAlerts))
	mux.Handle("GET /api/v1/retention/summary", gated(entitlements.FeatureRetentionSignals, retentionHandler.Summary))
	mux.Handle("PATCH /api/v1/retention/alerts/{id}/resolve", gated(entitlements.FeatureRetentionSignals, retentionHandler.Resolve))
	mux.Handle("GET /api/v1/retention/staff-activity", gated(entitlements.FeatureRetentionSignals, retentionHandler.StaffActivity))

	// Staff work (FR-13). Read-only over ledgers that already record who acted.
	// Plain jwt, not owner-only: a staff member may see their own day, and the
	// service narrows the result from the token rather than trusting a query
	// parameter.
	// Medium plan and up (pricing sheet: "Staff Work").
	mux.Handle("GET /api/v1/staff-work", gated(entitlements.FeatureStaffWork, staffWorkHandler.Day))
	mux.Handle("GET /api/v1/staff-work/items", gated(entitlements.FeatureStaffWork, staffWorkHandler.Items))
	mux.Handle("GET /api/v1/staff-work/leads", gated(entitlements.FeatureStaffWork, staffWorkHandler.LeadWork))
	// Analytics (FR-22). Same range parameters as the day view. Not a
	// ranking: people come back ordered by name and compared only to their
	// own previous period.
	mux.Handle("GET /api/v1/staff-work/analytics",
		gated(entitlements.FeatureStaffWork, staffWorkHandler.Analytics))

	// Work queues (FR-19). What is still owed, as opposed to what happened.
	// Plain jwt: low stock is a fact about the shelf, not about a person, and
	// the receptionist who notices it is the one who should be able to see it.
	mux.Handle("GET /api/v1/queues/stock", jwt(http.HandlerFunc(queuesHandler.Stock)))
	// Stock analytics (FR-23). The queue above answers "what is nearly gone"
	// against a typed-in threshold; this answers how long the shelf lasts at
	// the rate things actually sell, which is the question that decides money.
	mux.Handle("GET /api/v1/stock/analytics",
		jwt(http.HandlerFunc(stockReportHandler.Report)))

	// Inventory across branches (FR-22). Plain jwt for the same reason as the
	// stock queue: the person who notices an empty shelf is standing at it,
	// and a transfer that needs an owner is a transfer that does not happen.
	// Who moved what is recorded on the transfer instead.
	mux.Handle("GET /api/v1/stock/chain",
		jwt(http.HandlerFunc(stockTransferHandler.Chain)))
	mux.Handle("POST /api/v1/stock/transfer",
		jwt(http.HandlerFunc(stockTransferHandler.Send)))
	mux.Handle("GET /api/v1/stock/transfers",
		jwt(http.HandlerFunc(stockTransferHandler.History)))

	// Collections (FR-19 §3). Not narrowed by user: unlike staff work this is
	// a worklist rather than a record of who did what, and a receptionist
	// working the desk needs the whole list for it to be useful.
	mux.Handle("GET /api/v1/queues/collections",
		jwt(http.HandlerFunc(queuesHandler.Collections)))
	// Records that a member owes money. POST /api/v1/payments only ever
	// creates a *paid* row, so before this there was no way to enter a due.
	mux.Handle("POST /api/v1/payments/due",
		jwt(http.HandlerFunc(queuesHandler.RaiseDue)))
	mux.Handle("POST /api/v1/payments/{id}/contact",
		jwt(http.HandlerFunc(queuesHandler.RecordContact)))
	mux.Handle("POST /api/v1/payments/{id}/promise",
		jwt(http.HandlerFunc(queuesHandler.RecordPromise)))
	// Settles an existing due. Distinct from POST /api/v1/payments, which
	// creates a new one — collecting through that would leave the original
	// pending and double-count the money.
	mux.Handle("POST /api/v1/payments/{id}/settle",
		jwt(http.HandlerFunc(queuesHandler.Settle)))
	// Write-off is owner-only, enforced in the service from the token rather
	// than here, so the rule travels with the operation.
	mux.Handle("POST /api/v1/payments/{id}/write-off",
		jwt(http.HandlerFunc(queuesHandler.WriteOff)))

	// Renewals due (FR-19 §4). Windowed at 30 days either side; anything
	// lapsed longer ago is counted in the response but not listed.
	mux.Handle("GET /api/v1/queues/renewals",
		jwt(http.HandlerFunc(queuesHandler.Renewals)))
	// Owner-only, enforced in the service from the token.
	mux.Handle("POST /api/v1/members/{id}/confirm-lapse",
		jwt(http.HandlerFunc(queuesHandler.ConfirmLapse)))

	// Expected payments (FR-19 §5). The only date-scoped queue endpoint: what
	// is owed is owed whatever range you ask for, but what is *coming* is a
	// question about a window. Takes the same date/from/to as staff work.
	mux.Handle("GET /api/v1/queues/expected",
		jwt(http.HandlerFunc(queuesHandler.Expected)))
	// Draft invoices from raised dues (FR-19 §6). Only dues, never expiring
	// memberships: an invoice for money nobody agreed to pay would put an
	// invented supply into the gym's tax records.
	mux.Handle("POST /api/v1/queues/expected/invoice",
		jwt(http.HandlerFunc(queuesHandler.InvoiceDues)))

	// Money leakage (FR-21). What the gym handed over and never billed —
	// which is why none of it appears in the collections queue.
	// Medium plan and up (pricing sheet: "Money Leaks").
	mux.Handle("GET /api/v1/queues/leakage",
		gated(entitlements.FeatureMoneyLeaks, queuesHandler.Leakage))

	// Trainer payouts (FR-21 §2). The other direction of the same problem:
	// money the gym owes, which nothing recorded until now. Premium plan
	// only (pricing sheet: "Advanced trainer payouts", "Salary +
	// commission + session-based payouts").
	mux.Handle("GET /api/v1/trainers/{trainer_id}/payout-preview",
		gated(entitlements.FeatureAdvancedPayouts, payoutsHandler.Preview))
	mux.Handle("GET /api/v1/payouts", gated(entitlements.FeatureAdvancedPayouts, payoutsHandler.List))
	mux.Handle("POST /api/v1/payouts", gated(entitlements.FeatureAdvancedPayouts, payoutsHandler.Create))
	mux.Handle("GET /api/v1/payouts/{id}", gated(entitlements.FeatureAdvancedPayouts, payoutsHandler.Get))
	mux.Handle("POST /api/v1/payouts/{id}/cancel",
		gated(entitlements.FeatureAdvancedPayouts, payoutsHandler.Cancel))
	// Owner-only, enforced in the service from the token: this is the one
	// operation in the system that moves cash out of the gym.
	mux.Handle("POST /api/v1/payouts/{id}/pay",
		gated(entitlements.FeatureAdvancedPayouts, payoutsHandler.MarkPaid))

	// Rhythm-break detection (FR-09). Raises a `rhythm_break` alert into the
	// same retention_alerts queue, so resolution goes through the retention
	// endpoint above — there is deliberately no second resolve route.
	mux.Handle("POST /api/v1/rhythm/scan", jwt(http.HandlerFunc(rhythmHandler.Scan)))
	mux.Handle("GET /api/v1/rhythm/breaks", jwt(http.HandlerFunc(rhythmHandler.ListBreaks)))
	mux.Handle("GET /api/v1/rhythm/members/{id}", jwt(http.HandlerFunc(rhythmHandler.GetProfile)))

	// First 90 days (FR-10). Like rhythm, these raise rows in the same
	// retention_alerts queue and are closed through the retention endpoint —
	// one member, one problem, one row, one call.
	mux.Handle("POST /api/v1/activation/scan", jwt(http.HandlerFunc(activationHandler.Scan)))
	mux.Handle("GET /api/v1/activation/alerts", jwt(http.HandlerFunc(activationHandler.ListAlerts)))
	mux.Handle("GET /api/v1/activation/funnel", jwt(http.HandlerFunc(activationHandler.Funnel)))

	// The counter prompt (FR-11). Not a new signal — a new place to show the
	// ones that already exist, at the moment the member is standing there.
	// Medium plan and up (pricing sheet: "Counter prompts") — note this
	// gates only the prompt itself, never /api/v1/attendance/checkin, so a
	// Normal-tier gym can still check members in.
	mux.Handle("POST /api/v1/counter/checkin/{member_id}", gated(entitlements.FeatureCounterPrompts, counterHandler.Show))
	mux.Handle("GET /api/v1/counter/prompt/{member_id}", gated(entitlements.FeatureCounterPrompts, counterHandler.Peek))
	mux.Handle("PATCH /api/v1/counter/prompts/{id}/acted", gated(entitlements.FeatureCounterPrompts, counterHandler.MarkActed))
	mux.Handle("GET /api/v1/counter/effectiveness", gated(entitlements.FeatureCounterPrompts, counterHandler.Effectiveness))

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
	// Medium plan and up (pricing sheet: "Classes & timetable").
	mux.Handle("POST /api/v1/class-types", gated(entitlements.FeatureClasses, classesHandler.CreateClassType))
	mux.Handle("GET /api/v1/class-types", gated(entitlements.FeatureClasses, classesHandler.ListClassTypes))
	mux.Handle("PUT /api/v1/class-types/{id}", gated(entitlements.FeatureClasses, classesHandler.UpdateClassType))

	mux.Handle("POST /api/v1/class-schedules", gated(entitlements.FeatureClasses, classesHandler.CreateSchedule))
	mux.Handle("GET /api/v1/class-schedules", gated(entitlements.FeatureClasses, classesHandler.ListSchedules))
	mux.Handle("POST /api/v1/class-schedules/generate", gated(entitlements.FeatureClasses, classesHandler.GenerateUpcomingSessions))

	mux.Handle("POST /api/v1/class-sessions", gated(entitlements.FeatureClasses, classesHandler.CreateAdHocSession))
	mux.Handle("GET /api/v1/class-sessions", gated(entitlements.FeatureClasses, classesHandler.ListSessions))
	mux.Handle("GET /api/v1/class-sessions/{id}", gated(entitlements.FeatureClasses, classesHandler.GetSession))
	mux.Handle("PUT /api/v1/class-sessions/{id}", gated(entitlements.FeatureClasses, classesHandler.UpdateSession))
	mux.Handle("POST /api/v1/class-sessions/{id}/cancel", gated(entitlements.FeatureClasses, classesHandler.CancelSession))
	mux.Handle("POST /api/v1/class-sessions/{id}/complete", gated(entitlements.FeatureClasses, classesHandler.CompleteSession))

	mux.Handle("POST /api/v1/class-sessions/{id}/bookings", gated(entitlements.FeatureClasses, classesHandler.Book))
	mux.Handle("GET /api/v1/class-sessions/{id}/bookings", gated(entitlements.FeatureClasses, classesHandler.SessionBookings))
	mux.Handle("POST /api/v1/bookings/{id}/cancel", gated(entitlements.FeatureClasses, classesHandler.CancelBooking))
	mux.Handle("POST /api/v1/bookings/{id}/attendance", gated(entitlements.FeatureClasses, classesHandler.MarkAttendance))
	mux.Handle("GET /api/v1/members/{member_id}/bookings", gated(entitlements.FeatureClasses, classesHandler.MemberBookings))

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
	// Medium plan and up (pricing sheet: "PT packages & appointments").
	mux.Handle("POST /api/v1/pt-packages", gated(entitlements.FeaturePTPackages, ptHandler.CreatePackage))
	mux.Handle("GET /api/v1/pt-packages", gated(entitlements.FeaturePTPackages, ptHandler.ListPackages))
	mux.Handle("PATCH /api/v1/pt-packages/{id}/status", gated(entitlements.FeaturePTPackages, ptHandler.UpdatePackageStatus))
	mux.Handle("GET /api/v1/members/{member_id}/pt-packages", gated(entitlements.FeaturePTPackages, ptHandler.MemberPackages))
	mux.Handle("POST /api/v1/pt-appointments", gated(entitlements.FeaturePTPackages, ptHandler.Book))
	mux.Handle("GET /api/v1/pt-appointments", gated(entitlements.FeaturePTPackages, ptHandler.ListAppointments))
	mux.Handle("POST /api/v1/pt-appointments/{id}/outcome", gated(entitlements.FeaturePTPackages, ptHandler.SetOutcome))

	// PT feedback. One log, author_role tells whose words they are — both
	// member and trainer notes are staff-transcribed, since trainers have no
	// login (FR-03). Medium plan and up (pricing sheet: "Trainer management
	// + feedback"); pt-report (Phase 2) reads the same feedback log, so it's
	// gated identically.
	mux.Handle("POST /api/v1/pt/feedback", gated(entitlements.FeatureTrainerFeedback, ptFeedbackHandler.Create))
	mux.Handle("GET /api/v1/members/{id}/feedback", gated(entitlements.FeatureTrainerFeedback, ptFeedbackHandler.ByMember))
	mux.Handle("GET /api/v1/trainers/{id}/feedback", gated(entitlements.FeatureTrainerFeedback, ptFeedbackHandler.ByTrainer))

	// PT reports (Phase 2). Read-only compositions over pt, ptfeedback and
	// rhythm — the member and trainer sides are answered independently.
	mux.Handle("GET /api/v1/members/{id}/pt-report", gated(entitlements.FeatureTrainerFeedback, ptReportHandler.Member))
	mux.Handle("GET /api/v1/trainers/{id}/pt-report", gated(entitlements.FeatureTrainerFeedback, ptReportHandler.Trainer))

	// Private member recognition (Phase 3). Always a human reason, never a
	// score or a rank — same discipline as FR-13 §1. Medium plan and up
	// (pricing sheet: "Recognition").
	mux.Handle("POST /api/v1/members/{id}/recognitions", gated(entitlements.FeatureRecognition, recognitionHandler.Create))
	mux.Handle("GET /api/v1/members/{id}/recognitions", gated(entitlements.FeatureRecognition, recognitionHandler.ByMember))

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
	// Shop / POS. Medium plan and up (pricing sheet: "Shop / POS", "Stock &
	// restock management", "Sales history / refunds").
	mux.Handle("POST /api/v1/products", gated(entitlements.FeatureShopPOS, posHandler.CreateProduct))
	mux.Handle("GET /api/v1/products", gated(entitlements.FeatureShopPOS, posHandler.ListProducts))
	mux.Handle("PUT /api/v1/products/{id}", gated(entitlements.FeatureShopPOS, posHandler.UpdateProduct))
	mux.Handle("DELETE /api/v1/products/{id}", gated(entitlements.FeatureShopPOS, posHandler.DeleteProduct))
	mux.Handle("POST /api/v1/products/{id}/stock", gated(entitlements.FeatureShopPOS, posHandler.AdjustStock))
	mux.Handle("GET /api/v1/products/{id}/stock-history", gated(entitlements.FeatureShopPOS, posHandler.StockHistory))
	mux.Handle("POST /api/v1/sales", gated(entitlements.FeatureShopPOS, posHandler.RecordSale))
	mux.Handle("GET /api/v1/sales", gated(entitlements.FeatureShopPOS, posHandler.ListSales))
	mux.Handle("GET /api/v1/sales/{id}", gated(entitlements.FeatureShopPOS, posHandler.GetSale))
	mux.Handle("POST /api/v1/sales/{id}/refund", gated(entitlements.FeatureShopPOS, posHandler.Refund))
	mux.Handle("GET /api/v1/retail/summary", gated(entitlements.FeatureShopPOS, posHandler.Summary))

	// ── Member wallet ──────────────────────────────────────────────────────
	// Medium plan and up (pricing sheet: "Digital Wallet").
	mux.Handle("GET /api/v1/members/{member_id}/wallet", gated(entitlements.FeatureDigitalWallet, walletHandler.Get))
	mux.Handle("POST /api/v1/members/{member_id}/wallet/topup", gated(entitlements.FeatureDigitalWallet, walletHandler.TopUp))
	mux.Handle("POST /api/v1/members/{member_id}/wallet/spend", gated(entitlements.FeatureDigitalWallet, walletHandler.Spend))
	mux.Handle("POST /api/v1/members/{member_id}/wallet/adjust", gated(entitlements.FeatureDigitalWallet, walletHandler.Adjust))

	// ── Branches & organizations ───────────────────────────────────────────
	// MyBranches and Switch stay ungated on every plan — a standalone gym
	// is one branch in one organization (branches.Organization's own
	// comment), so every tier needs to know which branch it's looking at.
	// Everything below is the actual multi-branch cluster the pricing
	// sheet calls Premium: adding a second location, cross-branch staff
	// access, chain-wide comparisons, targets, and transfers.
	mux.Handle("GET /api/v1/branches", jwt(http.HandlerFunc(branchesHandler.MyBranches)))
	mux.Handle("POST /api/v1/branches/switch", jwt(http.HandlerFunc(branchesHandler.Switch)))
	mux.Handle("POST /api/v1/branches", gated(entitlements.FeatureMultiBranch, branchesHandler.CreateBranch))
	mux.Handle("POST /api/v1/branches/access", gated(entitlements.FeatureMultiBranch, branchesHandler.GrantAccess))
	mux.Handle("DELETE /api/v1/branches/{gym_id}/access/{user_id}", gated(entitlements.FeatureMultiBranch, branchesHandler.RevokeAccess))
	mux.Handle("GET /api/v1/org/summary", gated(entitlements.FeatureMultiBranch, branchesHandler.ChainSummary))
	mux.Handle("GET /api/v1/org/report", gated(entitlements.FeatureMultiBranch, branchesHandler.PeriodReport))
	mux.Handle("PUT /api/v1/branches/{gym_id}/targets", gated(entitlements.FeatureMultiBranch, branchesHandler.SetTargets))
	mux.Handle("POST /api/v1/branches/transfer-member", gated(entitlements.FeatureMultiBranch, branchesHandler.TransferMember))
	mux.Handle("POST /api/v1/branches/transfer-staff", gated(entitlements.FeatureMultiBranch, branchesHandler.TransferStaff))
	mux.Handle("POST /api/v1/branches/transfer-trainer", gated(entitlements.FeatureMultiBranch, branchesHandler.TransferTrainer))

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
	mux.Handle("GET /api/v1/reports/payments", gated(entitlements.FeatureReportPayments, reportsHandler.Payments))
	mux.Handle("GET /api/v1/reports/renewals", gated(entitlements.FeatureReportRenewals, reportsHandler.Renewals))
	mux.Handle("GET /api/v1/reports/plans", gated(entitlements.FeatureReportPlans, reportsHandler.Plans))

	// ── Server ────────────────────────────────────────────────────────────
	// CORS wraps the whole mux so preflight OPTIONS requests are answered before
	// they reach the router (which registers only method-qualified routes and
	// would 405 them). No-op for native clients; required for any web build.
	//
	// RequestLog wraps CORS rather than the other way round: CORS answers
	// preflights itself and never calls through, so a logger mounted inside it
	// would be blind to a failing preflight — the single hardest failure to
	// diagnose from the browser side.
	srv := &http.Server{
		Addr:         ":" + cfg.Server.Port,
		Handler:      middleware.RequestLog()(middleware.CORS(cfg.CORSAllowedOrigins())(mux)),
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
