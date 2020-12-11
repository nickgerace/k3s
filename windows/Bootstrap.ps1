# Get toolchain ready and build k3s for Windows
choco install -y golang minigw git kubernetes-cli
go build -i  -o k3s.exe main.go

# Prepare node
#curl https://dl.k8s.io/v1.14.7/kubernetes-node-windows-amd64.tar.gz -o kubernetes-node-windows-amd64.tar.gz
curl https://dl.k8s.io/v1.20.0/kubernetes-node-windows-amd64.tar.gz -o kubernetes-node-windows-amd64.tar.gz
tar zxvf kubernetes-node-windows-amd64.tar.gz 
mkdir C:\k
cp kube* C:\k\

# Get Flannel ready (including script below)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

################################################################################################################
# wget https://raw.githubusercontent.com/Microsoft/SDN/master/Kubernetes/flannel/start.ps1 -o c:\k\start.ps1
Param(
    [parameter(Mandatory = $true)] $ManagementIP,
    [ValidateSet("l2bridge", "overlay",IgnoreCase = $true)] [parameter(Mandatory = $false)] $NetworkMode="l2bridge",
    [parameter(Mandatory = $false)] $ClusterCIDR="10.244.0.0/16",
    [parameter(Mandatory = $false)] $KubeDnsServiceIP="10.96.0.10",
    [parameter(Mandatory = $false)] $ServiceCIDR="10.96.0.0/12",
    [parameter(Mandatory = $false)] $InterfaceName="Ethernet",
    [parameter(Mandatory = $false)] $LogDir = "C:\k",
    [parameter(Mandatory = $false)] $KubeletFeatureGates = ""
)

$BaseDir = "c:\k"
$NetworkMode = $NetworkMode.ToLower()
$NetworkName = "cbr0"

$GithubSDNRepository = 'Microsoft/SDN'
if ((Test-Path env:GITHUB_SDN_REPOSITORY) -and ($env:GITHUB_SDN_REPOSITORY -ne ''))
{
    $GithubSDNRepository = $env:GITHUB_SDN_REPOSITORY
}

if ($NetworkMode -eq "overlay")
{
    $NetworkName = "vxlan0"
}

# Use helpers to setup binaries, conf files etc.
$helper = "c:\k\helper.psm1"
if (!(Test-Path $helper))
{
    Start-BitsTransfer "https://raw.githubusercontent.com/$GithubSDNRepository/master/Kubernetes/windows/helper.psm1" -Destination c:\k\helper.psm1
}
ipmo $helper

$install = "c:\k\install.ps1"
if (!(Test-Path $install))
{
    Start-BitsTransfer "https://raw.githubusercontent.com/$GithubSDNRepository/master/Kubernetes/windows/install.ps1" -Destination c:\k\install.ps1
}

# Download files, move them, & prepare network
powershell $install -NetworkMode "$NetworkMode" -clusterCIDR "$ClusterCIDR" -KubeDnsServiceIP "$KubeDnsServiceIP" -serviceCIDR "$ServiceCIDR" -InterfaceName "'$InterfaceName'" -LogDir "$LogDir"

# Register node
powershell $BaseDir\start-kubelet.ps1 -RegisterOnly -NetworkMode $NetworkMode
ipmo C:\k\hns.psm1
################################################################################################################

# Run components
./k3s server --no-deploy servicelb coredns traefik --disable-agent
cp C:\Users\Administrator\.kube\k3s.yaml C:\k\config

# Start server
.\k3s.exe server --no-deploy traefik servicelb coredns --disable-agent

# Setup flannel
.\start.ps1 -ManagementIP 172.31.29.6 -ClusterCIDR 10.42.0.0/16 -ServiceCIDR 10.43.0.0/16 -KubeDnsServiceIP 10.43.0.10  -NetworkMode "overlay"

# Start flannel
[Environment]::SetEnvironmentVariable("NODE_NAME", (hostname).ToLower())
C:\flannel\flanneld.exe -kubeconfig-file "C:\k\config" -iface <mgmt ip> -ip-masq  -kube-subnet-mgr

# Start Kubelet
ipmo C:\k\helper.psm1
GetSourceVip -ipaddress "$mgmt-ip" -NetworkName "vxlan0"
cat .\sourceVip.json 
C:\k\start-kubelet.ps1 -NetworkMode "overlay" -KubeDNSServiceIP "10.43.0.10" -LogDir "C:\k"

# Start kubeproxy
.\start-Kubeproxy.ps1 -NetworkMode "overlay" -clusterCIDR "10.42.0.0/16" -NetworkName "vxlan0" -LogDir "C:\k"
