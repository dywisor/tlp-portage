# Copyright 1999-2015 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: $

EAPI=5

EGIT_REPO_URI='git://github.com/linrunner/TLP.git'
EGIT_BRANCH='master'
EGIT_COMMIT="${PV}"

inherit eutils bash-completion-r1 git-2 linux-info systemd

DESCRIPTION="Power-Management made easy, designed for Thinkpads."
HOMEPAGE="http://linrunner.de/en/tlp/tlp.html"

SRC_URI="http://git.erdmann.es/trac/dywi_tlp-gentoo-additions/downloads/tlp-gentoo-additions-${PV}.tar.bz2"
RESTRICT="mirror"

LICENSE="GPL-2+ tpacpi-bundled? ( GPL-3+ )"
SLOT="0"
KEYWORDS="~x86 ~amd64"
IUSE="tlp_suggests rdw laptop-mode-tools +tpacpi-bundled +pm-utils"

_OPTIONAL_RDEPEND="
	sys-apps/smartmontools
	sys-apps/ethtool
	sys-apps/lsb-release
	sys-power/acpid
"
DEPEND=""
RDEPEND="
	virtual/udev
	sys-apps/hdparm
	dev-lang/perl sys-apps/usbutils sys-apps/pciutils
	pm-utils?  ( sys-power/pm-utils )
	!pm-utils? ( sys-apps/systemd )
	|| ( net-wireless/iw net-wireless/wireless-tools )
	net-wireless/rfkill

	rdw?                ( net-misc/networkmanager )
	tlp_suggests?       ( ${_OPTIONAL_RDEPEND} )
	!laptop-mode-tools? ( !app-laptop/laptop-mode-tools )
"

# pm hooks to disable defined by upstream
CONFLICTING_PM_POWERHOOKS="95hdparm-apm disable_wol hal-cd-polling
intel-audio-powersave harddrive laptop-mode journal-commit pci_devices
pcie_aspm readahead sata_alpm sched-powersave usb_bluetooth wireless
xfs_buffer"

CONFIG_CHECK='~DMIID ~ACPI_PROC_EVENT ~POWER_SUPPLY ~ACPI_AC'
ERROR_DMIID='DMIID is required by tlp-stat and tpacpi-bat'
ERROR_ACPI_PROC_EVENT='ACPI_PROC_EVENT is required by thinkpad-radiosw (linux < 3.12)'

_tlp_setup_pmutils() {
	# enable/disable hooks
	local TLP_NOP POWER_D hook hook_name

	TLP_NOP="${EPREFIX}/usr/$(get_libdir)/${PN}-pm/${PN}-nop"
	POWER_D="${EROOT%/}/etc/pm/power.d"

	case "${1-}" in
		'enable'|'reenable')
			einfo "Re-enabling power hooks in ${POWER_D} that link to ${TLP_NOP}"

			for hook_name in ${CONFLICTING_PM_POWERHOOKS?}; do
				hook="${POWER_D}/${hook_name}"
				if [[ "$(readlink "${hook}" 2>/dev/null)" == "${TLP_NOP}" ]]; then
					rm -- "${hook}" || die "cannot reenable hook ${hook_name}."
				fi
			done
		;;
		'disable')
			einfo "Disabling conflicting power hooks in ${POWER_D}"

			[[ -e "${POWER_D}" ]] || mkdir -p -- "${POWER_D}" || die
			for hook_name in ${CONFLICTING_PM_POWERHOOKS?}; do
				hook="${POWER_D}/${hook_name}"
				if [[ ( ! -e "${hook}" ) && ( ! -h "${hook}" ) ]]; then
					ln -s -- "${TLP_NOP}" "${hook}" || \
						die "cannot disable power.d hook ${hook_name}."
				fi
			done
		;;
		*)
			die "_tlp_setup_pmutils(): bad usage."
		;;
	esac
}

src_unpack() {
	git-2_src_unpack
	default
}

src_prepare() {
	epatch "${WORKDIR}/gentoo/"{systemd-compat,gentoo-base}.patch
	use tpacpi-bundled || epatch "${WORKDIR}/gentoo/gentoo-unbundle-tpacpi.patch"
	epatch_user
}

src_install() {
	emake DESTDIR="${ED}" TLP_LIBDIR="/usr/$(get_libdir)" \
		TLP_CONF=/etc/conf.d/tlp \
		TLP_NO_INIT=1 TLP_NO_BASHCOMP=1 \
		$(usex tpacpi-bundled TLP_NO_TPACPI={0,1}) \
		$(usex pm-utils TLP_NO_PMUTILS={0,1}) \
		install-tlp $(usex rdw install-rdw "")

	## init/service file(s)
	newinitd "${WORKDIR}/gentoo/${PN}-init.openrc" "${PN}"
	systemd_dounit "${PN}"{,-sleep}.service

	## bashcomp
	newbashcomp "${PN}.bash_completion" "${PN}"

	## man, doc
	doman man/?*.?*
	dodoc README*
}

pkg_postrm() {
	## Re-enable conflicting pm-utils hooks
	_tlp_setup_pmutils enable
}

pkg_postinst() {
	## Disable conflicting pm-utils hooks
	# always disable hooks even if USE=-pm-utils
	# Otherwise a blocker on sys-power/pm-utils would be necessary
	_tlp_setup_pmutils disable

	## postinst messages
	elog "${PN^^} is disabled by default."
	elog "Refer to https://github.com/dywisor/tlp-portage/blob/maint/README.rst for setup instructions."

	if ! use tlp_suggests; then
		local p a
		_check_installed() { has_version "${1}" && a=" (already installed)" || a=; }
		einfo "In order to get full functionality, the following packages should be installed:"
		for p in ${_OPTIONAL_RDEPEND?}; do
			_check_installed "${p}"
			einfo "- ${p}${a}"
		done
	fi

	! use laptop-mode-tools || ewarn \
		"Reminder: don't run laptop-mode-tools and ${PN} at the same time."

	use tpacpi-bundled || ewarn \
		"USE=-tpacpi-bundled: do not report bugs about tpacpi-bat upstream."
}
