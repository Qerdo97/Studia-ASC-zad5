### Variables
$index_number = 17313
$default_location_id = 'northeurope'

# Main function
function Invoke-Main
{
    CheckAdminRights
    Dependencies
    ConnectToAzure

    # Dynamicly created variable with name of the location
    $default_location = Get-AzLocation | Where-Object { $_.Location -eq $default_location_id } | Select-Object -ExpandProperty DisplayName

    CreateResourceGroup -resource_group_name $index_number -location $default_location
    CreateVirtualNetwork -resource_group_name $index_number -location $default_location -virtual_network_name "WITNET_$index_number" -address_space '10.10.0.0/16' -subnet_name "WITSUBNET_$index_number" -subnet_address_space '10.10.10.0/24'

    ### VMs
    CreateVirtualMachine -resource_group_name $index_number -location $default_location_id -VMname "WIT-${index_number}-VM1" -login 'WitAdmin' -password 'Pa$$w0rd123456' -networkName "WITNET_$index_number" -subnetName "WITSUBNET_$index_number" -image Win2019Datacenter
    CreateVirtualMachine -resource_group_name $index_number -location $default_location_id -VMname "WIT-${index_number}-VM2" -login 'WitAdmin' -password 'Pa$$w0rd123456' -networkName "WITNET_$index_number" -subnetName "WITSUBNET_$index_number" -image Win2019Datacenter
    # Wait for all jobs to complete
    While (Get-Job -State "Running")
    {
        Start-Sleep 10
    }
    # Process the results
    foreach ($job in Get-Job)
    {
        $result = Receive-Job $job
        if ($( $result.ProvisioningState ) -eq 'Succeeded')
        {
            Write-Host -ForegroundColor Green "Maszyna $( $result.Name ) pomyślnie utworzona"
        }
    }
    # Cleanup
    Remove-Job -State Completed

    Write-Host -ForegroundColor Green "Tworzenie grupy zabezpieczeń aplikacji ${index_number}_AG-PSWWW"
    New-AzApplicationSecurityGroup -ResourceGroupName $index_number -Name "${index_number}_AG-PSWWW" -Location $default_location -Force -AsJob | Out-Null
    Write-Host -ForegroundColor Green "Tworzenie grupy zabezpieczeń aplikacji ${index_number}_AG-MGM"
    New-AzApplicationSecurityGroup -ResourceGroupName $index_number -Name "${index_number}_AG-MGM" -Location $default_location -Force -AsJob | Out-Null
    # Wait for all jobs to complete
    While (Get-Job -State "Running")
    {
        Start-Sleep 10
    }
    # Process the results
    foreach ($job in Get-Job)
    {
        $result = Receive-Job $job
        if ($( $result.ProvisioningState ) -eq 'Succeeded')
        {
            Write-Host -ForegroundColor Green "Grupa zabezpieczeń aplikacji $( $result.Name ) pomyślnie utworzona"
        }
    }
    # Cleanup
    Remove-Job -State Completed



    $NewNSG = PrepareNSG
    SwitchAllVMsNICsToCustomOne -new_NSG $NewNSG
    ChangeASGforVM -VMname "WIT-${index_number}-VM1" -ASGname "${index_number}_AG-MGM"
    ChangeASGforVM -VMname "WIT-${index_number}-VM2" -ASGname "${index_number}_AG-PSWWW"
    hostWebsiteOnVM -vmName "WIT-${index_number}-VM2"
    $ip = checkPublicIPofVM -vmName "WIT-${index_number}-VM2"

    # Webbrowser run to check the website
    Write-Host -ForegroundColor Green "Otwieranie przeglądarki internetowej i prezentacja strony..."
    Start-Process "http://${ip}:9090"

    listAllResources
    Remove-Job *
    cleanup
    Write-Host -ForegroundColor Green "Koniec"
}

function CheckAdminRights
{
    Write-Host -ForegroundColor Yellow 'Sprawdzanie uprawnień administratora'
    If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator"))
    {
        Write-Host -ForegroundColor Red "Ten skrypt musi być uruchomiony z uprawieniami administratora!!!"
        Write-Host -ForegroundColor Red ""
        Write-Host -ForegroundColor Red -NoNewLine 'Wciśnij dowolny klawisz aby kontynuować...';
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
        exit 1
    }
    Write-Host -ForegroundColor Green 'Skrypt uruchomiony z uprawnieniami administratora'
}

