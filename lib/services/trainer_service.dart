import '../models/trainer.dart';

/// TrainerService — stub.
/// Implement endpoints in the Trainer Management sprint.
class TrainerService {
  Future<List<Trainer>> getTrainers() async =>
      throw UnimplementedError('Trainer management not yet implemented');

  Future<Trainer> createTrainer(Map<String, dynamic> data) async =>
      throw UnimplementedError();

  Future<Trainer> updateTrainer(int id, Map<String, dynamic> data) async =>
      throw UnimplementedError();
}
