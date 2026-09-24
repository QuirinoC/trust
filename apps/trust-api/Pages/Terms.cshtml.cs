using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.AspNetCore.Mvc;

namespace TrustApi.Pages;

public class TermsModel : PageModel
{
    public IActionResult OnGet() => RedirectPermanent("https://jointrust.app/terms");
}
