import '../models/campaign.dart';

/// MarketingService — stub.
/// Implement endpoints in the Marketing Automation sprint.
class MarketingService {
  Future<List<Campaign>> getCampaigns() async =>
      throw UnimplementedError('Marketing Automation not yet implemented');

  Future<Campaign> createCampaign(Map<String, dynamic> data) async =>
      throw UnimplementedError();

  Future<void> sendCampaign(int id) async =>
      throw UnimplementedError();
}
