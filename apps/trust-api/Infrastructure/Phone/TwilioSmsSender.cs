using System.Net.Http.Headers;
using System.Text;
using Microsoft.Extensions.Options;
using TrustApi.Configuration;
using TrustApi.Domain;

namespace TrustApi.Infrastructure.Phone;

public interface ISmsOtpSender
{
    bool IsConfigured { get; }
    Task SendAsync(string e164, string code, CancellationToken cancellationToken);
    Task SendTextAsync(string e164, string body, CancellationToken cancellationToken);
}

public sealed class TwilioSmsSender(IHttpClientFactory http, IOptions<TwilioOptions> options) : ISmsOtpSender
{
    public bool IsConfigured => options.Value.IsConfigured;

    public Task SendAsync(string e164, string code, CancellationToken cancellationToken) =>
        SendTextAsync(
            e164,
            $"Trust code: {code}. Expires in 10 minutes. Reply STOP to opt out.",
            cancellationToken);

    public async Task SendTextAsync(string e164, string body, CancellationToken cancellationToken)
    {
        var twilio = options.Value;
        if (!twilio.IsConfigured)
        {
            throw TrustException.OtpNotConfigured();
        }

        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"https://api.twilio.com/2010-04-01/Accounts/{Uri.EscapeDataString(twilio.AccountSid)}/Messages.json");
        var token = Convert.ToBase64String(Encoding.ASCII.GetBytes($"{twilio.AccountSid}:{twilio.AuthToken}"));
        request.Headers.Authorization = new AuthenticationHeaderValue("Basic", token);
        var form = new Dictionary<string, string>
        {
            ["To"] = e164,
            ["Body"] = body
        };
        if (!string.IsNullOrWhiteSpace(twilio.MessagingServiceSid))
        {
            form["MessagingServiceSid"] = twilio.MessagingServiceSid.Trim();
        }
        else
        {
            form["From"] = twilio.FromNumber.Trim();
        }

        request.Content = new FormUrlEncodedContent(form);
        using var client = http.CreateClient("twilio");
        using var response = await client.SendAsync(request, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw TrustException.OtpSendFailed();
        }
    }
}

public static class PhoneE164
{
    public static bool TryNormalize(string? raw, out string e164)
    {
        e164 = "";
        if (string.IsNullOrWhiteSpace(raw))
        {
            return false;
        }

        var trimmed = raw.Trim();
        var digits = new string(trimmed.Where(char.IsDigit).ToArray());
        if (trimmed.Any(char.IsLetter))
        {
            return false;
        }

        if (trimmed.StartsWith('+'))
        {
            if (digits.Length is < 8 or > 15)
            {
                return false;
            }

            e164 = "+" + digits;
            return IsTextable(e164);
        }

        if (digits.Length == 10)
        {
            e164 = "+1" + digits;
            return IsTextable(e164);
        }

        if (digits.Length == 11 && digits[0] == '1')
        {
            e164 = "+" + digits;
            return IsTextable(e164);
        }

        return false;
    }

    /// US numbers are the normal path. Satellite, premium, and other non-E.164 junk are not texted.
    private static bool IsTextable(string e164)
    {
        if (e164.Length < 2 || e164[0] != '+')
        {
            return false;
        }

        var digits = e164[1..];
        if (digits.Length is < 8 or > 15 || digits[0] == '0')
        {
            return false;
        }

        if (digits.StartsWith("870", StringComparison.Ordinal)
            || digits.StartsWith("878", StringComparison.Ordinal)
            || digits.StartsWith("881", StringComparison.Ordinal)
            || digits.StartsWith("882", StringComparison.Ordinal)
            || digits.StartsWith("883", StringComparison.Ordinal)
            || digits.StartsWith("888", StringComparison.Ordinal)
            || digits.StartsWith("979", StringComparison.Ordinal))
        {
            return false;
        }

        if (digits[0] != '1')
        {
            return true;
        }

        if (digits.Length != 11)
        {
            return false;
        }

        var npa = digits.Substring(1, 3);
        var nxx = digits.Substring(4, 3);
        if (npa[0] is < '2' or > '9' || nxx[0] is < '2' or > '9')
        {
            return false;
        }

        return npa is not ("900" or "976") && nxx is not "976";
    }

    public static string Mask(string e164)
    {
        if (string.IsNullOrEmpty(e164) || e164.Length < 5)
        {
            return "+***";
        }

        return "+***" + e164[^4..];
    }
}
