## WARNINGS

### It goes without saying, your decision to use this module comes with risks. For example, your ambient and loaded temperatures may be different, your device may experience new types of never seen before levels of lag, and system services may behave in profoundly illegitimate ways. My phone hasn't blown up yet, but that doesn't mean it won't. (My phone is still fine, yours should be too.)

### If you wish to use this module, please provide feedback! It will be most helpful if you can provide as many details as possible, such as the differences you notice between the stock performance and my altered performance, the environmental conditions you are in, if you are noticing increased heating compared to before, etc. The goal is to make sure these are truly the best values, and once confirmed, to submit these new values to as many custom ROMs as possible for their new default values.

### In the meantime, dear custom ROM developers: Please, refrain from adopting these new values until I determine that it is safe through community feedback to submit my own pull requests! I understand the temptations, but you will pose a risk to your community of Pixel Tensor users if you do not wait for community testing of this module. If you are faced with users who have complaints about performance, lag and/or stutter issues, kindly direct them over to this GitHub repository where I will provide releases and updates for them to try out.

---

# Pixel Tune

### Made and tested by JoshuaDoes on a Pixel 6 Pro.

## COMPATIBILITY

### MAGISK IS *REQUIRED*, NO IFS ANDS OR BUTS ABOUT IT!

So far this module is only compatible with Pixel 6 (Tensor G1) and Pixel 7 (Tensor G2) series devices due to the nature of the patches.

Additionally, for best compatibility you should be running hentaiOS/helluvaOS based on Android 15, or any other ROM that stays true to Pixel stock in the device tree. Other ROMs might need changes made for support, and you are on your own if you fall into this case.

---

## What does this module do?

This module will patch your boot ramdisk to add a Magisk overlay.d script, which allows us to override various init service definitions to change what they run and how they run. These patches allow us to modify the performance characteristics assigned to each service, and so we opt to give the important ones the capacities they deserve.

In addition, we are creating a new cpuset called `system` and allowing it access to every CPU core. Every service we patch now belongs to this cpuset, as previously the vast majority of them were restricted from accessing big cores. I believe this is helping to balance the overall load with the `top-app` cpuset, which means your little and mid cores won't have to boost so high when your primary app is at high loads - system can simply spread alongside the app on the big cores.

Lastly, we're installing a Magisk service.d script that tunes a few different kernel tunables and adjusts some power HAL settings. For example we're making the power HAL aware that many services now have access to the big cores, and we're also setting the swappiness value to 1 so that zram is avoided until it's absolutely necessary (which avoids some unnecessary RAM overhead and frees CPU time).

## Installing

For your very first time, just install it like any other module and reboot. However, every time you update your kernel or Magisk you will most likely need to reinstall.

While this module features a working uninstall script (see below), this is not how you should reinstall it! For that purpose, the action script (which is actually called by the install script) features the complete patch and install process for your convenience. Just open your modules list in Magisk and tap the `Action` button inside Pixel Tune's box, then reboot!

## Uninstalling

As mentioned earlier, this module features a working uninstall script. Because it also suppports reinstalls after boot updates, it uses the reverse of the patching logic to remove the patches regardless of other changes made since the install. No boot backups are ever used, so there is no risk of old restores.

To uninstall this module safely, just uninstall it like any other module and reboot.

### WARNING

Your device WILL bootloop once after you uninstall this module. Magisk waits to run uninstall scripts until after a reboot, and we can't just hot reload boot nor the kernel once we unpatch the boot image. Thus, the only solution is a hard reset.

A fun fact about this, during development I accidentally softlocked myself out of ever being able to run Magisk without factory resetting because the forced reboot meant Magisk didn't complete the uninstall. This resulted in an effective bootloop if I flashed Magisk at all. My fix was to install KSU because it would wipe the modules for me on boot so that it could replace Magisk - but this is how I unfortunately learned that KSU is not compatible until they have a custom init like Magisk does. And the bugfix was to simply forcefully remove the module before the hard reset. (Oopsie, lmao)

## Downloads

Release downloads: [GitHub Releases for Pixel Tune](https://github.com/JoshuaDoes/ptune/releases)

Source code: [GitHub Repository for Pixel Tune](https://github.com/JoshuaDoes/ptune)

**NOTE:** This module is no longer upgradeable through Magisk's module list! If you see an update available, you must visit the GitHub Releases tab on this repository in order to download and manually install it. It is HIGHLY recommended to install it ASAP. It may be a minor bug, or it may be something huge that I have overlooked. I want your phone to be as safe as possible when using these patches.

## Support and Feedback

Discord: @joshuadoes

Telegram: [JoshuaDoes](https://t.me/JoshuaDoes)

Twitter: [@TheNotesOfJosh](https://twitter.com/TheNotesOfJosh)

## Donations

If you enjoy the work I've done here, or any other projects I work on, please consider donating and leave a note with the projects that you used!

In order of preference:

CashApp: $JoshuaDoes

Chime: $JoshuaDoes

PayPal: [JoshuaDoes](https://paypal.me/JoshuaDoes)

Patreon: [JoshuaDoes](https://patreon.com/JoshuaDoes)

Venmo: @JoshuaDoes

