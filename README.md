## Breaking into a secure router

### Dumping the firmware: Serial Port
Get serial port access. The board has serial uart pins that work without any issues. I just connected GND, TX, RX to a usb serial adapter and I was able to see log messages from the device as it boots up.

Normally, getting access to the serial port is the first step and then the second step is to get access to the uboot shell by pressing a key during the boot process.

On this device they put a password on the uboot shell (which is not standard) and this prevented us from breaking into the device early on.

![](https://github.com/MeisterLone/Askey-RT5010W-D187-REV6/blob/master/Pic/c60631f2524e4d70c09bb43b346e29e91ed8d066.jpeg?raw=true)

### Dumping the firmware: EMMC
As it turns out, the board only has a single EMMC flash chip (no nand, no spi). This means that all of the code executed by the SoC is contained in one place, great. I decided I would desolder the EMMC and read it directly in my XGecu T56 programmer. This step ended up being uneccesary as I was later able to break into uboot without needing direct access to the storage. The EMMC was desoldered and the firmware dumped using the 1 bit ISP wires on the programmer. This component and the pads on the EMMC are extremely small and soldering onto them was an exercise in patience.

### Analyzing the firmware dump
This device is completely network locked. It doesnt even have an HTTP ui to allow for changing anything. It is a 'Cloud Router' which connects to Spectrum and is entirely managed by them (and some minimal settings in the Spectrum app). The only thing displayed in the browser when you try to connect to it, is a status page indicating whether the device was able to sync up with its cloud network.

![](https://github.com/MeisterLone/Askey-RT5010W-D187-REV6/blob/master/Pic/msedge_BHpjoS4OXV.png?raw=true)

So we are out of luck trying to use HTTP as an attack vector. 

Or are we?

In analyzing the firmware dump, I found a username & password in the filesystem

/etc/httpd.conf
```shell
    /cgi-bin/warehouse.cgi:ThylacineGone:4p@ssThats10ng
    /warehouse:ThylacineGone:4p@ssThats10ng
```
It appears there are some API's exposed that allow for special functions, such as changing the fan speed and flashing new firmware.

### Using the warehouse_api
After some researching into the system files, I figured out  that in order to use the warehouse_api, the device must be in "warehouse mode" which is determined at startup. When the board boots up, it makes a DNS request through the wan port for the following domain

WAREHOUSE.CTDI.LOCAL

It expects 2 ips to be returned for that domain, if that is the case then the router goes into "warehouse mode" and the warehouse_api becomes available to use.
I used a second OpenWrt router with the "BIND" dns server installed and configured it to respond 2 random ips for that domain. The second OpenWrt router was plugged into the WAN port on the attack router and after a reboot, the device was in warehouse mode. I could check this by visiting the CGI script at https://192.168.1.1/cgi-bin/warehouse.cgi
using the username and password mentioned in the previous post.

![](https://github.com/MeisterLone/Askey-RT5010W-D187-REV6/blob/master/Pic/JiyQzafVok.png?raw=true)

Now I had access to the following apis
```
get_current_firmware_version
get_firmware_update_status
get_mode
reboot
factory_reset
update_firmware
check_security
fan_rpm_get
fan_rpm_set
activate_tm
deactivate_tm
tm_status
fan_cond_check
```
Obviously, the most interesting thing here is update_firmware. This command takes 3 parameters;

tftpserver=
firmware=
retries=

I set up a tftp server and loaded a firmware image for a similar but different board just to see what it does. After calling the update_firmware api, I called get_firmware_update_status periodically to see what it was doing. 

Flashing..
Flashing..
Failed: IMAGE CHECK FAILURE

This was not unexpected, but at least we know we're getting somewhere. A look at the CGI script shows me that the command parameters are being passed to a utility called "fw_utils" which is an ELF binary. I opened up the binary in Ghidra to see what it was doing. I was hoping for something simple like a check for a specific string- indeed, all fw_utils was doing is a check if the string 'rt5010w-d187' and 'askey' are present in the extracted firmware image. It is also expecting a flat kernel subimage with the name "hlos" to be present. 

I used the "mkimage" tool provided by uboot along with the simple image config file below.
```
/dts-v1/;

/ {
        description = "rt5010w-d187";
        #address-cells = <1>;

        images {
                hlos {
                        description = "ARM64 OpenWrt Linux-4.4.60";
                        data = /incbin/("hlos.img");
                        type = "flat_dt";
						hash1 {
							algo = "crc32";
						};
						hash2 {
							algo = "sha1";
						};
                };
        };
}; 
```

I created a new upgrade image using the stock kernel image I dumped off the device (hlos.img). Lets pass it to the "update_firmware" api and see what happens;

Flashing..
Flashing..
Success: Upgrade complete

At this point I thought I had broken the security on the board and that I have a viable way to replace the stock firmware, but alas, she would not give up that easily.

As it turns out after further digging in Ghidra, fw_utils passes the firmware binary to a second application for processing. The second application lives inside a library called 'libopensync' which is part of proprietary software called "OpenSync". This software only functions as a tool for lazy OEMs to make locking down devices easier. It is used to create these trashy 'Cloud Routers' at scale. To my dismay, 'libopensync' does a signature check on the firmware using public key encryption. This means that only the OEM will ever have the ability to flash the device using the warehouse api. An extremely lame conlusion to my investigation into the warehouse_api.

> Side rant; locking down hardware to this extent is not only bad for the consumer but also bad for the environment. Yes, the environment. Chip manufacturers are making SoC's with security mechanisms that make them almost impervious to malicious attackers -Good, but OEMs are using these same mechanisms to keep consumers from ever actually owning the hardware they buy -Bad! Once the OEM no longer has any use for these devices, they are tossed on the trash. When devices like the Askey-RT5010W are hardenend and the only firmware the device will accept has to be signed by the OEM, the device becomes a piece of trash the moment the next generation is released. This really adds up in terms of e-waste. We need to move the needle towards more control for consumers, not less. 

![](https://github.com/MeisterLone/Askey-RT5010W-D187-REV6/blob/master/Pic/javaw_IEtuctwY9M.png?raw=true)

Above decompilation shows the input firmware signature being checked against a public key.

### Bruteforce password cracking
After gaining access to the filesystem, an attempt was made to crack the password by bruteforce. We can find the Linux root user password hash saved in the form of an MD5Crypt string in /etc/shadow.
If it were a simple password, simple pasting this string into google would get us the password. I set up a commercial password bruteforce cracking utility to try guess the password using the hash and let it run for a few weeks without success. I didnt expect much success here because we know this OEM likes to use complex passwords as we have already seen in the warehouse_api password. It is always worth a shot to try bruteforce an MD5 password if you expect a simple password but that was not the case for this device.

The password used for U-Boot uses a SHA256 hash, which is not viable for bruteforcing so that was not attempted.

![](https://github.com/MeisterLone/Askey-RT5010W-D187-REV6/blob/master/Pic/RDCMan_VKVwIeIFnf.png?raw=true)

### Hardware level attack vectors
At this point I kind of gave up trying to find a software based attack vector. This board is not going to make it easy on us. I experimented with trying to patch some of the binaries involved in the boot process to remove the password from Uboot. In order to achieve this, I needed to have write access to the EMMC on demand. (Ie, no desoldering). This could be done by a process called ISP (In-System Programming).

We only need access to 3 pins on the EMMC in order to be able to write and read from it using the T56 Programmer.

CMD
CLK
D0

I probed every exposed contact on the board to asses whether they could be the aforementioned pins. It turns out, there are no exposed contacts on the board that are directly connected to the required pins- I was going to need to expose some contacts.
Grabbed 180 grit sandpaper and cut off a tiny piece and slowly sanded away the conformal coating on the board at several target sites where I thought we would most likely see CMD, CLK or D0. It took a couple of attempts but eventually we had exposed contacts for all of the required pins. I glued breakout board onto the mainboard and soldering the wires into place. 

![](https://github.com/MeisterLone/Askey-RT5010W-D187-REV6/blob/master/Pic/3grid.jpg?raw=true)

The hook up wires I used here are extremely small and thin in order to fit onto the microscopic exposed traces. These small wires go to a breakout board which is where I plug in the T56 programmer.

Here are some things to note if you ever attempt something like this. 
1. The CLK pin should be disconnected from the processor (SoC). In the case of this router, this was easy. There was only a resistor I needed to desolder.
2. Your wires should be as short as possible- the CLK signal is fairly high frequency and prone to interference, so try to keep the length of cable you use between the EMMC and the programmer to an absolute minimum!
3. The board will power the EMMC, it is not necessary to power it externally, as long as the CLK pin is disconnected from the processor. If powering it externally, some tinkering is required and a pullup might be necessary on the CLK pin, because the CPU acts as a sink while the device is powered down. Dont attempt powering the EMMC externally and NOT disconnecting the CLK without having an oscilloscope.

### The Askey RT5010W Partition Layout
```
Name              Start      End Sectors
0:SBL1               34     2081    2048
0:BOOTCONFIG       2082     3105    1024
0:BOOTCONFIG1      3106     4129    1024
0:QSEE             4130    10273    6144
0:QSEE_1          10274    16417    6144
0:DEVCFG          16418    17441    1024
0:DEVCFG_1        17442    18465    1024
0:APDP            18466    19489    1024
0:APDP_1          19490    20513    1024
0:RPM             20514    21537    1024
0:RPM_1           21538    22561    1024
0:CDT             22562    23585    1024
0:CDT_1           23586    24609    1024
0:APPSBLENV       24610    25121     512
0:APPSBL          25122    29217    4096
0:APPSBL_1        29218    33313    4096
0:ART             33314    35361    2048
0:HLOS            35362    51745   16384
0:HLOS_1          51746    68129   16384
rootfs            68130   330273  262144
0:WIFIFW         330274   346657   16384
rootfs_1         346658   608801  262144
0:WIFIFW_1       608802   625185   16384
rootfs_data      625186  1673761 1048576
rootfs_data_1   1673762  2722337 1048576
0:ETHPHYFW      2722338  2723361    1024
econfig         2723362  2739745   16384
edata           2739746  2772513   32768
log             2772514  3034657  262144
persist         3034658  3067425   32768
usr_app         3067426  5164577 2097152
rsvd_1          5164578  5172769    8192
rsvd_2          5172770  5180961    8192
rsvd_3          5180962  5185057    4096
rsvd_4          5185058  5217825   32768
rsvd_5          5217826  5283361   65536
rsvd_6          5283362  5414437  131076
user_data       5414438 15204321 9789884
```

This device has been deliberately hardened and the attack surface has been minimized to a point where it is impractical to try gain root privledges on the OEM firmware - we will try to gain access to the device using custom firmware. Here is a quick and dirty summary of the boot stages on newer Qualcomm based boards.

### Qualcomm IPQ8072A boot process
This is a very secure process and the OEM has made sure to use several of the security mechanisms exposed by Qualcomm.

1. **Primary Bootloader**
This is the first program that the Qualcomm chip runs.  It is always at 0x4400 (partition 0:SBL1) and is refered to as the "bootrom" or SBL1. This is a relatively simple piece of software that is provided by Qualcomm. The SoC is tied to the bootrom, it is signed and the signature is checked by the SoC before execution begins. In older SoC, the bootrom is implicitly trusted as the first program in the boot chain, but these more modern SoC, Qualcomm has endeavoured to provide a secure boot chain all the way from the first user instruction that it executes. Impressive!

2. **Secondary Bootloader** (U-Boot)
The secondary bootloader is the program that prepares the device and actually loads the kernel. This program is stored in the 0:APPSBL partition on our device. U-Boot has several different boot methods that support different ways of getting the kernel image into memory. (via EMMC, via Tftp, via USB etc) The Qualcomm bootrom uses public key encryption using a certificate provided by the OEM to check the secondary bootloader before jumping to it. This means that there is no way to replace U-Boot on this device without having access to encryption keys from both Qualcomm and the OEM. In our device, the OEM implemented a custom boot method that does more than a standard U-Boot build would do. It checks the firmware image it is about to load against.. you guessed it.. a public key! This means that even if you replaced the firmware saved in the filesystem, uboot would not run it.

### How to unlock U-Boot?
U-Boot shell access is locked behind a password and we have established that there is no way to patch the boot programs in the filesystem in a way that affords us more control over the boot process and/or acesss to the U-Boot shell. The entire boot chain is signed and secured by public key encryption- however this does not bar us from modifying the configuration used by these programs. We are also free to modify these programs - *after* - they have been loaded into memory.

### Identifying a vulnerability
Luckily for us, the Askey RT5010W exposes a way for us to do exactly that, via U-Boot.

But wait, didnt I just say the entire boot chain is secured and U-Boot is password protected? Yes, but we have write access to the environment variables that U-Boot uses to configure itself.

Lets dump out the contents of the 0:APPSBLENV partition. These are loaded by U-Boot and determines how it behaves.

```
baudrate=115200
bootargs=console=ttyMSM0,115200n8
bootcmd=bootipq
bootdelay=2
eth1addr=2c:ea:dc:34:4a:ac
eth2addr=2c:ea:dc:34:4a:ac
eth3addr=2c:ea:dc:34:4a:ac
eth4addr=2c:ea:dc:34:4a:ac
ethaddr=2c:ea:dc:34:4a:ab
fdt_high=0x4A200000
fdtcontroladdr=4a985be0
fileaddr=44000000
filesize=1a0
flash_type=5
ipaddr=192.168.10.10
machid=8750106
mmcargs=mmc_mid=0x15
netmask=255.255.255.0
reboot-reason=rea=ffffffff
reboot-time=time=ffffffff
serverip=192.168.10.1
soc_version_major=2
soc_version_minor=0
stderr=serial@78B3000
stdin=serial@78B3000
stdout=serial@78B3000
```

As you have probably already guessed, "bootcmd" is the first command executed by U-Boot after it is fully initialized. We have the ability to change this command, now we are gods. Right? 
Lets just change it to something that would pull a kernel image from tftp and boot it. 

```
setenv ipaddr 192.168.0.10; setenv serverip 192.168.0.1; tftpboot kernel.img; bootm;
```

Lets see...

```markdown
bootm
secure boot fuse is enabled
Not allowed command, use bootipq.resetting ...
```

Well well well, it seems the OEM saw us coming from a mile away. The have modified the default uboot behaviour and disabled the "bootm" command entirely. Instead, they have a proprietary "bootipq" command which does the loading and booting of their signed firmware images only. 

I tried a couple of other commands. I know there's no USB port on this device, but what does the command "usbboot" do?

```markdown
usbboot
** No device specified **
IPQ807x#

```

"usbboot" gave us the expected error, but do you see what follows? It executed the command and jumped out into a shell, skipping the password check. Very, very interesting....

In fact, any command that generates some kind of error will throw us into a shell without us having to enter a password. Now we can really start playing around using the Serial Console.

We can dump memory from here, even write memory as we please. 

#### Using the vulnerability to gain control of the device
Now, we know that we can make U-Boot exit out into a shell by causing an error to throw in the current program. This is pretty easy to do if you have butchered your board like I have in order to gain write access to the storage, but given how simple this exploit is, surely there is an easier way?

Yes, yes there is. 

All we need to do is interrupt signals between the CPU and the EMMC when U-Boot is trying to load the firmware. We need to do this trick AFTER U-boot has finished initializing itself, but BEFORE U-boot loads the kernel.

The perfect time to do this is during the 2 seconds U-Boot displays this message:
```markdown
Hit space key to stop autoboot:  0
```

Once this is done, U-Boot will not be able to load the kernel image from EMMC and the bootipq command will throw us into a shell. 

After successfully interrupting U-Boot kernel load, we run the following commands to guarantee that we get a shell on every boot without needing to do the trick.

```markdown
setenv bootcmd usbboot
saveenv
```

From here, its game-over for this router. We can patch program memory as we please, and even load in new programs to get the desired behaviour.  

# How to interrupt U-Boot and get to a shell
The CLK signal that runs between the EMMC and the CPU must be interrupted at the perfect time. (3 second window)
This can be done by connecting VDDF (3v) to the CLK pin as soon as the "Hit space key to stop autoboot" message appears in the Serial Console.

I have a teardown video on youtube showing the entire process.
[Breaking into a secure router ( SAX1V1K Askey RT5010W )](https://youtu.be/tNiMljCNq3A "Breaking into a secure router ( SAX1V1K Askey RT5010W )")

1.  Open the case and remove the board. 

2. Remove the heatsink and the protective metal plate covering the CPU

3. Identify the CLK signal
 If you look closely, you will see a little resistor here. This is the CLK signal.

4. Connect a jump cable to VDDF on the serial pins

5. Get into position. Get ready to touch the other side of the jump cable onto the CLK pin.

6. Connect power to your board and watch the Serial Console output. Wait for the "Hit space key" message and as soon as you see it, touch and hold the tip of the jump cable on the CLK signal. You can touch either side of the resistor, both will work.

You should notice an error in the Serial Console followed by a command prompt. Congratualations, you're in.

If it didnt work, you can power off the device and try again. It may take a few tries. Make sure your jump cable does not touch anything else (dont touch any of the protective metal!!) or else you will risk frying the serial interface. Try to be careful!
