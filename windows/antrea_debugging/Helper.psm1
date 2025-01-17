function Get-WebFileIfNotExist($Path, $URL) {
    $count=0
    while (!(Test-Path $Path) -and ($count -ne 3)) {
        $count++
        Write-Host "Downloading $URL to $PATH"
        curl.exe -sLo $Path $URL
    }
}

function New-DirectoryIfNotExist($Path)
{
    if (!(Test-Path $Path))
    {
        mkdir $Path
    }
}

function Test-ConnectionWithRetry($ComputerName, $Port, $MaxRetry, $Interval) {
    $RetryCountRange = 1..$MaxRetry
    foreach ($RetryCount in $RetryCountRange) {
        Write-Host "Testing connection to ($ComputerName,$Port) ($RetryCount/$MaxRetry)..."
        if (Test-NetConnection -ComputerName $ComputerName -Port $Port | ? { $_.TcpTestSucceeded }) {
            return $true
        }
        if ($RetryCount -eq $MaxRetry) {
            return $false
        }
        Start-Sleep -Seconds $Interval
    }
}

function Get-GithubLatestReleaseTag($Owner, $Repo) {
    $ErrorActionPreference = "Stop"
    $AntreaReleases = (curl.exe -s "https://api.github.com/repos/$Owner/$Repo/releases" | ConvertFrom-Json)
    $ErrMsg = "Failed to get latest release tag for {$Owner, $Repo}"
    if (!($AntreaReleases -is [array])) {
        if ($AntreaReleases.message) {
            $ErrMsg = $ErrMsg + ", " + $AntreaReleases.message
        }
        Write-Host $ErrMsg
        return $null
    }
    foreach ($Release in $AntreaReleases) {
        if (!(($Release.tag_name.Split("-"))[-1].StartsWith("rc"))) {
            return $Release.tag_name
        }
    }
    Write-Host $ErrMsg
    return $null
}

