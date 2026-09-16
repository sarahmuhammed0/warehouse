import '../../../core/network/api_client.dart';
import 'health_models.dart';

/// Repository/service architecture foundation (architecture §4/§10): every
/// feature owns a repository that is the ONLY thing calling [ApiClient] for
/// that feature's data. A screen/provider never calls the network layer
/// directly — it calls a repository method, which returns a typed model or
/// throws a [Failure] (see core/error/failure.dart).
class HealthRepository {
  HealthRepository(this._client);

  final ApiClient _client;

  Future<ApiHealth> getApiHealth() async {
    final json = await _client.getJson('/health');
    return ApiHealth.fromJson(json);
  }

  Future<DatabaseHealth> getDatabaseHealth() async {
    final json = await _client.getJson('/health/db');
    return DatabaseHealth.fromJson(json);
  }
}
