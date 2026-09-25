using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.AspNetCore.Mvc;

namespace TrustApi.Pages;

public class SupportModel : PageModel
{
    public IActionResult OnGet() => RedirectPermanent("https://jointrust.app/support");
}
