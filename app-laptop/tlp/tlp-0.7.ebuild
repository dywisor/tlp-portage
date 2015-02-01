# Copyright 1999-2015 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: $

EAPI=5

inherit eutils bash-completion-r1 linux-info systemd

DESCRIPTION="Advanced Power Management for Linux"
HOMEPAGE="http://linrunner.de/tlp"

SRC_URI="
	https://github.com/linrunner/TLP/archive/${PV}.tar.gz -> ${P}.tar.gz
	http://erdmann.es/dywi/dl/tlp/tlp-gentoo-patches-${PV}.tar.xz
"
S="${WORKDIR}/${PN^^}-${PV}"
KEYWORDS="~amd64 ~x86"

MY_README_URI="https://github.com/dywisor/tlp-portage/blob/maint/README.rst"
MY_CONFFILE="/etc/tlp.conf"

# ebuild in overlay, no point in trying to access mirrored files
RESTRICT="mirror"

LICENSE="GPL-2+ tpacpi-bundled? ( GPL-3+ )"
SLOT="0"
KEYWORDS="~x86 ~amd64"
IUSE="tlp_suggests rdw laptop-mode-tools +tpacpi-bundled +pm-utils bluetooth deprecated"

_OPTIONAL_RDEPEND="
	sys-apps/smartmontools
	sys-apps/ethtool
	sys-apps/lsb-release
"
DEPEND=""
RDEPEND="
	virtual/udev
	sys-apps/util-linux
	sys-apps/hdparm
	dev-lang/perl sys-apps/usbutils sys-apps/pciutils
	pm-utils?  ( sys-power/pm-utils )
	!pm-utils? ( sys-apps/systemd )
	net-wireless/rfkill
	|| ( net-wireless/iw net-wireless/wireless-tools )
	|| ( sys-power/linux-x86-power-tools sys-apps/linux-misc-apps )

	rdw?                ( net-misc/networkmanager )
	tlp_suggests?       ( ${_OPTIONAL_RDEPEND} )
	bluetooth?          ( sys-apps/dbus net-wireless/bluez )
	deprecated?         ( sys-power/acpid )
	!laptop-mode-tools? ( !app-laptop/laptop-mode-tools )
"

pkg_pretend() {
	CONFIG_CHECK="~POWER_SUPPLY"

	CONFIG_CHECK+=" ~ACPI_AC"
	CONFIG_CHECK+=" ~DMIID"
	ERROR_DMIID="DMIID is required by tlp-stat and tpacpi-bat"
	CONFIG_CHECK+=" ~SENSORS_CORETEMP"
	ERROR_SENSORS_CORETEMP="coretemp module is used by tlp-stat"

	# transient kconfig recommendation (from sys-power/linux-x86-power-tools)
	CONFIG_CHECK+=" ~X86_MSR"
	ERROR_X86_MSR="msr module is required by x86_energy_perf_policy"

	if use deprecated; then
		CONFIG_CHECK+=" ~ACPI_PROC_EVENT"
		ERROR_ACPI_PROC_EVENT='ACPI_PROC_EVENT is required by thinkpad-radiosw'
	fi

	check_extra_config
}

pkg_setup() { :; }

src_prepare() {
	local -a PATCHES=()
	local PDIR="${WORKDIR}/patches"

	PATCHES+=( "${PDIR}/0001-gentoo-base.patch" )

	use deprecated     || PATCHES+=( "${PDIR}/0002-no-radiosw.patch" )
	use tpacpi-bundled || \
		PATCHES+=( "${PDIR}/0003-unbundle-tpacpi-bat.patch" )

	epatch "${PATCHES[@]}"

	cp "${FILESDIR}/${PN}-init.openrc-r1" "${S}/tlp.openrc" || die
	if ! use deprecated; then
		sed -r -e '/USE=deprecated/,+2d' -i "${S}/tlp.openrc" || die
	fi

	epatch_user
}

