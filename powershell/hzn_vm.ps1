. .\common.ps1

$VMAlias = "HZN"
$VMNumber = 9
$VMName = $LabPrefix, $VMAlias -Join "-"
$IpAddress = Get-DLabIpAddress $LabNetworkBase $VMNumber

New-DLabVM $VMName -Password $LocalPassword -OSVersion $OSVersion -Force
Start-DLabVM $VMName

Wait-DLabVM $VMName 'Heartbeat' -Timeout 600 -UserName $LocalUserName -Password $LocalPassword
$VMSession = New-DLabVMSession $VMName -UserName $LocalUserName -Password $LocalPassword

Set-DLabVMNetAdapter $VMName -VMSession $VMSession `
    -SwitchName $SwitchName -NetAdapterName $NetAdapterName `
    -IPAddress $IPAddress -DefaultGateway $DefaultGateway `
    -DnsServerAddress $DnsServerAddress

Write-Host "Joining domain"

Add-DLabVMToDomain $VMName -VMSession $VMSession `
    -DomainName $DomainName -DomainController $DCHostName `
    -UserName $DomainUserName -Password $DomainPassword

# Wait for virtual machine to reboot after domain join operation

Wait-DLabVM $VMName 'Reboot' -Timeout 120
Wait-DLabVM $VMName 'Heartbeat' -Timeout 600 -UserName $DomainUserName -Password $DomainPassword

$VMSession = New-DLabVMSession $VMName -UserName $DomainUserName -Password $DomainPassword

Write-Host "Requesting RDP server certificate"

Request-DLabRdpCertificate $VMName -VMSession $VMSession `
    -CAHostName $CAHostName -CACommonName $CACommonName

Write-Host "Initializing PSRemoting"

Initialize-DLabPSRemoting $VMName -VMSession $VMSession

Write-Host "Initializing VNC server"

Initialize-DLabVncServer $VMName -VMSession $VMSession

Write-Host "Creating DNS record for VMware Horizon"

$DnsName = "horizon"
$HorizonFQDN = "$DnsName.$DomainName"
$CertificateFile = "~\Documents\cert.pfx"
$CertificatePassword = "cert123!"

Invoke-Command -ScriptBlock { Param($DnsName, $DnsZoneName, $IPAddress, $DnsServer)
    Add-DnsServerResourceRecordA -Name $DnsName -ZoneName $DnsZoneName -IPv4Address $IPAddress -AllowUpdateAny -ComputerName $DnsServer
} -Session $VMSession -ArgumentList @($DnsName, $DomainName, $IPAddress, $DCHostName)

Write-Host "Creating SPN for VMware Horizon DNS name"

$SpnAccountName = "$DomainNetbiosName\$VMName"

Invoke-Command -ScriptBlock { Param($HorizonFQDN, $SpnAccountName)
    & "setspn" "-A" "HTTP/$HorizonFQDN" $SpnAccountName
} -Session $VMSession -ArgumentList @($HorizonFQDN, $SpnAccountName)

Write-Host "Requesting certificate for VMware Horizon"

Request-DLabCertificate $VMName -VMSession $VMSession `
    -CommonName $HorizonFQDN `
    -CAHostName $CAHostName -CACommonName $CACommonName `
    -CertificateFile $CertificateFile -Password $CertificatePassword
