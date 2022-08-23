# Deploying Nvidia vGPU Graphics Virtualization on OCI

# 1.	Introduction

NVIDIA virtual GPU (vGPU) is a graphics virtualization solution that provides multiple virtual machines (VMs) simultaneous access to one physical Graphics Processing Unit (GPU) on the VM Host Server. This article explains how to configure vGPU graphics virtualization on Nvidia Ampere GPU cards using I/O Virtualization (SR-IOV) mechanism, and how to deploy it on Oracle Cloud Infrastructure. For more information about Nvidia vGPU graphics virtualization refer to Nvidia Virtual GPU User Guide

# 2.	Prerequisites 

To use vGPU graphics virtualization you need to get vGPU drivers from NVIDIA as described in as described in [Downloading Nvidia vGPU Software](https://user-images.githubusercontent.com/54962742/184745070-39f9c88a-2187-4ead-9379-30f05daf6d75.png).
Login using your Enterprise account with Nvidia. If you don’t have an enterprise account with Nvidia you can select 90 days evaluation trial. Open Nvidia Licensing Portal / Software Downloads. Select “Product Family: VGPU”, Platform “Linux KVM”

![image](https://user-images.githubusercontent.com/54962742/184029997-257d9071-1a21-435c-a5e9-68f956904372.png)


Download zip file with the latest vGPU driver version that comes with the following files:
NVIDIA-Linux-x86_64-xxx.xx.xx-vgpu-kvm.run - vGPU manager for the VM host
NVIDIA-Linux-x86_64-xxx.xx.xx-grid.run - vGPU driver for Linux VM guest
xxx.xx_grid_win10_win11_server2016_server2019_server2022_64bit_international.exe - vGPU driver for Windows VM guest

# 3.	Configuration on OCI

3.1	Deploy a Bare Metal GPU server using one of the baremetal shapes below

BM.GPU.T1.2 (baremetal instance with 2 Nvidia A10 GPU)  
BM.GPU.10.4 (baremetal instance with 4 Nvidia A10 GPU)

Select the latest Oracle Linux 8 non-GPU image, with at least 100 GB of boot volume space.  You can deploy it in an existing VCN with a public subnet or create a new VCN with a public subnet enabling ingress traffic to SSH port TCP/22.
   
![image](https://user-images.githubusercontent.com/54962742/184030386-ab4ddfc8-5a9d-4056-97c2-015b57234026.png)


Prior to creating the instance click on “Show Advanced Options” link and open OS Management Service Agent tab.

*Note: It is recommended to uncheck “OS Management Service Agent” to avoid automatic apply of updates and patches that may cause interoperability problems with Nvidia driver*

![image](https://user-images.githubusercontent.com/54962742/184031215-a0b2e58e-430f-48e8-9195-a1864cfeb2f7.png)


3.2	Create a NSG with two rules: 
Ingress: RDP 3398/TCP (add any other required ports/protocols)
Egress: allow all/all 

*Note: if you want to enable any additional traffic to guest VMs that will be created in KVM environment on the berametal server, you can add all ingress ports/protocols to the NSG*

3.3	Create a L2 VLAN Subnet in the VCN with a /24 CIDR as a part of VCN CIDR range, and associate the created NSG with the VLAN

![image](https://user-images.githubusercontent.com/54962742/184031275-d4cf2bce-13f4-45f7-9ec3-69bb8a9dfdb5.png)
 
![image](https://user-images.githubusercontent.com/54962742/184031319-ac887206-1d9c-4750-8b7d-d201454daf9c.png)

Save VLAN ID in your records. In my example VLAN Tag is 1687

3.4	Navigate the created compute instance, go to Attached vNICs and add a vNIC attached to the VLAN

![image](https://user-images.githubusercontent.com/54962742/184031436-f293dd33-cd2c-4462-84ac-972d720ca759.png)

In the list of “Attached vNICs” you should see 2 vNICs where the 1-st one is the primary vNIC of the compute instance and the 2-d vNIC will serve is the bridge interface for guest VMs

![image](https://user-images.githubusercontent.com/54962742/184031583-36fe9015-b9d4-40f7-9cdf-1ff5d03138a8.png)


3.5	Open your VCN, click on VLANs and open the created VLAN.  Click on “Add External Access” button and add a reserved public IP for every guest VM that requires internet access (egress or ingress). Specifying private IP is optional (if not specified it will be allocated automatically from VLAN CIDR range..

*Note: This step can be deferred to a later stage once guest VM(s) are created*

![image](https://user-images.githubusercontent.com/54962742/184031677-c6ef1f8f-611c-40cb-897e-b146889a3d2a.png)


After enabling external access to guest VMs you should see all public IP(s) in your VLAN External Access list including the public IP allocated for the bridge interface itself

![image](https://user-images.githubusercontent.com/54962742/184031753-97b4afb1-b38d-4583-a5f9-5eb5aa5311fa.png)


# 4.	Oracle Linux 8 Host Setup Steps

4.1	Copy the downloaded vGPU driver files to the server and install the host driver

sudo bash NVIDIA-Linux-x86_64-xxx.xx.xx-vgpu-kvm.run

Ignore CC version check warning and hit Enter button. 

When the driver installation is finished, reboot the server:
sudo reboot

Verify driver installation

lsmod | grep nvidia

![image](https://user-images.githubusercontent.com/54962742/184041274-6f5b8697-bd3a-40ba-a822-59ec22735fb3.png)
 
Both nvidia_vgpu_vfio and nvidia modules must be loaded

Print the GPU device status with nvidia-smi command. 

nvidia-smi

![image](https://user-images.githubusercontent.com/54962742/184031942-60d6fb4e-4d57-4734-bc6d-0ef0e8aa063d.png)
 
The output of this command shows the version of the loaded Nvidia driver. The command also displays all available GPUs, shows GPU utilization, PCI Bus ID of each GPU and other statistics intended to aid in the management and monitoring of NVIDIA GPU devices.


4.2	Install required packages for KVM virtual environment

sudo dnf groupinstall -y "Server with GUI"  
sudo dnf install -y @virt  
sudo dnf install -y virt-manager  
sudo dnf install -y virt-install  

Install VNC server in order to launch virt-manager
sudo dnf install -y tigervnc-server  

4.3	Enable SR-IOV virtual functions (VFs) for GPUs 

*Note: change below values if PCI addresses reported in nvidia-smi are different*

sudo /usr/lib/nvidia/sriov-manage -e 00000000:17:00.0  
sudo /usr/lib/nvidia/sriov-manage -e 00000000:31:00.0  

Create vGPU devices with support of SR-IOV. Copy create-mdev.sh script to the server, add executable permission and run it. 

chmod +x create-mdev.sh

The script takes 2 parameters
sudo ./create-mdev.sh <GPU profile> <Number of Devices>

You can get a list of supported vGPU profiles by running

mdevctl types

For a complete list and description of Nvidia vGPU profiles, please refer to [Nvidia Virtual GPU Types](https://docs.nvidia.com/grid/latest/pdf/grid-vgpu-user-guide.pdf).

For example, if you want to create vGPU with 4GB GPU memory you have a choice of 3 A10-4 vGPU profiles:  
A10-4A – Virtual Applications  
A10-4Q – Virtual Workstations  
A10-4C – Inference Workloads  
Select the profile that is more appropriate for your workload. For example, if you want to create 6 vGPU devices with A10-4Q profile (4GB GPU memory per vGPU) run:

sudo ./create-mdev.sh A10-4Q 6

The script checks for all available PCI bus IDs and prompts you to select one where you want to create vGPU devices:

![image](https://user-images.githubusercontent.com/54962742/184044288-6c25b2ad-870e-4b26-806b-2084f2aa9dca.png)

Enter the number to select PCI bus you are creating the devices on.

On completion the scrips shows the total number of created vGPU devices, for example:

![image](https://user-images.githubusercontent.com/54962742/184044781-7f337305-0dd0-480b-b637-1781ddf4b06f.png)
 

Check that all vGPU devices are created

mdevctl list

![image](https://user-images.githubusercontent.com/54962742/184044748-083e7527-fcca-4bc4-8ed2-cdf940515d9b.png)

 
*Note: In this example the name of vGPU profile “nvidia-593” corresponds to A10-4Q vGPU profile. However, on your server the profile could be different. It depends on Nvidia driver version*

Rerun the script for every VGPU profile that you want to create. Only a single vGPU profile can be configured per GPU.

Add to root’s crontab to persist all configured devices after server reboot

sudo crontab -e
@reboot sudo /usr/lib/nvidia/sriov-manage -e ALL
4.4	Start libvirt service and enable automatic restart after server reboot

sudo systemctl start libvirtd
sudo systemctl enable libvirtd 

Configure libvirt user account
sudo usermod -a -G libvirt $(whoami)

4.5	Create a filesystem on NVMe disk and mount it under /mnt/data.

Check the name of NVMe device

lsblk
 
![image](https://user-images.githubusercontent.com/54962742/184044956-5c39f0a6-0c93-4523-8e1b-efa9b96eb20e.png)


*Note: if you need more space than the size of the local NVMe disk you can add Block Storage disk to the server and create a filesystem on it*

sudo mkfs.ext4 /dev/nvme0n1
sudo mkdir /mnt/data
sudo mount -t ext4 /dev/nvme0n1 /mnt/data

Update /etc/fstab file to mount this filesystem after server reboot

sudo vi /etc/fstab

Add a new line to the end of of the file

/dev/nvme0n1    /mnt/data       ext4    defaults,noatime,_netdev      0      2


4.6	Go back to ssh session and create a bridge interface to connect the OCI L2 VLAN on the primary host NIC to all the VM's PV NICs. Configure bridge network interface on the server. 

sudo vi  /etc/sysconfig/network-scripts/ifcfg-bridge1

Add the following content and save the file  
STP=no  
TYPE=Bridge  
PROXY_METHOD=none   
BROWSER_ONLY=no  
BOOTPROTO=none  
IPV4_FAILURE_FATAL=no   
NAME=bridge1  
DEVICE=bridge1  
ONBOOT=yes  
AUTOCONNECT_SLAVES=yes  

Attach the bridge to the VLAN interface

sudo vi /etc/sysconfig/network-scripts/ifcfg-ens300f0.1687 
where:
ens300f0 is the primary host NIC
1687 is the L2 VLANs VLAN tag that you copied in step 4 

Add the following content replacing VLAN ID with your VLAN tag  
VLAN=yes  
TYPE=Vlan  
PHYSDEV=ens300f0   
VLAN_ID=1687  
REORDER_HDR=yes   
GVRP=no  
MVRP=no  
NAME=ens300f0.1687   
DEVICE=ens300f0.1687   
ONBOOT=yes  
BRIDGE=bridge1  

Bring up the bridge and host VLAN interfaces and restart the network service.  Check whether newly created interfaces are showing up after network restart:


ifup bridge1
ifup ens300f0.1681
 
sudo systemctl restart network
 
sudo ip link show
sudo systemctl restart network
sudo ip link show
 
![image](https://user-images.githubusercontent.com/54962742/184032443-2c03b4ed-09fe-4a9a-a206-6505831b063b.png)

4.7	Make an ISO of the vGPU driver for guest VMs
genisoimage -o vgpu-guest-driver.iso 512.78_grid_win10_win11_server2016_server2019_server2022_64bit_international.exe 

# 5.	Configuration in KVM

5.1	 Start VNC server 

vncserver

It will prompt you to create VNC password. Enter VNC password and verify it. You don’t need view-only password. Check that vnc server is listening on port 5901 (or another 59xx VNC port)

netstat -plnt

![image](https://user-images.githubusercontent.com/54962742/184032516-d055c334-0b49-4516-b56a-d2afbfd7615a.png)
 
Exit from ssh session to create ssh tunnel for vnc

ssh -L59000:localhost:5901 opc@<instance-ip>

Start VNC Viewer on your computer and connect to localhost:59000. It will prompt you to enter VNC password that you configured in step 12. Check that VNC connection is successful. If you are prompted “Authentication Required to create a color profile” you can cancel it and proceed with VNC setup.  It should connect you to the server desktop.

5.2 Open a terminal and type “virt-manager” command. virt-manager is a graphical tool for managing guest virtual machines (VM) via libvirt. You can create virtual machines using virt-manager, however, in this article I’ll use a command line utility “virt-install” to create VMs.

Here is an example of virt-install command to create a guest windows VM:
 
sudo virt-install \
--name vm1 \
--description "Windows 10 VM" \
--boot uefi \
--os-type=Windows \
--os-variant=win10 \
--memory=4096 \
--vcpus=2 \
--cpu host-passthrough \
--cdrom /mnt/data/iso/Win10_21H2_English_x64.iso \
--disk path=/mnt/data/vms/vm1.qcow2,format=qcow2,bus=virtio,size=50 \
--disk path=/mnt/data/iso/winvirtio.iso,device=cdrom \
--network bridge:bridge1,model=virtio 

Use it as a template and customize it with VM name, vcpu, memory and disk size, updated path to disk and cdrom ISO files. 

In this example I am using virtIO NIC and disk devices in the guest VM. You can download virtIO drivers from Oracle VirtIO Drivers for Microsoft Windows for Use With KVM

If successful you’ll see the output of the command

Starting install...
Allocating 'vm1.qcow2'                                                                                                                                                                                                                     | 100 GB  00:00:00     
Domain is still running. Installation may be in progress.
Waiting for the installation to complete.

In virt-manager window you’ll see a new VM created and running.  To begin Installation double click on the VM name and it opens the VM console. You’ll see a message

Press any key if you want to boot from CD…

Press any key to continue with the installation. If you didn’t hit any key it will enter Boot Manager menu. Select “Reset” option and it will prompt to you press any key to boot from CD again.

When installing a Windows VM enter the product or select "I don't have a product key" when prompted. Select Windows Edition you want to install.  
*Note: If you are installing Windows 11 OS it requires a TPM and secure boot. This requirement can be bypassed before installation. Power off and start the VM again. Hit shift-F10 on the keyboard which will bring up a command prompt. From the command line, run "regedit". Under HKEY_LOCAL_MACHINE\SYSTEM\Setup add a new item (folder) named "LabConfig". Within the newly created LabConfig item, make two DWORD entries setting their values both to hex 1 - "BypassTPMCheck" and "BypassSecureBootCheck". Exit regex and continue installation as normal.* 


Windows setup will not detect virtIO disk because the driver is not installed. 

![image](https://user-images.githubusercontent.com/54962742/184032616-1fe3e5cf-294d-41e5-8da7-e696beb6a0d0.png)


Click on Load driver icon navigating to the cdrom with virtIO ISO file and browse virtIO driver location

![image](https://user-images.githubusercontent.com/54962742/184036587-d3e2e7ab-74cf-43bf-aced-091ae0db8109.png)
 

Select both VirtIO Ethernet Adapter and VirtIO SCSI controller drivers to install

![image](https://user-images.githubusercontent.com/54962742/184036725-2bd2d34b-bf51-493a-9d97-18b517375425.png)
 

After that Windows setup should detect the hard drive

![image](https://user-images.githubusercontent.com/54962742/184036826-df8eb4fc-1e6a-45c7-addf-11e006a1a4a6.png)
 

Click Next and proceed with Windows installation. 

# 6.	Windows VM Configuration

6.1	After installation of Windows OS edit networking configuration. Open Network Connections / Properties and edit IP settings. Select “Manual” and enable IPV4. Configure IPV4 static IP address to match the private IP configured in VLAN External Access in step 3.5. In my example, for vm1 I configured VLAN private IP address 10.0.79.11. The same static IP must be configured in the guest OS. For Gateway and DNS I am using the 1-st IP on VLAN subnet that in my case is 10.0.79.1

![image](https://user-images.githubusercontent.com/54962742/184036883-a343c1a3-39b6-41c7-abdf-ad134aac5f00.png)
 
Check that you can ping the gateway IP 10.0.79.1 and check that you have an external connectivity (ping 8.8.8.8). 

Open System / Remote Desktop and enable Remote Desktop connection in Windows OS. You should be able to RDP the VM using the public IP assigned in step 3.5.

6.2	Shutdown the VM and wait until the VM is stopped.  In virt-manager window edit the VM configuration by double clicking on the VM and clicking the Lightbulb icon. Navigate to the CD-ROM and change the ISO from Windows ISO to the vgpu-guest-driver.iso created in step 4.7.

Return to the terminal console of the host. Manually edit the VM configuration using virsh command to add mdev device with the unique ID you used when creating the vGPU device

sudo virsh edit vm1 

Scroll down to the <devices> section and add the following XML. Use the UUID that matches the target VF. 

*Note: you can get a list of all UUID associated with created vGPU VF by running  
sudo mdevctl list*

<hostdev mode='subsystem' type='mdev' model='vfio-pci'>
<source>
<address uuid='0f2d035e-43fb-4f82-beaa-abc9ff87bb53'/>
</source>
</hostdev>

Save the changes by typing ':wq' and pressing enter. Start the VM from virt-manager.  Connect to VM console, go to the CDROM drive with Nvidia vGPU driver ISO, install the driver and reboot the VM.

Use RDP to connect to the instance using the public IP assigned to the VM.

Open Device Manager and check that Windows OS detects Nvidia Display Adapter with the configured vGPU profile.
 
![image](https://user-images.githubusercontent.com/54962742/184036931-92d8575d-e31b-4567-be85-f6b32f419fea.png)

6.3	Run regedit and create an entry for the vGPU license server
Location: HKEY_LOCAL_MACHINE\SOFTWARE\NVIDIA Corporation\Global\GridLicensing
Value: ServerAddress String(REG_SZ) 
The value should be set to your license server IP address 

For more information about Nvidia vGPU licensing refer to Configuring a Licensed Client of Nvidia License System.

# 7. Cloning Virtual Machines

7.1 You can create more VMs by cloning an existing VM. Open virt-manager and shutdown the VM you are going to clone. Prior to cloning you can edit VM properties and remove ISO files from CDROM(s). After that right click on the VM and select “Clone” option. Edit the name of the new VM qcow2 file, and type on Clone button.  

![image](https://user-images.githubusercontent.com/54962742/184036977-9ffb2494-dd0f-4475-85dc-1933d4da5e8c.png)
 

7.2 Once VM is cloned return to the terminal console edit the new VM XML file to associate it with a new UUID. 

*Note: you can get a list of all UUID associated with created vGPU VF by running   
sudo mdevctl list*

The 1st UUID you already configured in the 1st VM. Use the next available UUID.

To edit the new VM XML file run

sudo virsh edit <vm-name>

and search for “hostdev” device and replace UUID (see step 6.2)
  
From virt-manager start the new VM and then using your RDP client RDP to the VM. The new VM is configured with the same static IP address as the original VM you were cloning from. In RDP session use the same public IP you used to connect the 1st VM. Open Network Connections in Windows OS and edit IP address of the new VM.

*Note: for the list of configured private and public VM see step 3.5*

After setting the new static IP your RDP session will be disconnected. Create a new RDP session with the public IP associated with the new VM (see step 3.5). At this stage you can start both VMs since they don’t have IP conflict anymore. Nvidia display adapter should be shown in Device Manager of both VMs. 

# 8. Monitoring vGPU Usage

8.1 To monitoring vGPU usage of guest VMs run from the host 

nvidia-smi vgpu -l

![image](https://user-images.githubusercontent.com/54962742/184037003-6c9070ac-5e33-4772-be79-8c8c2f76e721.png)
  

To create GPU load start streaming or playing games using GPU inside a guest VM.  

8.2 You can also monitor vGPU usage from guest VM OS in Windows Task Manager

![image](https://user-images.githubusercontent.com/54962742/184037044-4bf59268-985c-4459-ab8e-c392a4f597b4.png)
  