src_install() {
	emake DESTDIR="${ED}" \
		TLP_LIBDIR="/usr/$(get_libdir)" \
		TLP_SYSD="$(systemd_get_unitdir)" \
		TLP_CONF="${MY_CONFFILE}" \
		TLP_NO_INIT=1 TLP_NO_BASHCOMP=1 TLP_WITH_SYSTEMD=1 \
		$(usex tpacpi-bundled TLP_NO_TPACPI={0,1}) \
		$(usex pm-utils TLP_NO_PMUTILS={0,1}) \
		install-tlp $(usex rdw install-rdw "")

	## init/service file(s)
	newinitd tlp.openrc "${PN}"

	## bashcomp
	newbashcomp "${PN}.bash_completion" "${PN}"

	## man, doc
	doman man/?*.?*
	## repoman false positive: COPYING
	##  specifies which files are covered by which license
	dodoc README AUTHORS COPYING changelog

	## pm hook blacklist
	# always install this file,
	# otherwise a blocker on pm-utils would be necessary
	insinto /etc/pm/config.d
	newins "${FILESDIR}/pm-blacklist.0" tlp
}

# tlp_try_copymove_file ( old_file, new_file )
#
#  very verbose hardlink||copy old_file->new_file function
#
tlp_try_copymove_file() {
	[[ ( -n "${1-}" ) && ( -n "${2-}" ) ]] || die "bad usage"
	local word

	# hardlink or copy old_file->new_file (hardlink preferred) if all
	# of the following conditions are met:
	#
	# * new_file does not exist (not exists := ( ! -e _ && ! -h _ )
	# * old_file exists and is a file
	#
	# the checks/actions are racy,
	#  e.g. if the user edits old_file while updating $PN
	#
	if [[ ( -e "${2}" ) || ( -h "${2}" ) ]]; then
		elog "${2} exists - nothing to do."

	elif [[ -h "${1}" ]]; then
		ewarn "${1} is a symlink - cannot move files (manual update required)."

	elif [[ ! -e "${1}" ]]; then
		elog "${1} does not exist - no action required."

	elif [[ ! -f "${1}" ]]; then
		ewarn "${1} is not a file - manual update required."

	elif {
		word=
		{ ln -- "${1}" "${2}" && word=hardlinked; } || \
		{ cp -- "${1}" "${2}" && word=copied; }
	} 2>/dev/null; then
		elog "${1} has been ${word:-%UNDEFINED%} to ${2}"
		elog "Remove ${1} manually after reviewing changes."

	else
		ewarn "could copy config file to its new location - manual update required."
	fi
}

pkg_preinst() {
	local repl_pvr oldcfg newcfg word

	for repl_pvr in ${REPLACING_VERSIONS-}; do
		case "${repl_pvr}" in
			0.[34]|0.[34].*|0.5|*9999)
				# *9999: can't decide whether move is necessary or not, just try it
				oldcfg="/etc/conf.d/tlp"
				newcfg="${MY_CONFFILE}"

				ewarn "Beginning with ${PN}-0.5-r1, the config file location"
				ewarn "has been changed to ${newcfg} (from ${oldcfg})."
				ewarn "The ebuild tries to handle this automatically."

				tlp_try_copymove_file "${EROOT%/}${oldcfg}" "${EROOT%/}${newcfg}"

				# do not repeat tlp_try_copymove_file()
				# ($REPLACING_VERSIONS _could_ contain more than one $repl_pvr)
				break
			;;
		esac
	done
}

pkg_postinst() {
	## postinst messages
	elog "${PN^^} is disabled by default."
	elog "Refer to ${MY_README_URI} for setup instructions."

	if ! use tlp_suggests; then
		local pkg
		einfo "In order to get full functionality, the following packages should be installed:"
		for pkg in ${_OPTIONAL_RDEPEND?}; do
			if has_version "${pkg}"; then
				einfo "- ${pkg} (already installed)"
			else
				einfo "- ${pkg}"
			fi
		done
	fi

	! use laptop-mode-tools || ewarn \
		"Reminder: don't run laptop-mode-tools and ${PN} at the same time."

	use tpacpi-bundled || ewarn \
		"USE=-tpacpi-bundled: do not report bugs about tpacpi-bat upstream."
}
