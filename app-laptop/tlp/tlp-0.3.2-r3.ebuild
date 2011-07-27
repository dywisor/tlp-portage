# Copyright 1999-2011 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: $

# The EAPI variable tells the ebuild format in use.
# It is suggested that you the latest EAPI approved by the Council.
EAPI=4

inherit eutils bash-completion

DESCRIPTION="Power-Management made easy, designed for Thinkpads."
HOMEPAGE="https://github.com/linrunner/TLP"
SRC_URI="https://github.com/downloads/dywisor/tlp-gentoo/${PF}-gentoo.tgz"
LICENSE="GPL-2"

KEYWORDS="~amd64 ~x86"
SLOT="0"
IUSE="+X +thinkpad -acpi-hook -bash-completion -smartmontools -ethtool -laptop-mode-tools -networkmanager"

RESTRICT="mirror"

DEPEND=""
RDEPEND=" sys-apps/hdparm
net-wireless/wireless-tools
net-wireless/rfkill
sys-apps/dmidecode
acpi-hook? ( sys-power/acpid sys-power/pm-utils )
!acpi-hook? ( sys-power/upower )
thinkpad?  ( app-laptop/tp_smapi )
smartmontools? ( sys-apps/smartmontools )
ethtool? ( sys-apps/ethtool )
networkmanager? ( net-misc/networkmanager )
!laptop-mode-tools? ( !app-laptop/laptop-mode-tools )"

# pm hooks to disable defined by upstream
# (http://thinkpad-wiki.org/TLP_Programmdokumentation)
#
# hook definitions that have a different name in gentoo:
#  * 95hdparm-apm -> harddrive
#
_UPSTREAM_CONFLICTING_PMHOOKS="disable_wol hal-cd-polling
intel-audio-powersave journal-commit pcie_aspm laptop-mode
sata_alpm sched-powersave wireless xfs_buffer 95hdparm-apm"

# pm hooks to disable
_CONFLICTING_PMHOOKS="${_UPSTREAM_CONFLICTING_PMHOOKS} harddrive"

# networkmanager dispatcher.d/ script
_NM_DIS_DIR="/etc/NetworkManager/dispatcher.d"
_NM_DIS_NAME="02_tlp-ifup"

# tlp lib dir
_LIB="/usr/lib/tlp-pm"
_SHARE="/usr/share/tlp-pm"

src_configure() {
	if use networkmanager; then
		gentoo/ifup_assistant.pl "nm" ./tlp-ifup > "${T}/${_NM_DIS_NAME}" || die "ifup_assistant.pl failed."
	fi
}

src_compile() { return 0; }

src_install() {
	dosbin tlp || die

	dobashcompletion "tlp.bash_completion" ${PN}

	newbin tlp-rf bluetooth || die
	ln -f "${D}/usr/bin/bluetooth" "${D}/usr/bin/wifi" || die
	ln -f "${D}/usr/bin/bluetooth" "${D}/usr/bin/wwan" || die

	newbin tlp-run-on run-on-ac || die
	ln -f "${D}/usr/bin/run-on-ac" "${D}/usr/bin/run-on-bat" || die

	# tlp-stat requires root priv; sbin here <-> bin Makefile
	dosbin tlp-stat || die

	dodoc README || die
	dodoc gentoo/README.gentoo || die

	if [[ -d man ]];then
		local m
		for m in man/* ; do
			doman "$m" || die
		done
	fi

	insinto "$_LIB"
	doins tlp-functions tlp-rf-func tlp-nop || die
	exeinto "$_LIB"
	doexe gentoo/ifup_assistant.pl || die

	insinto "$_SHARE"
	doins tlp-ifup || die

	if use networkmanager; then
		exeinto "$_NM_DIS_DIR"
		doexe "${T}/${_NM_DIS_NAME}" || die
	fi

	doconfd conf/tlp || die

	exeinto /usr/lib/pm-utils/sleep.d
	doexe 49bay 49wwan || die

	if use acpi-hook; then
		newinitd gentoo/acpi_hook/init-tlp tlp || die

		insinto /etc/acpi/events
		doins gentoo/acpi_hook/99-zztlp || die

		exeinto /etc/acpi/actions
		doexe gentoo/acpi_hook/zztlp-acpi.sh || die
	else
		# upstream pm handling implementation,
		#  relies on external pm triggers (via upower/dbus,..)
		newinitd gentoo/std_pm/init-tlp tlp || die

		exeinto /usr/lib/pm-utils/power.d
		doexe gentoo/std_pm/zztlp || die
	fi

	if use X; then
		insinto /etc/xdg/autostart
		doins tlp.desktop || die
	fi

	insinto /usr/share/eselect/modules
	newins gentoo/eselect-tlp tlp.eselect || die
	return 0
}

pkg_postinst() {
	elog "You have to enable TLP by setting TLP_ENABLE=1 in /etc/conf.d/tlp."
	elog "If you want to enable and start TLP now, run 'eselect tlp enable'."
	elog "Don't forget to add /etc/init.d/tlp to your favorite runlevel."
	if use laptop-mode-tools; then
		ewarn "Reminder: don't run laptop-mode-tools and tlp at the same time."
	fi
	if use acpi-hook; then
		ewarn "Keep in mind that the acpid-hook is *not* supported by upstream."
		elog  "To apply the acpid rule now, make sure that acpid is started on init and run '/etc/init.d/acpid reload'."
	fi
	if ! use networkmanager; then
		ewarn "The ifup script has been installed into ${_SHARE}. 'eselect tlp net' may help you to set it up."
	fi
	bash-completion_pkg_postinst
	return 0
}

pkg_preinst() {
	# Disable conflicting pm-utils hooks
	local hook
	for hook in $_CONFLICTING_PMHOOKS; do
	if [[ -x "/usr/lib/pm-utils/power.d/${hook}" ]];then
		ln -sf /usr/lib/tlp-pm/tlp-nop /etc/pm/power.d/$i || die "Failed to disable ${hook}."
	fi
	done
	return 0
}

pkg_postrm() {
	# Remove pm-utils hook disablers
	local hook
	for hook in $_CONFLICTING_PMHOOKS; do
		if [[ x`readlink "/etc/pm/power.d/${hook}"` = "x/usr/lib/tlp-pm/tlp-nop" ]];then
			rm "/etc/pm/power.d/${hook}" || die "Couldn't reenable ${hook}."
		fi
	done
	return 0
}
