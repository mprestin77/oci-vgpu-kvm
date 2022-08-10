#/bin/bash
#set -x
GPU_PROFILE=$1
NUM_DEV=$2

if [ $# -ne 2 ]; then
        echo "Usage: create-mdev.sh <GPU profile> <number of devices>" 
        exit 1
fi
 
pci_ids=$(nvidia-smi vgpu -q | grep "^GPU" | cut -f 2,3 -d ':')
echo $pci_ids
if [ -z "$pci_ids" ]; then
        echo "No PCI bus with Nvidia devices was found"
        exit 1
fi
 
#Obtain the Bus/Device/Function (BDF) numbers of the host GPU device
#lspci | grep NVIDIA
echo "select PCI bus ID you want to create vGPU profile"
select id in $pci_ids
do
   pci_bus_id=$id
   break
done
 
echo $pci_bus_id
 
virtfn=$(readlink -f /sys/bus/pci/devices/0000:$pci_bus_id/virtfn*)
echo $virtfn
 
icount=0
for vf in $virtfn
do
	if [ $icount -eq $NUM_DEV ]; then
		echo "$icount devices created" 
		break
	fi

	dev=$(basename $vf)

	#Check if a device associated with this VF already exists 
	mdevctl list | grep "$dev"
	if [ $? -eq 0 ]; then
		continue
	fi

	#Create a new vGPU device for this VF
	echo $dev
	fname=$(grep -l "$GPU_PROFILE" /sys/class/mdev_bus/$dev/mdev_supported_types/nvidia-*/name)
	if [ -n $fname ]; then
		echo "Creating vGPU on $dev"
		uuid=$(uuidgen)
		echo $uuid | tee $(dirname $fname)/create
		mdevctl define --auto --uuid $uuid
		((icount+=1))

        fi	       
done 
exit 0