function Install-AntreaAgent {
    Param(
        [parameter(Mandatory = $false, HelpMessage="Kubernetes version to use")] [string] $KubernetesVersion="v1.18.0",
        [parameter(Mandatory = $false, HelpMessage="Kubernetes home path")] [string] $KubernetesHome="c:\k",
        [parameter(Mandatory = $false, HelpMessage="kubeconfig file path")] [string] $KubeConfig="c:\k\config",
        [parameter(Mandatory = $false, HelpMessage="Antrea version to use")] [string] $AntreaVersion="latest",
        [parameter(Mandatory = $false, HelpMessage="Antrea home path")] [string] $AntreaHome="c:\k\antrea",
        [parameter(Mandatory = $false, HelpMessage="Kubernetes download")] [string] $KubernetesURL="dl.k8s.io"
    )
    $ErrorActionPreference = "Stop"
    #echo "Install-AntreaAgent :::::::::::::::::::: 1" >> C:\k\hs.log

    $kubectl = "$KubernetesHome\kubectl.exe"
    $KubeProxy = "$KubernetesHome\kube-proxy.exe"

    $CNIPath = "c:\opt\cni\bin"
    $CNIConfigPath = "c:\etc\cni\net.d"
    $AntreaCNIConfigFile = "$CNIConfigPath\10-antrea.conflist"
    $HostLocalIpam = "$CNIPath\host-local.exe"

    $AntreaEtc = "$AntreaHome\etc"
    $AntreaAgentConfigPath = "$AntreaEtc\antrea-agent.conf"
    $AntreaAgent = "$AntreaHome\bin\antrea-agent.exe"
    $AntreaCNI = "$CNIPath\antrea.exe"
    $StopScript = "$AntreaHome\Stop.ps1"
    $Owner = "vmware-tanzu"
    $Repo = "antrea"

    $env:Path = "$KubernetesHome;" + $env:Path

    if ($AntreaVersion -eq "latest") {
        $AntreaVersion = (Get-GithubLatestReleaseTag $Owner $Repo)
        if (-Not $AntreaVersion) {
            Write-Host "Failed to get Antrea version"
            return $false
        }
    }
    Write-Host "Installing AntreaAgent, Antrea version: $AntreaVersion"
    $AntreaRawUrlBase = "https://raw.githubusercontent.com/$Owner/$Repo/$AntreaVersion"
    $AntreaReleaseUrlBase = "https://github.com/$Owner/$Repo/releases/download"

    New-DirectoryIfNotExist $KubernetesHome
    # Download kubectl
    Get-WebFileIfNotExist $kubectl  "https://$KubernetesURL/$KubernetesVersion/bin/windows/amd64/kubectl.exe"
    # Download kube-proxy
    Get-WebFileIfNotExist $KubeProxy "https://$KubernetesURL/$KubernetesVersion/bin/windows/amd64/kube-proxy.exe"

    New-DirectoryIfNotExist $AntreaHome
    New-DirectoryIfNotExist "$AntreaHome\bin"
    New-DirectoryIfNotExist "$CNIPath"
    New-DirectoryIfNotExist "$CNIConfigPath"
    # Download antrea-agent for windows
    Get-WebFileIfNotExist $AntreaAgent  "$AntreaReleaseUrlBase/$AntreaVersion/antrea-agent-windows-x86_64.exe"
    Get-WebFileIfNotExist $AntreaCNI  "$AntreaReleaseUrlBase/$AntreaVersion/antrea-cni-windows-x86_64.exe"
    # Prepare antrea scripts
    Get-WebFileIfNotExist $StopScript  "$AntreaRawUrlBase/hack/windows/Stop.ps1"

    # Download host-local IPAM plugin
    if (!(Test-Path $HostLocalIpam)) {
        curl.exe -sLO https://github.com/containernetworking/plugins/releases/download/v0.8.1/cni-plugins-windows-amd64-v0.8.1.tgz
        C:\Windows\system32\tar.exe -xzf cni-plugins-windows-amd64-v0.8.1.tgz  -C $CNIPath "./host-local.exe"
        Remove-Item cni-plugins-windows-amd64-v0.8.1.tgz
    }

    New-DirectoryIfNotExist $AntreaEtc
    #echo "Install-AntreaAgent :::::::::::::::::::: 2 $AntreaEtc" >> C:\k\hs.log
    #echo (ls $AntreaEtc) >> C:\k\hs.log
    Get-WebFileIfNotExist $AntreaCNIConfigFile "$AntreaRawUrlBase/build/yamls/windows/base/conf/antrea-cni.conflist"
    Get-WebFileIfNotExist $AntreaAgentConfigPath "$AntreaRawUrlBase/build/yamls/windows/base/conf/antrea-agent.conf"
    Add-Content $AntreaAgentConfigPath "`r`nclientConnection:`r`n  kubeconfig: $AntreaEtc\antrea-agent.kubeconfig"
    Add-Content $AntreaAgentConfigPath "`r`nantreaClientConnection:`r`n  kubeconfig: $AntreaEtc\antrea-agent.antrea.kubeconfig"
    #echo "Install-AntreaAgent :::::::::::::::::::: 3 $AntreaEtc" >> C:\k\hs.log
    #echo (ls $AntreaEtc) >> C:\k\hs.log

    $KUBE_DNS_SERVICE_HOST=$(kubectl --kubeconfig=$KubeConfig get service -n kube-system kube-dns -o=jsonpath='{.spec.clusterIP}')
    $KUBE_DNS_SERVICE_PORT=$(kubectl --kubeconfig=$KubeConfig get service -n kube-system kube-dns -o=jsonpath='{.spec.ports[0].port}')
    $KUBE_DNS_SERVICE_ADDR=$KUBE_DNS_SERVICE_HOST + ":" + $KUBE_DNS_SERVICE_PORT
    Add-Content $AntreaAgentConfigPath "`r`nDNSServerOverride: $KUBE_DNS_SERVICE_ADDR"
    #echo "Install-AntreaAgent :::::::::::::::::::: 4 $AntreaEtc" >> C:\k\hs.log
    #echo (ls $AntreaEtc) >> C:\k\hs.log

    # Create the kubeconfig file that contains the K8s APIServer service and the token of antrea ServiceAccount.
    $APIServer=$(kubectl --kubeconfig=$KubeConfig get service kubernetes -o jsonpath='{.spec.clusterIP}')
    #echo "Install-AntreaAgent :::::::::::::::::::: 5 $AntreaEtc" >> C:\k\hs.log
    #echo (ls $AntreaEtc) >> C:\k\hs.log
    $APIServerPort=$(kubectl --kubeconfig=$KubeConfig get service kubernetes -o jsonpath='{.spec.ports[0].port}')
    #echo "Install-AntreaAgent :::::::::::::::::::: 6 $AntreaEtc" >> C:\k\hs.log
    #echo (ls $AntreaEtc) >> C:\k\hs.log
    $APIServer="https://$APIServer" + ":" + $APIServerPort
    #echo "Install-AntreaAgent :::::::::::::::::::: 7 $AntreaEtc" >> C:\k\hs.log
    #echo (ls $AntreaEtc) >> C:\k\hs.log
    $TOKEN=$(kubectl --kubeconfig=$KubeConfig get secrets -n kube-system -o jsonpath="{.items[?(@.metadata.annotations['kubernetes\.io/service-account\.name']=='antrea-agent')].data.token}")
    #echo "Install-AntreaAgent :::::::::::::::::::: 8 $AntreaEtc" >> C:\k\hs.log
    #echo (ls $AntreaEtc) >> C:\k\hs.log
    $TOKEN=$([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($TOKEN)))
    #echo "Install-AntreaAgent :::::::::::::::::::: 9 $AntreaEtc" >> C:\k\hs.log
    #echo (ls $AntreaEtc) >> C:\k\hs.log
    kubectl config --kubeconfig=$AntreaEtc\antrea-agent.kubeconfig set-cluster kubernetes --server=$APIServer --insecure-skip-tls-verify
    echo "Install-AntreaAgent :::::::::::::::::::: 10 $AntreaEtc" >> C:\k\hs.log
    echo (ls $AntreaEtc) >> C:\k\hs.log
    kubectl config --kubeconfig=$AntreaEtc\antrea-agent.kubeconfig set-credentials antrea-agent --token=$TOKEN
    echo "Install-AntreaAgent :::::::::::::::::::: 11 $AntreaEtc" >> C:\k\hs.log
    echo (ls $AntreaEtc) >> C:\k\hs.log
    kubectl config --kubeconfig=$AntreaEtc\antrea-agent.kubeconfig set-context antrea-agent@kubernetes --cluster=kubernetes --user=antrea-agent
    echo "Install-AntreaAgent :::::::::::::::::::: 12 $AntreaEtc" >> C:\k\hs.log
    echo (ls $AntreaEtc) >> C:\k\hs.log
    kubectl config --kubeconfig=$AntreaEtc\antrea-agent.kubeconfig use-context antrea-agent@kubernetes
    echo "Install-AntreaAgent :::::::::::::::::::: 13 $AntreaEtc" >> C:\k\hs.log
    echo (ls $AntreaEtc) >> C:\k\hs.log

    # Create the kubeconfig file that contains the antrea-controller APIServer service and the token of antrea ServiceAccount.
    $AntreaAPISServer=$(kubectl --kubeconfig=$KubeConfig get service -n kube-system antrea -o jsonpath='{.spec.clusterIP}')
    $AntreaAPISServerPort=$(kubectl --kubeconfig=$KubeConfig get service -n kube-system antrea -o jsonpath='{.spec.ports[0].port}')
    $AntreaAPISServer="https://$AntreaAPISServer" + ":" + $AntreaAPISServerPort
    kubectl config --kubeconfig=$AntreaEtc\antrea-agent.antrea.kubeconfig set-cluster antrea --server=$AntreaAPISServer --insecure-skip-tls-verify
    kubectl config --kubeconfig=$AntreaEtc\antrea-agent.antrea.kubeconfig set-credentials antrea-agent --token=$TOKEN
    kubectl config --kubeconfig=$AntreaEtc\antrea-agent.antrea.kubeconfig set-context antrea-agent@antrea --cluster=antrea --user=antrea-agent
    kubectl config --kubeconfig=$AntreaEtc\antrea-agent.antrea.kubeconfig use-context antrea-agent@antrea
    echo "Install-AntreaAgent :::::::::::::::::::: 14 $AntreaEtc" >> C:\k\hs.log
    echo (ls $AntreaEtc) >> C:\k\hs.log
    return $true
}

