namespace TrustApi.Infrastructure.Notifications;

public static class NotificationLanguage
{
    private static readonly HashSet<string> Supported = new(StringComparer.OrdinalIgnoreCase)
    {
        "en", "de", "fr", "ja", "pt-BR", "zh-Hans"
    };

    public static string Normalize(string? language)
    {
        if (string.IsNullOrWhiteSpace(language)) return "en";
        var value = language.Trim().Replace('_', '-');
        if (value.Equals("pt", StringComparison.OrdinalIgnoreCase)) return "pt-BR";
        if (value.Equals("zh", StringComparison.OrdinalIgnoreCase)) return "zh-Hans";
        if (Supported.TryGetValue(value, out var supported)) return supported;
        var prefix = value.Split('-', 2)[0];
        return Supported.FirstOrDefault(candidate => candidate.Equals(prefix, StringComparison.OrdinalIgnoreCase)) ?? "en";
    }

    public static (string Title, string Body) Localize(string language, string kind, string actor)
    {
        var locale = Normalize(language);
        return (kind, locale) switch
        {
            ("look", "de") => ($"{actor} hat deinen Standort angesehen", "Eine einzelne Momentaufnahme des zuletzt für Trust verfügbaren Standorts."),
            ("look", "fr") => ($"{actor} a consulté ta position", "Un instantané de la dernière position disponible dans Trust."),
            ("look", "ja") => ($"{actor}さんが位置情報を確認しました", "Trustで利用できる最新の位置情報を1回確認しました。"),
            ("look", "pt-BR") => ($"{actor} consultou sua localização", "Uma captura da localização mais recente disponível no Trust."),
            ("look", "zh-Hans") => ($"{actor}查看了你的位置", "查看了一次 Trust 中最新可用的位置。"),
            ("look", _) => ($"{actor} looked at your location", "One snapshot of the latest location available to Trust."),
            ("home_arrival", "de") => ($"{actor} ist zu Hause", $"{actor} ist zu Hause."),
            ("home_arrival", "fr") => ($"{actor} est à la maison", $"{actor} est à la maison."),
            ("home_arrival", "ja") => ($"{actor}さんが帰宅しました", $"{actor}さんが家にいます。"),
            ("home_arrival", "pt-BR") => ($"{actor} chegou em casa", $"{actor} está em casa."),
            ("home_arrival", "zh-Hans") => ($"{actor}已到家", $"{actor}已在家。"),
            ("home_arrival", _) => ($"{actor} is home", $"{actor} is home."),
            _ => (actor, string.Empty)
        };
    }
}
