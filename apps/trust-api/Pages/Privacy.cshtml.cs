using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.AspNetCore.Mvc;

namespace TrustApi.Pages;

public class PrivacyModel : PageModel
{
    public IActionResult OnGet() => RedirectPermanent("https://jointrust.app/privacy");
}