function New-KubeProxyServiceInterface {
    Param(
        [parameter(Mandatory = $false, HelpMessage="Interface to be added service IPs by kube-proxy")] [string] $InterfaceAlias="HNS Internal NIC"
    )
    $ErrorActionPreference = "Stop"

    $hnsSwitchName = "KubeProxyInternalSwitch"
    $INTERFACE_TO_ADD_SERVICE_IP = "vEthernet ($InterfaceAlias)"
    if (Get-NetAdapter -InterfaceAlias $INTERFACE_TO_ADD_SERVICE_IP -ErrorAction SilentlyContinue) {
        Write-Host "Network adapter $INTERFACE_TO_ADD_SERVICE_IP exists, exit."
        return
    }
    if (!(Get-VMSwitch -Name $hnsSwitchName -ErrorAction SilentlyContinue)) {
        Write-Host "Creating internal switch: $hnsSwitchName for kube-proxy"
        New-VMSwitch -name $hnsSwitchName -SwitchType Internal
    }
    Write-Host "Creating network adapter: $INTERFACE_TO_ADD_SERVICE_IP for kube-proxy"
    [Environment]::SetEnvironmentVariable("INTERFACE_TO_ADD_SERVICE_IP", $INTERFACE_TO_ADD_SERVICE_IP, [System.EnvironmentVariableTarget]::Machine)
    Add-VMNetworkAdapter -ManagementOS -Name $InterfaceAlias -SwitchName $hnsSwitchName
    Set-NetIPInterface -ifAlias $INTERFACE_TO_ADD_SERVICE_IP -Forwarding Enabled
}