function Dependencies
{
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
    Write-Host -ForegroundColor Yellow 'Sprawdzanie wymaganych zależności'
    if ($null -eq $( Get-InstalledModule -Name Az -ErrorAction Ignore ))
    {
        Write-Host -ForegroundColor Yellow 'Moduł Az nie jest zainstalowany'
        Write-Host -ForegroundColor Yellow 'Instalacja modułu Az'
        Install-Module -Name AZ -AllowClobber -Scope AllUsers -Repository PSGallery -Force
    }
    else
    {
        Write-Host -ForegroundColor Green 'Moduł Az jest zainstalowany'
    }
    Write-Host -ForegroundColor Yellow 'Importowanie zależności'
    Import-Module Az
    Write-Host -ForegroundColor Green 'Zależności zaimportowane'
}

function ConnectToAzure
{
    try
    {
        Write-Host -ForegroundColor Yellow "Logowanie do Azure..."
        Connect-AzAccount -ErrorAction Stop -WarningAction Ignore | Out-Null;
    }
    catch
    {
        Write-Host -ForegroundColor Red "Brak dostępu do Azure"
        exit 1
    }
    Write-Host -ForegroundColor Green "Połączono z Azure"
}

function CreateResourceGroup
{
    param
    (
        $resource_group_name,
        $location
    )
    Write-Host -ForegroundColor Green "Tworzenie grupy zasobów $resource_group_name..."
    New-AzResourceGroup -Name $resource_group_name -Location $location -Force | Out-Null
    Write-Host -ForegroundColor Green "Grupa zasobów $resource_group_name została utworzona"
}

function CreateVirtualNetwork
{
    param
    (
        $resource_group_name,
        $virtual_network_name,
        $location,
        $address_space,
        $subnet_name,
        $subnet_address_space
    )
    Write-Host -ForegroundColor Green "Tworzenie sieci wirtualnej $virtual_network_name..."
    $virtualNetwork = New-AzVirtualNetwork -Name $virtual_network_name -ResourceGroupName $resource_group_name -Location $location -AddressPrefix $address_space -Force -ErrorAction Ignore -WarningAction Ignore
    Write-Host -ForegroundColor Green "Sieć wirtualna $virtual_network_name została utworzona"
    Write-Host -ForegroundColor Green "Tworzenie podsieci..."
    Add-AzVirtualNetworkSubnetConfig -Name $subnet_name -AddressPrefix $subnet_address_space -VirtualNetwork $virtualNetwork -ErrorAction Ignore -WarningAction Ignore | Out-Null
    $virtualNetwork | Set-AzVirtualNetwork | Out-Null
    Write-Host -ForegroundColor Green "Podsieć $subnet_name została utworzona"
}

function CreateVirtualMachine
{
    param
    (
        $VMname,
        $login,
        $password,
        $resource_group_name,
        $location,
        $networkName,
        $subnetName,
        $image
    )
    $password_secure = ConvertTo-SecureString -String $password -AsPlainText -Force
    $credentials = New-Object System.Management.Automation.PSCredential -ArgumentList $login, $password_secure
    Write-Host -ForegroundColor Green "Tworzenie maszyny wirtualnej $VMname..."
    try
    {
        New-AZVM `
        -Name $VMname `
        -ResourceGroupName $resource_group_name `
        -Location $location `
        -Credential $credentials `
        -Size Standard_D2_v2 `
        -SubnetName $subnetName `
        -VirtualNetworkName $networkName `
        -Image $image `
        -WarningAction Ignore `
        -AsJob | Out-Null
    }
    catch
    {
        Write-Host -ForegroundColor Red "Maszyna wirtualna $VMname nie została utworzona"
    }
}

