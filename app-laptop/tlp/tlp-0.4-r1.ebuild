# Copyright 1999-2013 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: $

EAPI=5

inherit base eutils bash-completion-r1 git-r3 linux-info systemd

DESCRIPTION="Power-Management made easy, designed for Thinkpads."
HOMEPAGE="http://linrunner.de/en/tlp/tlp.html"

EGIT_REPO_URI='git://github.com/linrunner/TLP.git'
EGIT_BRANCH='master'
EGIT_COMMIT="${PV}"

SRC_URI="http://git.erdmann.es/trac/dywi_tlp-gentoo-additions/downloads/tlp-gentoo-additions-${PV}.tar.bz2"
RESTRICT="mirror"

LICENSE="GPL-2+ tpacpi-bundled? ( GPL-3 )"
SLOT="0"
KEYWORDS="~x86 ~amd64"
IUSE="tlp_suggests rdw laptop-mode-tools +tpacpi-bundled +pm-utils"

_PKG_TPACPI='>app-laptop/tpacpi-bat-1.0'
_PKG_TPSMAPI='app-laptop/tp_smapi'
_PKG_ACPICALL='sys-power/acpi_call'
_OPTIONAL_DEPEND='
	sys-apps/smartmontools
	sys-apps/ethtool
	sys-apps/lsb-release
'

DEPEND=""
RDEPEND="${DEPEND-}
	sys-apps/hdparm

	pm-utils?  ( sys-power/pm-utils )
	!pm-utils? ( sys-apps/systemd )
	sys-power/acpid
	virtual/udev

	dev-lang/perl
	sys-apps/usbutils
	sys-apps/pciutils

	|| ( net-wireless/iw net-wireless/wireless-tools )
	net-wireless/rfkill

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

CONFIG_CHECK='~DMIID ~ACPI_PROC_EVENT ~POWER_SUPPLY ~ACPI_AC'
ERROR_DMIID='DMIID is required by tlp-stat and tpacpi-bat'
ERROR_ACPI_PROC_EVENT='ACPI_PROC_EVENT is required by thinkpad-radiosw'

src_unpack() {
	git-r3_src_unpack
	base_src_unpack
}

src_prepare() {
	local sed_expr

	PATCHES=(
		"${WORKDIR}/gentoo/"{49tlp,Makefile}.patch
		"${FILESDIR}/fix-run-on-ac-bat.patch"
	)
	cat "${WORKDIR}/gentoo/default.append" >> "${S}/default" || die

	sed_expr='s@^(\s*TLP_ENABLE=)[01]$@\10@'
	sed -r -e "${sed_expr}" -i "${S}/default" || die "sed failed (TLP_ENABLE=0)"
	base_src_prepare

	if ! use pm-utils; then
		sed -r -e '/install.*(PLIB|PMETC)/d' -i "${S}/Makefile" || die "sed Makefile"
	fi

	# edit version
	sed_expr="s@^(readonly TLPVER=[\"]?)(0[.]4)([\"]?)\s*\$@\1${PVR}\3@"
	sed -r -e "${sed_expr}" -i "${S}/tlp-functions" || die "sed tlp-functions"

	chmod u+x "${WORKDIR}/gentoo/tlp_configure.sh" && \
	ln -fs "${WORKDIR}/gentoo/tlp_configure.sh" "${S}/configure" || \
		die "cannot setup configure script!"
}

src_configure() {
	# econf is not supported and TLP is noarch, use ./configure directly
	./configure --quiet --src="${S}" \
		--target=gentoo $(use_with tpacpi-bundled) || die "configure failed ($?)"
}

src_compile() { return 0; }

