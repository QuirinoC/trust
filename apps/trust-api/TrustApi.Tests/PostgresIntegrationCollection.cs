namespace TrustApi.Tests;

/// <summary>
/// These tests share the same Postgres database and may use different test clocks.
/// Serialize them so one test's global expiry sweep cannot mutate another test's rows.
/// </summary>
[CollectionDefinition("Postgres integration", DisableParallelization = true)]
public sealed class PostgresIntegrationCollection
{
}
