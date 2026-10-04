namespace TrustApi.Domain;

/// Deadlines are server time; corrections bypass only account pacing, never a cap or destination pacing.
public sealed record PhoneRetryMetadata(DateTimeOffset ServerTime, DateTimeOffset RetryAt,
    int RetryAfterSeconds, DateTimeOffset ResendRetryAt, DateTimeOffset CorrectionRetryAt,
    int ImmediateNumberAttemptsRemaining, string? NormalizedPhone, DateTimeOffset AccountRetryAt,
    DateTimeOffset? AccountWindowStartedAt, int AccountSendCount, int ResendPacingSeconds);

public sealed record PhoneSmsReservation(bool Accepted, PhoneRetryMetadata Retry);

public static class PhoneSmsPolicy
{
    public static TimeSpan Window(string key) => TimeSpan.FromHours(key.Contains("-day", StringComparison.Ordinal) ? 24 : 1);
    public static int Backoff(int count) => count <= 1 ? 45 : Math.Min(45 << Math.Min(count - 1, 4), 180);
    public static SmsSendBudget Normalize(SmsSendBudget? row, string key, DateTimeOffset now) =>
        row is null || now - row.WindowStartedAt >= Window(key)
            ? new(key, now, 0, row?.LastSentAt, key.StartsWith("account:", StringComparison.Ordinal) ? [] : null)
            : row;

    public static bool IsNewCorrection(SmsSendBudget account, string? phone) =>
        phone is not null && account.PhoneAttempts is { Length: < 3 } attempts && !attempts.Contains(phone, StringComparer.Ordinal);

    public static DateTimeOffset Deadline(IEnumerable<SmsSendBudget> rows, DateTimeOffset now, bool correction, bool includePhone = true)
    {
        var deadline = now;
        foreach (var row in rows)
        {
            var isPhone = row.ScopeKey.StartsWith("phone:", StringComparison.Ordinal);
            if (isPhone && !includePhone) continue;
            var limit = row.ScopeKey == SmsSendBudget.GlobalDayKey() ? 40 : 8;
            if (row.SendCount >= limit) deadline = Max(deadline, row.WindowStartedAt + Window(row.ScopeKey));
            if (row.LastSentAt is { } sent && (isPhone || (!correction && row.ScopeKey.StartsWith("account:", StringComparison.Ordinal))))
            {
                var wait = sent.AddSeconds(Backoff(row.SendCount));
                // At the hourly rollover account grace resets. Destinations still owe
                // the 45-second minimum after their most recent send.
                var afterReset = isPhone ? Max(row.WindowStartedAt + Window(row.ScopeKey), sent.AddSeconds(45))
                    : row.WindowStartedAt + Window(row.ScopeKey);
                deadline = Max(deadline, wait < afterReset ? wait : afterReset);
            }
        }
        return deadline;
    }

    public static PhoneRetryMetadata Metadata(IReadOnlyList<SmsSendBudget> rows, string? phone, DateTimeOffset now, DateTimeOffset retryAt)
    {
        var account = rows.FirstOrDefault(row => row.ScopeKey.StartsWith("account:", StringComparison.Ordinal));
        var remaining = account?.PhoneAttempts is { } attempts ? Math.Max(0, 3 - attempts.Length) : 0;
        return new(now, retryAt, Math.Max(0, (int)Math.Ceiling((retryAt - now).TotalSeconds)),
            Deadline(rows, now, false), Deadline(rows, now, remaining > 0, includePhone: false), remaining, phone,
            Deadline(rows, now, false, includePhone: false), account?.WindowStartedAt, account?.SendCount ?? 0,
            Math.Max(Backoff(account?.SendCount ?? 0), Backoff(rows.FirstOrDefault(row => row.ScopeKey.StartsWith("phone:", StringComparison.Ordinal))?.SendCount ?? 0)));
    }

    public static SmsSendBudget Increment(SmsSendBudget row, string? phone, DateTimeOffset now) => row with
    {
        SendCount = row.SendCount + 1, LastSentAt = now,
        PhoneAttempts = row.ScopeKey.StartsWith("account:", StringComparison.Ordinal) && row.PhoneAttempts is { } attempts && phone is not null
            ? attempts.Append(phone).Distinct(StringComparer.Ordinal).ToArray() : row.PhoneAttempts
    };
    private static DateTimeOffset Max(DateTimeOffset a, DateTimeOffset b) => a > b ? a : b;
}
