[CmdletBinding()]
param (
    # GitHub Repository Owner
    [Parameter()]
    [string]
    $Owner = "coreruleset",
    # GitHub Repository Name
    [Parameter()]
    [string]
    $Repo = "coreruleset",
    # GitHub Repository Path
    [Parameter()]
    [string]
    $Path = "rules",
    # GitHub Repository Branch. The branch indicates the rule set version that you want to pull the rules and severities from
    [Parameter()]
    [ValidateSet("v3.3/master","v3.2/master", "v3.1/master", "v4.0/main")]
    [string]
    $Branch = "v3.2/master",
    # Data Collection Rule Immutable ID - Look in the Azure Portal (click the view json for the DCR) for this value 
    [Parameter()]
    [string]
    $DCRImmutableId,
    # Data Collection Endpoint URI - Look in the Azure Portal overview tab for this value
    [Parameter()]
    [string]
    $DataCollectionEndpointURI,
    # Log Analytics Custom Table Name
    [Parameter()]
    [string]
    $tableName
)

# Import the Az module
Import-Module Az.Accounts

# Base URI to get the rules from the repository - we are going to target the RAW file content so we can parse it
$baseUri = "https://api.github.com/repos/$owner/$repo/contents/$($path)?ref=$branch"

# Invoke the REST method to get the list of "files" in the rules directory we are going to process each one
$response = Invoke-RestMethod -Uri $baseUri -ContentType 'application/vnd.github.raw+json'

# Patterns to match the severity and ID of each rule
$severityPattern = "severity:'\w+'"
$idPattern = "id:\d+"
# Array to store the rules and their severities
$completeRuleList = new-object System.Collections.ArrayList

# Loop through each "file" in the response. These will be https://raw.githubusercontent.com/... links to the rules files
foreach ($file in $response) {
    if ($file.type -eq "file") {

        Write-Host "Processing File/RulesList from:" $file.download_url
        $GithubRepoURL = $file.download_url
        $fileToCheck = (Invoke-WebRequest -Uri $GithubRepoURL).Content

        # find the ID and severity of each rule
        $ruleIds = $fileToCheck | Select-String -Pattern $idPattern -AllMatches
        $ruleSeverity = $fileToCheck | Select-String -Pattern $severityPattern -AllMatches

        foreach ($ruleId in $ruleIds.Matches) {
            $rule = $ruleId.Value -replace "id:|,", ""
            $ruleDetails = $ruleSeverity.Matches | Where-Object { $_.Index -gt $ruleId.Index } | Select-Object -First 1
            $severity = $ruleDetails.Value -replace "severity:'|'", ""
            # associate a score with each severity level, for Rules that have no severity we will assign a score of 0
            switch ($severity) {
                "CRITICAL" { $score = 5 }
                "WARNING" { $score = 3 }
                "NOTICE" { $score = 2 }
                "ERROR" { $score = 4 }
                "" { $score = 0 }
                default { $score = 0 }
            }
            $completeRuleList.Add(
                [PSCustomObject]@{
                    TimeGenerated = Get-Date
                    ruleId       = $rule
                    severity = $severity
                    score    = $score
                }) | Out-Null
        }
    }
}


# Convert the list of rules to JSON
$JSONUpload = $completeRuleList | ConvertTo-Json -Depth 10
# Get the bearer token to authenticate to the Data Collection Rule Endpoint
$bearerToken = (Get-AzAccessToken -ResourceUrl 'https://monitor.azure.com').Token

# Sending the data to Log Analytics via the DCR!
$headers = @{"Authorization" = "Bearer $bearerToken"; "Content-Type" = "application/json" }
$uri = "$DataCollectionEndpointURI/dataCollectionRules/$DcrImmutableId/streams/Custom-$($tableName)"+"?api-version=2023-01-01"
$uploadResponse = Invoke-RestMethod -Uri $uri -Method "Post" -Body $JSONUpload -Headers $headers
Write-Host $uploadResponse 
