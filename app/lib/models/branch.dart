/// Branch — a gym location. See docs/FR-06-multi-location.md in the backend repo.
///
/// A branch **is** a gym: `gym_id` remains the single tenancy key, and a chain
/// is an organization sitting above several of them. There is deliberately no
/// `branch_id` on members or payments — adding a second scoping key would mean
/// every query in the system had to honour it, and any query that missed it
/// would leak data between branches.
class Branch {
  final int id;
  final String name;

  /// Short label ("Model Town") as opposed to the gym's full name
  /// ("FitZone Model Town"). Reads better in a switcher.
  final String? branchName;
  final String? city;
  final String? state;
  final String status;
  final int? organizationId;

  /// The signed-in user's role in this branch. Roles are per-branch: a manager
  /// at one location may be ordinary staff at another.
  final String role;

  Branch({
    required this.id,
    required this.name,
    this.branchName,
    this.city,
    this.state,
    this.status = 'active',
    this.organizationId,
    this.role = 'staff',
  });

  String get displayName =>
      (branchName != null && branchName!.isNotEmpty) ? branchName! : name;

  bool get isOwner => role == 'owner';

  factory Branch.fromJson(Map<String, dynamic> j) => Branch(
    id: j['id'] ?? 0,
    name: j['name'] ?? '',
    branchName: j['branch_name'],
    city: j['city'],
    state: j['state'],
    status: j['status'] ?? 'active',
    organizationId: j['organization_id'],
    role: j['role'] ?? 'staff',
  );
}

/// One branch's headline numbers in the consolidated chain view.
///
/// Carries comparison measures, not just totals: raw size mostly reflects how
/// long a branch has existed, whereas revenue per member and attainment against
/// target say which branch is actually performing.
class BranchSummary {
  final int gymId;
  final String name;
  final String? branchName;
  final int activeMembers;
  final int totalMembers;
  final int expiringSoon;
  final int revenueInPaise;

  final int newMembersThisMonth;
  final int lapsedThisMonth;
  final int revenueTargetInPaise;
  final int memberTarget;
  final int revenuePerMemberInPaise;
  final double revenueAttainmentPct;
  final double memberAttainmentPct;

  BranchSummary({
    required this.gymId,
    required this.name,
    this.branchName,
    required this.activeMembers,
    required this.totalMembers,
    required this.expiringSoon,
    required this.revenueInPaise,
    this.newMembersThisMonth = 0,
    this.lapsedThisMonth = 0,
    this.revenueTargetInPaise = 0,
    this.memberTarget = 0,
    this.revenuePerMemberInPaise = 0,
    this.revenueAttainmentPct = 0,
    this.memberAttainmentPct = 0,
  });

  String get displayName =>
      (branchName != null && branchName!.isNotEmpty) ? branchName! : name;

  double get revenueInRupees => revenueInPaise / 100;
  bool get hasTarget => revenueTargetInPaise > 0;

  factory BranchSummary.fromJson(Map<String, dynamic> j) => BranchSummary(
    gymId: j['gym_id'] ?? 0,
    name: j['name'] ?? '',
    branchName: j['branch_name'],
    activeMembers: j['active_members'] ?? 0,
    totalMembers: j['total_members'] ?? 0,
    expiringSoon: j['expiring_soon'] ?? 0,
    revenueInPaise: j['revenue_this_month_in_paise'] ?? 0,
    newMembersThisMonth: j['new_members_this_month'] ?? 0,
    lapsedThisMonth: j['lapsed_this_month'] ?? 0,
    revenueTargetInPaise: j['monthly_revenue_target_in_paise'] ?? 0,
    memberTarget: j['monthly_member_target'] ?? 0,
    revenuePerMemberInPaise: j['revenue_per_member_in_paise'] ?? 0,
    revenueAttainmentPct:
        (j['revenue_attainment_pct'] as num?)?.toDouble() ?? 0,
    memberAttainmentPct: (j['member_attainment_pct'] as num?)?.toDouble() ?? 0,
  );
}
