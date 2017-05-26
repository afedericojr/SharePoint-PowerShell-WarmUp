##
# SHAREPOINT 2016 WARMUP  SCRIPT
# AFEDERICO 2017
# This script is an improvement upon http://www.justinkobel.com/post/2013/08/16/My-SharePoint-2013-(and-2010)-Warm-up-Script
# and warmups up applications, site collections within them, creates a log file of the successes and failures, and then emails the results.
# This script needs to run on both WFE and APP servers. The APP server role(s) will automatically use the -includecentraladministration switch.
##
Param(
    [switch]$report,
    [switch]$iisreset
)
Add-PsSnapin Microsoft.SharePoint.PowerShell -ErrorAction SilentlyContinue
Start-SPAssignment -global
# If iisreset switch is used, IIS will be reset.
# A scheduled IIS Reset is not recommended.
if($iisreset){
    Write-Host "Resetting IIS. Please wait."
    & {iisreset}
}
$timeout = 120000 # =120 seconds  
$dateToday = $([DateTime]::Now.ToString('yyyy_dd_MM'))
$logPath = "L:\Scripts\SP2016Warmup" # Since we could be in a UAC window, we need to hardcode our log path since our directory could be System32
$successfilename=("$logPath\SuccessfulRuns_$dateToday.txt")
$failsfilename=("$logPath\FailedRunInfo_$dateToday.txt")
$serverRole = Get-SPServer -Identity $env:COMPUTERNAME | Select-Object -ExpandProperty Role
$siteLimit = 100 # Increase the limit beyond 100 sites as needed, but be cautious of run time. -All returns all sites.
# Global Variables For Report
$global:appCount = 0
$global:siteCount = 0
$global:numAppSuccesses = 0
$global:numAppFailures = 0
$global:numSiteSuccesses = 0
$global:numSiteFailures = 0
# Send-Mail Variables
$smartHost = "email.domain.com"
$sendTo = "spadmin@domain.com" # Multiple values separated by comma
$sendFrom = "spadmin@domain.com"
$mailSubject = "SharePoint Warmup Results for $env:COMPUTERNAME"
# Start-MailMessage Variables
$mailBodyComposer = ""
$style = ""

Add-Type -ReferencedAssemblies "System.Net" -TypeDefinition @"  
using System.Net;  
public class WarmupWebClient:WebClient
{
    private int timeout = 60000;  
    public WarmupWebClient(int timeout)  
    {  
        this.timeout = timeout;  
    }
    
    protected override WebRequest GetWebRequest(System.Uri webUrl)  
    {
        WebRequest requestResponse = base.GetWebRequest(webUrl);  
        requestResponse.Timeout = this.timeout;  
        return requestResponse;  
    }  
} 
"@

# Determines if the server type is an Application Server, in which case it includes Central Administrator in the warmup for that server.
function Initialize-WarmUp {
    Write-Output "<h2>Begin Warmup of Web Applications on $([DateTime]::Now.ToString('MMMM dd, yyyy'))</h2>"
    if ($serverRole -eq "ApplicationWithSearch" -or $serverRole -eq "Application") {
        foreach ($WebApp in (Get-SPWebApplication -includecentraladministration)) 
        { 
            Start-WarmupUrl($webApp.Url)
        }
    }
    else {
        foreach ($WebApp in (Get-SPWebApplication)) 
        { 
            Start-WarmupUrl($webApp.Url)
        }
    }
# You can warmup any URL, such as shown below with search results. (e.g. Excel Services, Access Services, etc.)
# Start-WarmupUrl("https://intranet.contoso.com/_layouts/OSSSearchResults.aspx?k=warmup")
}

# Runs after Initialize-Warmup determines which server type.
# Uses current credentials to get each site within the current application.
# Logs output for each result.
function Start-WarmupUrl($url){
    try {  
        Write-Output "<b>Warming up $url</b></br>" 
        $wc = New-Object WarmupWebClient($timeout)  
        $wc.Credentials = [System.Net.CredentialCache]::DefaultCredentials  
        $ret = $wc.DownloadString($url)

        if( $ret.Length -gt 0 ) {
            $s = "Last run successful for url ""$($url)"": $([DateTime]::Now.ToString('yyyy.dd.MM HH:mm:ss'))"
            try {
                Write-Output "<ul>"
                foreach ($webSite in get-spsite -webapplication $WebApp.url -Limit $siteLimit){
                    $s += "`r`n --> Warmed up site: $($webSite.Url)"
                    Write-Output "<li>Warmed up site: $($webSite.Url)</li>"
                    $global:numSiteSuccesses++
                }
                Write-Output "</ul>"
            }
            catch [Exception]{
                $global:numSiteFailures++
            }
            if( Test-Path $successfilename -PathType Leaf ) {  
                $c = Get-Content $successfilename  
                $cl = $c -split '`n'     
                $s = ((@($s) + $cl) | Select-Object -First 200)  
            }
        $global:numAppSuccesses++
        Out-File -InputObject ($s -join "`r`n") -FilePath $successfilename  
       }  
 
    }
    catch [Exception]{  
 
        $s = "`r`nLast run failed for url ""$($url)"": $([DateTime]::Now.ToString('yyyy.dd.MM HH:mm:ss')) : $($_.Exception.Message)`r`n" 
 
        Write-Output "<font color=red></br>Last run failed for url ""$($url)"" on $([DateTime]::Now.ToString('yyyy.dd.MM HH:mm:ss')) with Error:</br><b>$($_.Exception.Message)</b></font></br></br>"
 
        if( Test-Path $failsfilename -PathType Leaf ) {  
            $c = Get-Content $failsfilename  
            $cl = $c -split '`n' 
            $s = ((@($s) + $cl) | Select-Object -First 200)
        }
        $global:numAppFailures++
        Out-File -InputObject ($s -join "`r`n") -FilePath $failsfilename  
    }
}

