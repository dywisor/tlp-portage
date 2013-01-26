# Copyright 1999-2013 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: $

EAPI=5

inherit base eutils bash-completion-r1 git-2 linux-info

EGIT_REPO_URI='git://github.com/linrunner/TLP.git'

_ADDITIONS_STABLE_PVR="0.3.7.901-r3"

_ADDITIONS_PVR="${PVR}"
_MY_KEYWORDS="~x86 ~amd64"
case "${PV}" in
	9999*)
		EGIT_BRANCH="devel"

		# use last known stable additions. this may or may not work
		# Possible risks:
		# * Makefile.gentoo may be out of date
		#    => silently skips installation of required files
		# * ...
		_ADDITIONS_PVR="${_ADDITIONS_STABLE_PVR}"
		_MY_KEYWORDS=""
	;;
	0.3.7.901*)
		# devel version with well-defined additions tarball
		EGIT_BRANCH="devel"
		_MY_KEYWORDS=""

		case "${PV#0.3.7.901_pre}" in
			20130103)
				_ADDITIONS_PVR="0.3.7.901"
				EGIT_COMMIT='e04565023dec4bc0142a0b87ac498ed0a94b91a6'
			;;
			20130120)
				EGIT_COMMIT='9ec6cf72ee370559e60b0f1eed6ad6add5acffc5'
				_ADDITIONS_PVR="${_ADDITIONS_STABLE_PVR}"
			;;
			20130126)
				EGIT_COMMIT='a5b7a0bf72d3e4a5fb81e9ea1d181c6f86c7b466'
				_ADDITIONS_PVR="${_ADDITIONS_STABLE_PVR}"
			;;
			*)
				die "unknown pre-release version ${PV#0.3.7.901_pre} (${PV})."
			;;
		esac
	;;
esac

SRC_URI="http://dreliam.de/tlp/gentoo/tlp-gentoo-additions-${_ADDITIONS_PVR}.tar.bz2"
RESTRICT="mirror"

IUSE="tlp_suggests rdw +perl +openrc systemd bash-completion laptop-mode-tools tpacpi-bundled"
REQUIRED_USE="
	tlp_suggests?   ( perl )
	tpacpi-bundled? ( perl )
	|| ( openrc systemd )
"

DESCRIPTION="Power-Management made easy, designed for Thinkpads."
HOMEPAGE="http://linrunner.de/en/tlp/tlp.html"

LICENSE="GPL-2 tpacpi-bundled? ( GPL-3 )"
SLOT="0"
KEYWORDS="${_MY_KEYWORDS}"

_PKG_TPACPI='app-laptop/tpacpi-bat'
_PKG_TPSMAPI='app-laptop/tp_smapi'
_PKG_ACPICALL='sys-power/acpi_call'
_OPTIONAL_DEPEND='
	sys-apps/smartmontools
	sys-apps/ethtool
	sys-apps/lsb-release
'

DEPEND=""
RDEPEND="${DEPEND:-}
	sys-apps/hdparm

	sys-power/upower
	sys-power/pm-utils
	virtual/udev

	net-wireless/wireless-tools
	net-wireless/rfkill

	perl?               ( dev-lang/perl sys-apps/usbutils )
	rdw?                ( net-misc/networkmanager )
	tlp_suggests?       ( ${_OPTIONAL_DEPEND} )
	!laptop-mode-tools? ( !app-laptop/laptop-mode-tools )
"

# pm hooks to disable defined by upstream
#
# hooks that have a different name in gentoo:
#  * <none>
#
CONFLICTING_PM_POWERHOOKS_UPSTREAM="95hdparm-apm disable_wol hal-cd-polling
intel-audio-powersave harddrive laptop-mode journal-commit pci_devices
pcie_aspm readahead sata_alpm sched-powersave usb_bluetooth wireless
xfs_buffer"