function PrepareNSG
{
    ### NSG Rules
    $ASG_PSWW_id = Get-AzApplicationSecurityGroup -Name "${index_number}_AG-PSWWW" | Select-Object -ExpandProperty Id
    $ASG_MGM_id = Get-AzApplicationSecurityGroup -Name "${index_number}_AG-MGM" | Select-Object -ExpandProperty Id

    Write-Host -ForegroundColor Green "Tworzenie reguł zabezpieczeń..."
    $rule1 = New-AzNetworkSecurityRuleConfig -Name "${index_number}_PS" -Direction Inbound -SourceAddressPrefix * -DestinationApplicationSecurityGroupId $ASG_PSWW_id -SourcePortRange * -DestinationPortRange '5985' -Protocol * -Priority 100 -Access Allow
    $rule2 = New-AzNetworkSecurityRuleConfig -Name "${index_number}_WWW1" -Direction Inbound -SourceAddressPrefix * -DestinationApplicationSecurityGroupId $ASG_PSWW_id -SourcePortRange * -DestinationPortRange '9090' -Protocol * -Priority 110 -Access Allow
    $rule3 = New-AzNetworkSecurityRuleConfig -Name "${index_number}_WWW2" -Direction Inbound -SourceAddressPrefix * -DestinationApplicationSecurityGroupId $ASG_PSWW_id -SourcePortRange * -DestinationPortRange '443' -Protocol * -Priority 120 -Access Allow
    $rule4 = New-AzNetworkSecurityRuleConfig -Name "${index_number}_MGM" -Direction Inbound -SourceAddressPrefix * -DestinationApplicationSecurityGroupId $ASG_MGM_id -SourcePortRange * -DestinationPortRange '3389' -Protocol * -Priority 130 -Access Allow


    ### NSG
    try
    {
        Write-Host -ForegroundColor Green "Tworzenie grupy zabezpieczeń sieciowych ${index_number}_NSG"
        $nsg = New-AzNetworkSecurityGroup -ResourceGroupName $index_number -Location $default_location_id -Name "${index_number}_NSG" -SecurityRules $rule1, $rule2, $rule3, $rule4 -Force
    }
    catch
    {
        Write-Host -ForegroundColor Red "Grupa zabezpieczeń sieciowych ${index_number}_NSG nie utworzona"
    }
    Write-Host -ForegroundColor Green "Grupa zabezpieczeń sieciowych ${index_number}_NSG utworzona wraz z regułami"
    return $nsg
}
function SwitchAllVMsNICsToCustomOne
{
    param (
        $new_NSG
    )
    foreach ($vm in Get-AzVM -ResourceGroupName $index_number)
    {
        #        $vm | Select-Object -Property *
        Write-Host -ForegroundColor Green "Przypisywanie $( $new_NSG.Name ) do maszyny wirtualnej $( $vm.Name )"
        $NIC = Get-AzNetworkInterface -ResourceId $( $vm.NetworkProfile.NetworkInterfaces[0].Id )
        $NIC.NetworkSecurityGroup = $new_NSG
        $NIC | Set-AzNetworkInterface | Out-Null
        Write-Host -ForegroundColor Green "$( $new_NSG.Name ) przypisany do maszyny wirtualnej $( $vm.Name )"
    }
}
function ChangeASGforVM
{
    param (
        $VMname,
        $ASGname
    )
    Write-Host -ForegroundColor Green "Przypisywanie grupy zabezpieczeń sieciowych $ASGname do maszyny wirtualnej $VMname"
    $Vm = Get-AzVM -Name $VMname
    $nic = Get-AzNetworkInterface -ResourceId $Vm.NetworkProfile.NetworkInterfaces.id
    $Asg = Get-AzApplicationSecurityGroup -Name $ASGname
    $nic.IpConfigurations[0].ApplicationSecurityGroups = $Asg
    $nic | Set-AzNetworkInterface | Out-Null
    Write-Host -ForegroundColor Green "Grupa zabezpieczeń sieciowych $ASGname przypisana do maszyny wirtualnej $VMname"
}
function prepareRemoteSubscript
{
    $content = @"
set-executionpolicy unrestricted
`$SiteFolderPath = "C:\WebSite"
`$SiteName = "CSBG"
Write-Host "Disabling Firewall..."
Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled False
Import-Module ServerManager
Install-WindowsFeature -Name Web-Server -IncludeAllSubFeature -IncludeManagementTools
Add-WindowsFeature Web-Scripting-Tools
Import-Module WebAdministration
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module -Name 'IISAdministration' -Force
Import-Module -Name 'IISAdministration'
Install-WindowsFeature web-mgmt-console
New-Item -Path `$SiteFolderPath -type Directory
Set-Content `$SiteFolderPath\Default.htm "<h1>Hello CBSG Polska Sp. z o.o.</h1>"
New-IISSite -Name `$SiteName -PhysicalPath `$SiteFolderPath -BindingInformation "*:9090:"

"@
    Write-Host -ForegroundColor Green "Tworzenie zdalnego skryptu remote_script.ps1"
    New-Item -Path ${PSScriptRoot} -ItemType file -Name "remote_script.ps1" -Force -Value $content | Out-Null
    Write-Host -ForegroundColor Green "Utworzono zdalny skrypt remote_script.ps1"
}
function hostWebsiteOnVM
{
    param(
        $vmName
    )
    prepareRemoteSubscript
    Write-Host -ForegroundColor Green "Uruchamianie serwera WWW na maszynie wirtualnej $vmName"
    try
    {
        Invoke-AzVMRunCommand -ResourceGroupName $index_number -VMName $vmName -CommandId 'RunPowerShellScript' -ScriptPath "${PSScriptRoot}/remote_script.ps1" | Out-Null
        Write-Host -ForegroundColor Green "Serwer WWW uruchomiony na maszynie wirtualnej $vmName"
    }
    catch
    {
        Write-Host -ForegroundColor Red "Nie udało się uruchomić serwera WWW na maszynie wirtualnej $vmName"
    }
}
function checkPublicIPofVM
{
    param(
        $vmName
    )
    Write-Host -ForegroundColor Green "Sprawdzanie adresu IP publicznego maszyny wirtualnej $vmName"
    try
    {
        $ip = Get-AzPublicIpAddress -ResourceGroupName $index_number -Name $vmName | Select-Object -ExpandProperty IpAddress
        Write-Host -ForegroundColor Green "Adres IP publiczny maszyny wirtualnej ${vmName}: $ip"
    }
    catch
    {
        Write-Host -ForegroundColor Red "Maszyna wirtualna $vmName nie posiada adresu IP publicznego"
    }
    return $ip
}
function listAllResources
{
    Write-Host -ForegroundColor Green "Lista wszystkich zasobów w grupie $index_number"
    $resources = Get-AzResource -ResourceGroupName $index_number | Select-Object -Property Name, ResourceGroupName, ResourceType, Location, Tags
    Write-Host -ForegroundColor Green "Lista zasobów w grupie $index_number"
    $resources
}
function cleanup
{
    Remove-Item -Force "$PSScriptRoot\remote_script.ps1"
    $confirmation = Read-Host "Czy chcesz usunąć wszystkie zasoby z grupy $index_number? (y/n)"
    while ($confirmation -notmatch "[yY]")
    {
        if ($confirmation -match "[nN]")
        {
            Write-Host -ForegroundColor Green "Anulowano usuwanie zasobów z grupy $index_number"
            return
        }
    }
#    Write-Host -ForegroundColor Green "Czyszczenie grupy zasobów $index_number"
#    $resources = Get-AzResource -ResourceGroupName $index_number | Select-Object -Property Name, ResourceGroupName, ResourceType, Location, Tags, ResourceId
#    foreach ($resource in $resources)
#    {
#        Write-Host -ForegroundColor Green "Usuwanie zasobu $( $resource.Name )"
#        Remove-AzResource -ResourceId $( $resource.ResourceId ) -Force -AsJob -ErrorAction Ignore -WarningAction Ignore | Out-Null
#    }
#    # Wait for all jobs to complete
#    Get-Job | Wait-Job | Out-Null
#    # Process the results
#    foreach ($job in Get-Job)
#    {
#        $result = Receive-Job $job
#        if ($( $result.ProvisioningState ) -eq 'Succeeded')
#        {
#            Write-Host -ForegroundColor Green "Zasób $( $result.Name ) usunięty"
#        }
#    }
#    # Cleanup
#    Remove-Job -State Completed

    Write-Host -ForegroundColor Green "Usuwainie grupy zasobów $index_number"
    Remove-AzResourceGroup -Name $index_number -Force | Out-Null
    Write-Host -ForegroundColor Green "Grupa zasobów $index_number usunięta"
}
Invoke-Main
