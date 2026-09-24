using System.Reflection;

namespace TrustApi.Infrastructure.StoreKit;

public static class AppleRootCertificates
{
    public static string[] LoadEmbedded()
    {
        var assembly = typeof(AppleRootCertificates).Assembly;
        var name = assembly.GetManifestResourceNames()
            .SingleOrDefault(item => item.EndsWith("AppleRootCA-G3.cer", StringComparison.Ordinal))
            ?? throw new InvalidOperationException("Apple Root CA G3 is not embedded.");
        using var stream = assembly.GetManifestResourceStream(name)
            ?? throw new InvalidOperationException("Apple Root CA G3 stream is missing.");
        using var memory = new MemoryStream();
        stream.CopyTo(memory);
        return [Convert.ToBase64String(memory.ToArray())];
    }
}