CONFLICTING_PM_POWERHOOKS="${CONFLICTING_PM_POWERHOOKS_UPSTREAM}"

pkg_setup() {
	if use kernel_linux; then
		linux-info_pkg_setup
		einfo "${P} now uses the DMI sysfs interface (CONFIG_DMIID) instead of sys-apps/dmidecode."
		if ! linux_config_exists || ! linux_chkconfig_present DMIID; then
			ewarn "CONFID_DMIID should be enabled."
		fi
	fi
}

src_prepare() {

	# these patches are now included upstream (tlp-0.3.7.901_pre20130120 and
	# later)
	case "${PV}" in
		0.3.7.901_pre201301[01]?|0.3.7.1)
			PATCHES+=(
				"${FILESDIR}/tlp-usblist-print-unknown-if-device-desc-is-empty.patch"
				"${FILESDIR}/tlp-stat-do-not-set-needs_root_priv-0-directly.patch"
			)
		;;
		0.3.7.901_pre20130126)
			PATCHES+=(
				"${FILESDIR}/tlp-functions-fix-get_wifi_ifaces.patch"
			)
		;;
	esac
	base_src_prepare
	chmod u+x "${WORKDIR}/gentoo/tlp_configure.sh" || die "chmod configure"
	ln -fs "${WORKDIR}/gentoo/tlp_configure.sh" "${S}/configure" || die "ln configure"
}

src_configure() {
	# econf is not supported and TLP is noarch, use ./configure directly
	./configure --quiet --src="${S}" --target=gentoo $(use_with tpacpi-bundled)
}

src_install() {
	_tlp_usex() { use "${1}" && echo "TLP_NO_${2:-${1^^}}=1"; }

	# TLP_NO_TPACPI: do not install the bundled tpacpi-bat file
	#                 TLP expects to find tpacpi-bat at /usr/sbin/tpacpi-bat
	# LIBDIR:        use proper libary dir names instead of relying on a
	#                 lib->lib64 symlink on amd64 systems
	emake -f "${WORKDIR}/gentoo/Makefile.gentoo" \
		$(_tlp_usex !perl USB) \
		$(_tlp_usex !tpacpi-bundled TPACPI) \
		TLP_NO_INITD=1 TLP_NO_BASHCOMP=1 TLP_NO_CONFIG=1 \
		DESTDIR="${D}" LIBDIR=$(get_libdir) \
		install-tlp $(usex rdw install-rdw "")

	if use bash-completion; then
		newbashcomp "tlp.bash_completion" "${PN}"
	fi

	# tlp config file
	if [[ "${PV}" == 9999* ]]; then
		# use default config, but set TLP_ENABLE to 0 (unsafe edit)
		sed 's,TLP_ENABLE=1,TLP_ENABLE=0,' -i default || die "sed TLP_ENABLE=0"
		newconfd default ${PN}
	else
		# use config from the additions tarball
		newconfd "${WORKDIR}/gentoo/tlp.conf" ${PN}
	fi

	# init file(s)
	use openrc && newinitd "${WORKDIR}/gentoo/tlp-init.openrc" ${PN}

	if use systemd; then
		insinto /etc/systemd/system
		# tlp-init.service has been renamed to tlp.service
		# as of tlp-0.3.7.901_pre20130120
		case "${PV}" in
			0.3.7.901_pre201301[01]?|0.3.7.1)
				doins tlp-init.service
			;;
			*)
				doins tlp.service
			;;
		esac
	fi

	# man, doc
	doman man/?*.?*
	dodoc README*

	# Disable conflicting pm-utils hooks
	#  Has been moved back in pkg_*() as of tlp-0.3.7.901_pre20130120.
	#
	case "${PV}" in
		0.3.7.901_pre201301[01]?|0.3.7.1)
			local TLP_NOP="/usr/$(get_libdir)/${PN}-pm/${PN}-nop" hook
			for hook in ${CONFLICTING_PM_POWERHOOKS?}; do
				dosym "${TLP_NOP}" "/etc/pm/power.d/${hook}"
			done
		;;
	esac
}

