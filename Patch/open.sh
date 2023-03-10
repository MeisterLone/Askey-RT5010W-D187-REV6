#
# This script patches the Spectrum SAX1V1K 
#
# 1. Removes the requirement of a signed kernel image, enables the bootm command
# 2. Enables TFTP boot
# 3. Initializes network ports in U-Boot (otherwise TFTP boot is impossible)
# 4. Attempts to boot "recovery.img" from 10.0.0.10 via WAN port on every boot
#
# . Paul Francis Nel
# . sarealm@gmail.com
#

. /lib/functions.sh

echo "Finding partitions.."
ubootpart=$(find_mmc_part "0:APPSBL")
hlospart=$(find_mmc_part "0:HLOS")
envpart=$(find_mmc_part "0:APPSBLENV")
rootpart=$(find_mmc_part "rootfs")

echo "Dumping patch locations.."
b1=$(hexdump -n 4 -s 0x18670 -e '4/1 "%x" "\n"' "$ubootpart")
b2=$(hexdump -n 4 -s 0x1D4F8 -e '4/1 "%x" "\n"' "$ubootpart")

echo $b1
echo $b2

#verify uboot firmware is as expected
#do not bypass this check or you will brick your device
if [ $b1 == "7001a" ] &&  [ $b2 == "6001a" ]; 
then
	echo "U-Boot looks good."
else
	echo "Cant proceed, unknown U-Boot binary! Please send a hexdump of $ubootpart so I can check it."
	exit 1
fi

echo "Setting up U-Boot environment.."

echo "$envpart 0x0 0x40000 0x40000 1" > /etc/fw_env.config

mmcblk_hlos=$(echo "$hlospart" | sed -e "s/^\/dev\///")
hlos_start=$(cat /sys/class/block/$mmcblk_hlos/start)
hlos_size=$(cat /sys/class/block/$mmcblk_hlos/size)

fw_setenv fix_uboot "mw 4a911044 0a000007 1;mw 4a91dfdc 0a000006 1;setenv loadaddr 44000000;setenv ipaddr 10.0.0.5;setenv serverip 10.0.0.10;"
fw_setenv read_hlos_emmc "mmc read 44000000 $hlos_start $hlos_size;"
fw_setenv set_custom_bootargs "setenv bootargs console=ttyMSM0,115200n8 mmc_mid=0x15 boot_signedimg mmc_mid=0x15 boot_signedimg mmc_mid=0x15 boot_signedimg root=$rootpart rootwait"
fw_setenv setup_and_boot "run set_custom_bootargs;run fix_uboot; run read_hlos_emmc; bootm"
fw_setenv bootcmd "run fix_uboot; go 4a9647cc || sleep 3; tftpboot recovery.img; bootm || run setup_and_boot"

echo "Done!"