function Start-KubeProxy {
    Param(
        [parameter(Mandatory = $false, HelpMessage="kubeconfig file path")] [string] $KubeProxy = "c:\k\kube-proxy.exe",
        [parameter(Mandatory = $false, HelpMessage="kubeconfig file path")] [string] $KubeConfig="c:\k\config",
        [parameter(Mandatory = $false)] [string] $LogDir = "c:\var\log\kube-proxy"
    )
    $ErrorActionPreference = "Stop"

    if (Get-Process -Name kube-proxy -ErrorAction SilentlyContinue) {
        Write-Host "kube-proxy is already in running"
        return $true
    }

    New-DirectoryIfNotExist $LogDir

    New-KubeProxyServiceInterface

    Start-Process -FilePath $KubeProxy -ArgumentList "--proxy-mode=userspace --kubeconfig=$KubeConfig --log-dir=$LogDir --logtostderr=false --alsologtostderr"
    return $true
}

function Start-OVSServices {
    $ErrorActionPreference = "Stop"
    $MaxRetry = 10
    $RetryCount = 0
    while ($true) {
        $Service = Get-Service -Name ovsdb-server
        if ($Service.Status -eq "Running") {
            break
        }
        $RetryCount += 1
        if ($RetryCount -gt $MaxRetry) {
            Write-Host "Waiting for ovsdb-server running timeout, exit"
            return $false
        }
        if ($Service.Status -eq "Stopped") {
            Start-Service ovsdb-server
        }
        Write-Host "Waiting for ovsdb-server running"
        Start-Sleep -Seconds 2
    }
    # Try to cleanup ovsdb-server configurations if the antrea-hnsnetwork is not existing. Or ovs-vswitchd service
    # will can not get started.
    if (!(Get-VMswitch -Name "antrea-hnsnetwork" -SwitchType External -ErrorAction SilentlyContinue)) {
        & ovs-vsctl.exe --no-wait --if-exists del-br br-int
        if ($LASTEXITCODE) {
            return $false
        }
    }
    $RetryCount = 0
    while ($true) {
        $Service = Get-Service -Name ovs-vswitchd
        if ($Service.Status -eq "Running") {
            break
        }
        $RetryCount += 1
        if ($RetryCount -gt $MaxRetry) {
            Write-Host "Waiting for ovsdb-vswitchd running timeout, exit"
            return $false
        }
        if ($Service.Status -eq "Stopped") {
            Start-Service ovs-vswitchd
        }
        Write-Host "Waiting for ovs-vswitchd running"
        Start-Sleep -Seconds 2
    }
    return $true
}

function Start-AntreaAgent {
    Param(
        [parameter(Mandatory = $false, HelpMessage="Antrea home path")] [string] $AntreaHome="c:\k\antrea",
        [parameter(Mandatory = $false, HelpMessage="kubeconfig file path")] [string] $KubeConfig="c:\k\config",
        [parameter(Mandatory = $false)] [string] $LogDir
    )
    $ErrorActionPreference = "Stop"

    if (Get-Process -Name antrea-agent -ErrorAction SilentlyContinue) {
        Write-Host "antrea-agent is already in running"
        return $true
    }

    if (!(Start-OVSServices)) {
        return $flase
    }

    $AntreaAgent = "$AntreaHome\bin\antrea-agent.exe"
    $AntreaAgentConfigPath = "$AntreaHome\etc\antrea-agent.conf"
    if ($LogDir -eq "") {
        $LogDir = "$AntreaHome\logs"
    }
    New-DirectoryIfNotExist $LogDir
    [Environment]::SetEnvironmentVariable("NODE_NAME", (hostname).ToLower())
    Start-Process -FilePath $AntreaAgent  -ArgumentList "--config=$AntreaAgentConfigPath --logtostderr=false --log_dir=$LogDir --alsologtostderr --log_file_max_size=100 --log_file_max_num=4"
    return $true
}

Export-ModuleMember Get-WebFileIfNotExist
Export-ModuleMember New-DirectoryIfNotExist
Export-ModuleMember Test-ConnectionWithRetry
Export-ModuleMember Install-AntreaAgent
Export-ModuleMember New-KubeProxyServiceInterface
Export-ModuleMember Start-OVSServices
Export-ModuleMember Start-KubeProxy
Export-ModuleMember Start-AntreaAgent
