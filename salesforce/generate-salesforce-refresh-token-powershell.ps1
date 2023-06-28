$instanceUrl = "https://lightbeam.develop.my.salesforce.com"
$clientId = "3MVG9n_HvETGhr.......................................MC_twiaGbrj.pF._"
$clientSecret = "A89A8605ADF6............................................B3B2A"

$redirectUri = "https://login.salesforce.com"

function Obtain-AuthorizationCode {
    param (
        [string]$instanceUrl,
        [string]$clientKey,
        [string]$redirectUri
    )

    $authorizationUrl = "${instanceUrl}/services/oauth2/authorize?response_type=code&client_id=${clientKey}&redirect_uri=${redirectUri}"
    Write-Host "Please log in to Salesforce and visit the following URL to obtain the authorization code:`n"
    Write-Host $authorizationUrl
}

function Obtain-AccessToken {
    param (
        [string]$instanceUrl,
        [string]$clientKey,
        [string]$clientSecret,
        [string]$redirectUri,
        [string]$authorizationCode
    )

    $tokenUrl = "${instanceUrl}/services/oauth2/token"

    $params = @{
        code          = [System.Uri]::UnescapeDataString($authorizationCode)
        grant_type    = "authorization_code"
        client_id     = $clientKey
        client_secret = $clientSecret
        redirect_uri  = $redirectUri
    }

    try {
        $response = Invoke-RestMethod -Uri $tokenUrl -Method POST -Body $params -ContentType "application/x-www-form-urlencoded"
        Write-Output $response
    } catch {
        $errorResponse = $_.Exception.Response
        $responseContent = ""

        if ($errorResponse -ne $null) {
            $reader = [System.IO.StreamReader]::new($errorResponse.GetResponseStream())
            $responseContent = $reader.ReadToEnd()
        }

        Write-Error "Failed to obtain refresh token. Error: $_"
        Write-Error "Response content: $responseContent"
        Read-Host "Press Enter to exit"
        exit 1
    }
}

function Main {
    Obtain-AuthorizationCode -instanceUrl $instanceUrl -clientKey $clientId -redirectUri $redirectUri
    $authorizationCode = Read-Host "`nEnter the authorization code"

    Obtain-AccessToken -instanceUrl $instanceUrl -clientKey $clientId -clientSecret $clientSecret -redirectUri $redirectUri -authorizationCode $authorizationCode

    # Prompt for user input before exiting
    Read-Host "Press Enter to exit"
}

Main