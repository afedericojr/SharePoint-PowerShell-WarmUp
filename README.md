# SharePoint-PowerShell-WarmUp
SharePoint Power Shell Warmup with Report and Keep-Alive Script for 2010/2013/2016
This has only been tested on 2016 as of 5/26/2017

Run this with the -report switch to email you a report, and use -iisreset to issue an iisreset before it warms everything up.
If you created a scheduled task to run every hour for instance, and don't use a switch, it won't produce a report and will function cleanly as a keep alive.
