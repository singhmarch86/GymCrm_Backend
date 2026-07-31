import '../models/branch.dart';

/// BranchService — stub.
/// Implement endpoints in the Branch Management sprint.
/// Note: requires schema changes (branches table, branch_id on members).
class BranchService {
  Future<List<Branch>> getBranches() async =>
      throw UnimplementedError('Branch Management not yet implemented');

  Future<Branch> createBranch(Map<String, dynamic> data) async =>
      throw UnimplementedError();

  Future<void> switchBranch(int branchId) async =>
      throw UnimplementedError();
}