src_install() {
	# TLP_NO_TPACPI: do not install the bundled tpacpi-bat file
	#                 TLP expects to find tpacpi-bat at /usr/sbin/tpacpi-bat
	# LIBDIR:        use proper libary dir names instead of relying on a
	#                 lib->lib64 symlink on amd64 systems
	emake	DESTDIR="${ED}" LIBDIR=$(get_libdir) \
		CONFFILE="${ED}etc/conf.d/${PN}" \
		$(usex tpacpi-bundled "" TLP_NO_TPACPI=1) \
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
	local \
		TLP_NOP="${EROOT%/}/usr/$(get_libdir)/${PN}-pm/${PN}-nop" \
		POWER_D="${EROOT%/}/etc/pm/power.d" \
		hook hook_name

	einfo "Re-enabling power hooks in ${POWER_D} that link to ${TLP_NOP}"
	for hook_name in ${CONFLICTING_PM_POWERHOOKS?}; do
		hook="${POWER_D}/${hook_name}"

		if \
			[[ ( -L "${hook}" ) && ( "$(readlink "${hook}")" == "${TLP_NOP}" ) ]]
		then
			rm "${hook}" || die "cannot reenable hook ${hook_name}."
		fi
	done
}

pkg_postinst() {
	## Disable conflicting pm-utils hooks
	# always disable hooks even if USE=-pm-utils
	# Otherwise a blocker on sys-power/pm-utils would be necessary
	#
	local \
		TLP_NOP="${EROOT%/}/usr/$(get_libdir)/${PN}-pm/${PN}-nop" \
		POWER_D="${EROOT%/}/etc/pm/power.d" \
		iter

	einfo "Disabling conflicting power hooks in ${POWER_D}"

	[[ -e "${POWER_D}" ]] || mkdir -p "${POWER_D}" || \
		die "cannot create '${POWER_D}'."

	for iter in ${CONFLICTING_PM_POWERHOOKS?}; do
		if [[ ! -e "${POWER_D}/${iter}" ]]; then
			ln -s -- "${TLP_NOP}" "${POWER_D}/${iter}" || \
				die "cannot disable power.d hook ${iter}."
		fi
	done

	## postinst messages

	elog "${PN^^} is disabled by default."
	elog "You have to enable ${PN^^} by setting ${PN^^}_ENABLE=1 in /etc/conf.d/${PN}."

	ewarn "Using ${PN^^} with systemd is unsupported."
	elog	"systemd users should enable ${PN^^} by running"
	for iter in "${PN}"{,-sleep}.service; do
		elog "- systemctl enable ${iter}"
	done
	elog "Others (openrc et al.) should add /etc/init.d/${PN} to their favorite runlevel."

	elog "You must restart acpid after upgrading ${PN}."

	local a
	_check_installed() { has_version "${1}" && a=" (already installed)" || a=; }

	if ! use tlp_suggests; then
		local p
		elog "In order to get full functionality, the following packages should be installed:"
		for p in ${_OPTIONAL_DEPEND?}; do
			_check_installed "${p}"
			elog "- ${p}${a}"
		done
	fi

	elog "For battery charge threshold control,"
	elog "one or more of the following packages are required:"

	_check_installed "${_PKG_TPSMAPI?}"
	elog "- ${_PKG_TPSMAPI?} - for Thinkpads up to Core 2 (and Sandy Bridge partially)${a}"
	if use tpacpi-bundled; then
		_check_installed "${_PKG_ACPICALL?}"
		elog "- ${_PKG_ACPICALL?} - kernel module for Sandy Bridge Thinkpads (this includes Ivy Bridge/Haswell/... ones as well)${a}"
	else
		_check_installed "${_PKG_TPACPI?}"
		elog "- ${_PKG_TPACPI?} - for Sandy Bridge Thinkpads (this includes Ivy Bridge/Haswell/... ones as well)${a}"
	fi

	if use laptop-mode-tools; then
		ewarn "Reminder: don't run laptop-mode-tools and ${PN} at the same time."
	fi

	if ! use tpacpi-bundled; then
		ewarn "USE=-tpacpi-bundled: do not report bugs about tpacpi-bat upstream."
	fi
}
