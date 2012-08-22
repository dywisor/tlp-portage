# Copyright 1999-2012 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: $

EAPI=4

inherit eutils bash-completion-r1

DESCRIPTION="Power-Management made easy, designed for Thinkpads."
HOMEPAGE="https://github.com/linrunner/TLP/wiki/TLP-Linux-Advanced-Power-Management"
SRC_URI="https://github.com/downloads/dywisor/tlp-gentoo/${P}-${PR}-gentoo.tar.bz2"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS=""
IUSE="+X +thinkpad tpacpi usb rdw bash-completion smartmontools ethtool lsb-release laptop-mode-tools"

DEPEND=""
RDEPEND="
sys-power/pm-utils
sys-power/upower
sys-apps/hdparm
sys-apps/dmidecode
net-wireless/wireless-tools
net-wireless/rfkill
sys-fs/udev
sys-apps/usbutils
thinkpad?           ( app-laptop/tp_smapi )
rdw?                ( net-misc/networkmanager )
tpacpi?             ( dev-lang/perl )
usb?                ( dev-lang/perl )
smartmontools?      ( sys-apps/smartmontools )
ethtool?            ( sys-apps/ethtool )
lsb-release?        ( sys-apps/lsb-release )
!laptop-mode-tools? ( !app-laptop/laptop-mode-tools )"

RESTRICT="mirror"

# pm hooks to disable defined by upstream
#
# hookss that have a different name in gentoo:
#  * <none>
#
CONFLICTING_PM_POWERHOOKS_UPSTREAM="95hdparm-apm disable_wol hal-cd-polling
intel-audio-powersave harddrive laptop-mode journal-commit pci_devices
pcie_aspm readahead sata_alpm sched-powersave usb_bluetooth wireless xfs_buffer"

CONFLICTING_PM_POWERHOOKS="${CONFLICTING_PM_POWERHOOKS_UPSTREAM}"

TLIB=/usr/lib/tlp-pm
PLIB=/usr/lib/pm-utils
PMETC=/etc/pm
ULIB=/usr/lib/udev
NMDSP=/etc/NetworkManager/dispatcher.d

TLP_NOP=${PLIB}/tlp-nop

src_install() {
	# tlp-stat needs root priv -> /usr/sbin
	dosbin tlp tlp-stat

	newbin tlp-rf bluetooth
	dosym "bluetooth" "/usr/bin/wifi"
	dosym "bluetooth" "/usr/bin/wwan"

	newbin tlp-run-on run-on-ac
	dosym "run-on-ac" "/usr/bin/run-on-bat"

	use usb && dobin tlp-usblist

	insinto "${TLIB}"
	doins tlp-functions tlp-rf-func tlp-nop

	if use tpacpi; then
		exeinto "${TLIB}"
		doexe tpacpi-bat
	fi

	exeinto "${ULIB}"
	doexe udev/tlp-usb-udev

	insinto "${ULIB}/rules.d"
	newins udev/rules/tlp.rules 40-tlp.rules

	doconfd conf/tlp

	newinitd gentoo/init-tlp tlp

	exeinto "${PLIB}/power.d"
	doexe zztlp

	exeinto "${PLIB}/sleep.d"
	doexe 49bay 49wwan

	dodoc README
	dodoc gentoo/README.gentoo

	if [[ -d man ]];then
		doman man/*
	fi

	if use X; then
		insinto /etc/xdg/autostart
		doins tlp.desktop
	fi

	if use bash-completion; then
		newbashcomp "tlp.bash_completion" "${PN}"
	fi

	if use rdw; then
		insinto "${ULIB}/rules.d"
		newins udev/rules/tlp-rdw.rules 40-tlp-rdw.rules

		exeinto "${ULIB}"
		doexe udev/tlp-rdw-udev

		exeinto "${NMDSP}"
		newexe tlp-rdw-nm 99tlp-rdw-nm

		exeinto "${PLIB}/sleep.d"
		doexe 48tlp-rdw-lock
	fi

	return 0
}

pkg_preinst() {
	# Disable conflicting pm-utils hooks
	local hook
	for hook in ${CONFLICTING_PM_POWERHOOKS}; do
		if [[ -x "${PLIB}/power.d/${hook}" ]]; then
			ln -sf "${TLP_NOP}" "${PMETC}/power.d/${hook}" || \
				die "Failed to disable pm power hook '${hook}'."
		fi
	done
}

pkg_postrm() {
	# Remove pm-utils hook disablers
	local hook
	for hook in ${CONFLICTING_PM_POWERHOOKS}; do
		if [[ `readlink "${PMETC}/power.d/${hook}"` == "${TLIB}/power.d/${hook}" ]]; then
			rm "${PMETC}/power.d/${hook}" || \
				die "Couldn't reenable pm power hook '${hook}'."
		fi
	done
}

pkg_postinst() {
	elog "TLP is disabled by default. You have to enable TLP by setting TLP_ENABLE=1 in /etc/conf.d/tlp."
	elog "Don't forget to add /etc/init.d/tlp to your favorite runlevel."
	if use laptop-mode-tools; then
		ewarn "Reminder: don't run laptop-mode-tools and tlp at the same time."
	fi
	elog "A note for pre tlp-0.3.6 users: the ifup script has been replaced with the Radio Device Wizard. Please remove any created NetworkManager ifup dispatcher script."
	if [[ -e "${NMDSP}/02_tlp-ifup" ]]; then
		ewarn "${NMDSP}/02_tlp-ifup should be removed."
	fi
	return 0
}
