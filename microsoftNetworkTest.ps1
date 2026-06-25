# Define key Intune endpoints
$intuneEndpoints = @(
    "https://endpoint.microsoft.com",
    "https://login.microsoftonline.com",
    "https://graph.microsoft.com",
    "https://deviceenrollment.microsoft.com",
    "https://manage.microsoft.com",
    "https://fef.amsub010.manage.microsoft.com",
    "https://fef.amsub020.manage.microsoft.com",
	"https://ecs.office.com",
	"https://manage.microsoft.com",
	"https://EnterpriseEnrollment.manage.microsoft.com"
)

Write-Host "Testing Intune connectivity..." -ForegroundColor Cyan

foreach ($url in $intuneEndpoints) {
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
        if ($response.StatusCode -eq 200) {
            Write-Host "✅ $url is reachable." -ForegroundColor Green
        } else {
            Write-Host "⚠️ $url responded with status code $($response.StatusCode)." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "❌ Failed to reach $url. Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