# Uses WMI to get current Memory usage.
function Get-MemoryUsage() {
    [cmdletbinding()]
    Param()
     
    $os = Get-Ciminstance Win32_OperatingSystem
    $pctFree = [math]::Round(($os.FreePhysicalMemory/$os.TotalVisibleMemorySize)*100,2)
     
    if ($pctFree -ge 45) {
        $Status = "OK"
    }
    elseif ($pctFree -ge 15 ) {
        $Status = "Warning"
    }
    else {
        $Status = "Critical"
    }
     
    $os | Select-Object @{Name = "Memory Status";Expression = {$Status}},
    @{Name = "% Free"; Expression = {$pctFree}},
    @{Name = "Free (GB)";Expression = {[math]::Round($_.FreePhysicalMemory/1mb,2)}},
    @{Name = "Total (GB)";Expression = {[int]($_.TotalVisibleMemorySize/1mb)}}
 
}

# Uses WMI to get current Disk usage
function Get-DiskUsage {
    Get-WmiObject win32_logicaldisk -Filter "MediaType='12'" |
    Select-Object @{n="Drive";e={$_.DeviceId}}, 
    @{n="% Free";e={"{0:N3}" -f ($_.FreeSpace/$_.Size).ToString("P")}},
    @{n="Size (GB)";e={[math]::Round($_.Size/1GB,2)}},
    @{n="Free Space (GB)";e={[math]::Round($_.FreeSpace/1GB,2)}}
}

# Begins composition and formating of the mail message
function Start-MailMessage(){
    $style = "<style>BODY{font-family: Arial; font-size: 10pt; margin: 10px 0 10px 0; }"
    $style = $style + "TABLE{border: 1px solid black; border-collapse: collapse; }"
    $style = $style + "TH{border: 1px solid black; background: #dddddd; padding: 5 15px 5 15px; }"
    $style = $style + "TD{border: 1px solid black; padding: 5 15px 5 15px; }"
    $style = $style + "</style>"

    $mailBodyComposer += Initialize-WarmUp
    $mailBodyComposer = [string]$mailBodyComposer + [string]::Format("<p>
    Total number of web applications: <b>{0}</b></br>
    Total number of site collections: <b>{1}</b></br>
    Total number of successful web application warmups: <b>{2}</b></br>
    Total number of failed web application warmups: <b>{3}</b></br>
    Total number of successful site collection warmups: <b>{4}</b></br>
    Total number of failed site collection warmups: <b>{5}</b></br></p>
    ",($global:numAppSuccesses + $global:numAppFailures),($global:numSiteSuccesses + $global:numSiteFailures),$global:numAppSuccesses,$global:numAppFailures,$global:numSiteSuccesses,$global:numSiteFailures)

    $mailBodyComposer += Get-MemoryUsage | ConvertTo-Html -Head $style
    $mailBodyComposer += Get-DiskUsage | ConvertTo-Html

    Send-Mail($mailBodyComposer)
}

# Sends the mail message that was composed by Start-MailMessage
function Send-Mail($mailBody)
{
    $mailAttachment = @()
    if ($global:numAppSuccesses -or $global:numSiteSuccesses){
        $mailAttachment += $successfilename
    }
    if ($global:numAppFailures -or $global:numSiteFailures){
        $mailAttachment += $failsfilename
    }
    # Built-in CMDLet
    Send-MailMessage -Subject $mailSubject -From $sendFrom -To $sendTo -SmtpServer $smartHost -body $mailBody -BodyAsHtml -Attachments $mailAttachment
} # End function Send-Mail

# If report switch is used, it will send a report, otherwise it will only warm up the sites.
if($report){
    Write-Host "Warming up sites. Please wait. A report will be sent once completed."
    Start-MailMessage
}
else{
    Write-Host "Warming up sites. Please wait."
    Initialize-WarmUp
}

Stop-SPAssignment -global