pkg_postrm() {
	case "${PV}" in
		0.3.7.901_pre201301[01]?)
			:
		;;
		*.9[0-9][0-9]*|9999*)
			local \
				TLP_NOP="${ROOT%/}/usr/$(get_libdir)/${PN}-pm/${PN}-nop" \
				POWER_D="${ROOT%/}/etc/pm/power.d" \
				hook hook_name

			einfo "Re-enabling power hooks in ${POWER_D} that link to ${TLP_NOP}"
			for hook_name in ${CONFLICTING_PM_POWERHOOKS?}; do
				hook="${POWER_D}/${hook_name}"

				if [[
					( -L "${hook}" ) &&
					( `readlink "${hook}"` == "${TLP_NOP}" )
				]]; then
					rm "${hook}" || die "cannot reenable hook ${hook_name}."
				fi
			done
			# cannot know whether POWER_D existed before installing
			# TLP or not
#			rmdir --ignore-fail-on-non-empty -- "${POWER_D}" || \
#				die "rmdir ${POWER_D} returned $?."
		;;
	esac
}

pkg_postinst() {
	case "${PV}" in
		0.3.7.901_pre201301[01]?)
			einfo "You're using a development version of ${PN}."
		;;
		*.9[0-9][0-9]*|9999*)
			einfo "You're using a development version of ${PN}."

			# Disable conflicting pm-utils hooks
			local \
				TLP_NOP="${ROOT%/}/usr/$(get_libdir)/${PN}-pm/${PN}-nop" \
				POWER_D="${ROOT%/}/etc/pm/power.d" \
				hook_name

			einfo "Disabling conflicting power hooks in ${POWER_D}"
			[[ -e "${POWER_D}" ]] || mkdir "${POWER_D}" || \
				die "mkdir ${POWER_D} returned $?."
			for hook_name in ${CONFLICTING_PM_POWERHOOKS?}; do
				if [[ ! -e "${POWER_D}/${hook_name}" ]]; then
					ln -s -- "${TLP_NOP}" "${POWER_D}/${hook_name}" || \
						die "cannot disable power.d hook ${hook_name}."
				fi
			done
		;;
	esac

	elog "${PN^^} is disabled by default. You have to enable ${PN^^} by setting ${PN^^}_ENABLE=1 in /etc/conf.d/${PN}."
	if use openrc; then
		elog "Don't forget to add /etc/init.d/${PN} to your favorite runlevel."
	fi

	if use systemd; then
		ewarn "USE=systemd is unsupported."
		elog  "A service file has been installed to /etc/systemd/system/${PN}-init.service."
	fi

	if ! use tlp_suggests; then
		local p
		elog "In order to get full functionality, the following packages should be installed:"
		for p in ${_OPTIONAL_DEPEND?}; do
			elog "- ${p}"
		done
	fi

	elog "For battery charge threshold control,"
	elog "one or more of the following packages are required:"
	if use kernel_linux; then
		elog "- ${_PKG_TPSMAPI?} - for Thinkpads up to Core 2 (and Sandy Bridge partially)"
		if use tpacpi-bundled; then
			elog "- ${_PKG_ACPICALL?} - kernel module for Sandy Bridge Thinkpads (this includes Ivy Bridge ones as well)"
		else
			elog "- ${_PKG_TPACPI?} - for Sandy Bridge Thinkpads (this includes Ivy Bridge ones as well)"
		fi
	else
		ewarn "No package suggestions available due to USE=-kernel_linux"
	fi

	if ! use perl; then
		einfo "The tlp-usblist script has not been installed due to USE=-perl."
	fi

	if use laptop-mode-tools; then
		ewarn "Reminder: don't run laptop-mode-tools and ${PN} at the same time."
	fi
}
