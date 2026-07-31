import '../models/pt_package.dart';

/// PtService — stub.
/// Implement endpoints in the Personal Training sprint.
class PtService {
  Future<List<PtPackage>> getMemberPackages(int memberId) async =>
      throw UnimplementedError('Personal Training not yet implemented');

  Future<PtPackage> createPackage(Map<String, dynamic> data) async =>
      throw UnimplementedError();

  Future<void> recordSession(int packageId) async =>
      throw UnimplementedError();
}
