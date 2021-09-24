# Copyright 2011-2020 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

inherit eutils bash-completion-r1 linux-info systemd udev

DESCRIPTION="Advanced Power Management for Linux"
HOMEPAGE="https://linrunner.de/tlp"

if [[ "${PV}" == 9999* ]]; then
	inherit git-r3

	EGIT_REPO_URI="https://github.com/linrunner/TLP.git"
	EGIT_BRANCH="main"
	SRC_URI=""
	KEYWORDS=""

else
	if [[ "${PV}" =~ ^[0-9]+[.][0-9]+[.][0-9]+_(alpha|beta|pre|rc|p)[0-9]+$ ]]; then
		# our version:      1.2.3_beta4
		# upstream version: 1.2.3-beta.4
		MY_PV="$(ver_rs 3 - 4 .)"
	else
		MY_PV="${PV}"
	fi

	SRC_URI="https://github.com/linrunner/TLP/archive/${MY_PV}.tar.gz -> ${P}.tar.gz"
	S="${WORKDIR}/${PN^^}-${MY_PV}"
	KEYWORDS="~amd64 ~x86"

	# ebuild in overlay, no point in trying to access mirrored files
	RESTRICT="mirror"
fi

MY_README_URI="https://github.com/dywisor/tlp-portage/blob/maint/README.rst"

LICENSE="GPL-2+ tpacpi-bundled? ( GPL-3+ )"
SLOT="0"
IUSE="+tlp-suggests rdw +tpacpi-bundled bluetooth pm-utils"

_OPTIONAL_RDEPEND="
	sys-apps/smartmontools
	sys-apps/ethtool
	sys-apps/lsb-release
	|| ( sys-power/linux-x86-power-tools sys-apps/linux-misc-apps )
"
DEPEND=""
RDEPEND="
	virtual/udev
	sys-apps/util-linux
	sys-apps/hdparm
	dev-lang/perl sys-apps/usbutils sys-apps/pciutils
	|| ( >=sys-apps/util-linux-2.31_rc1 net-wireless/rfkill )
	|| ( net-wireless/iw net-wireless/wireless-tools )

	rdw?                ( net-misc/networkmanager )
	tlp-suggests?       ( ${_OPTIONAL_RDEPEND} )
	bluetooth?          ( sys-apps/dbus net-wireless/bluez )
	pm-utils?           ( sys-power/pm-utils )
"

pkg_pretend() {
	use tpacpi-bundled || ewarn "USE=-tpacpi-bundled: unsupported"
	use pm-utils && ewarn "USE=pm-utils: unsupported"
}

pkg_setup() {
	CONFIG_CHECK="~POWER_SUPPLY"

	CONFIG_CHECK+=" ~PM"
	ERROR_PM="PM is required for USB/PCI(e) autosuspend"
	CONFIG_CHECK+=" ~ACPI_AC"
	CONFIG_CHECK+=" ~DMIID"
	ERROR_DMIID="DMIID is required by tlp-stat and tpacpi-bat"
	CONFIG_CHECK+=" ~SENSORS_CORETEMP"
	ERROR_SENSORS_CORETEMP="coretemp module is used by tlp-stat"

	# transient kconfig recommendation (from sys-power/linux-x86-power-tools)
	CONFIG_CHECK+=" ~X86_MSR"
	ERROR_X86_MSR="msr module is required by x86_energy_perf_policy"

	linux-info_pkg_setup
}

tlp_emake() {
	# TLP_CONF == TLP_CONFUSR
	emake \
		TLP_ULIB="$(get_udevdir)" \
		TLP_SYSD="$(systemd_get_systemunitdir)" \
		TLP_SDSL="$(systemd_get_utildir)/system-sleep" \
		TLP_ELOD="/$(get_libdir)/elogind/system-sleep" \
		TLP_SHCPL="$(get_bashcompdir)" \
		TLP_CONF="/etc/tlp.conf" \
		\
		TLP_NO_INIT=1 \
		$(usex pm-utils TLP_WITH_SYSTEMD={0,1}) \
		$(usex pm-utils TLP_WITH_ELOGIND={0,1}) \
		$(usex tpacpi-bundled TLP_NO_TPACPI={0,1}) \
		$(usex tpacpi-bundled "" TPACPIBAT="tpacpi-bat") \
		\
		"${@}"
}

src_compile() {
	tlp_emake
}

src_install() {
	tlp_emake DESTDIR="${D}" \
		install-tlp install-man $(usex rdw install-rdw "")

	## init/service file(s)
	newinitd "${FILESDIR}/tlp-init.openrc-r3" "${PN}"

	## extra configuration
	insinto /etc/tlp.d
	newins "${FILESDIR}/gentoo.conf" "01-gentoo.conf"

	# /var/lib/tlp should exist
	keepdir /var/lib/tlp

	## doc
	dodoc README.rst changelog

	## pm-utils (deprecated / unsupported)
	if use pm-utils; then
		## sleep/resume hook
		insinto /usr/lib/pm-utils/sleep.d
		doins "${FILESDIR}/49tlp"

		## pm hook blacklist
		insinto /etc/pm/config.d
		newins "${FILESDIR}/pm-blacklist.0" tlp
	fi
}

pkg_postinst() {
	## postinst messages
	if [[ -z "${REPLACING_VERSIONS}" ]]; then
		elog "TLP is disabled by default."
		elog "Refer to ${MY_README_URI} for setup instructions."
	fi
}
