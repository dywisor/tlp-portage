# Copyright 2011-2019 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=7

inherit eutils bash-completion-r1 linux-info systemd udev

DESCRIPTION="Advanced Power Management for Linux"
HOMEPAGE="https://linrunner.de/tlp"

if [[ "${PV}" == 9999* ]]; then
	inherit git-r3

	# note that this ebuild builds against 2 live repos
	EGIT_REPO_URI="https://github.com/linrunner/TLP.git"
	EGIT_BRANCH="master"
	SRC_URI=""
	KEYWORDS=""

	MY_ADDITIONS_REPO_URI="https://github.com/dywisor/tlp-gentoo-additions.git"
	MY_ADDITIONS_REMOTE_REF="refs/heads/master"

else
	SRC_URI="
		https://github.com/linrunner/TLP/archive/${PV}.tar.gz -> ${P}.tar.gz
		https://tlp-gentoo-additions.s3.amazonaws.com/tlp-gentoo-patches-${PV}.tar.xz
	"
	S="${WORKDIR}/${PN^^}-${PV}"
	KEYWORDS="~amd64 ~x86"

	# ebuild in overlay, no point in trying to access mirrored files
	RESTRICT="mirror"
fi

MY_README_URI="https://github.com/dywisor/tlp-portage/blob/maint/README.rst"
MY_CONFFILE="/etc/tlp.conf"

LICENSE="GPL-2+ tpacpi-bundled? ( GPL-3+ )"
SLOT="0"
IUSE="tlp_suggests rdw +tpacpi-bundled bluetooth pm-utils"

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
	|| ( >=sys-apps/util-linux-2.31_rc1 net-wireless/rfkill )
	|| ( net-wireless/iw net-wireless/wireless-tools )
	|| ( sys-power/linux-x86-power-tools sys-apps/linux-misc-apps )

	rdw?                ( net-misc/networkmanager )
	tlp_suggests?       ( ${_OPTIONAL_RDEPEND} )
	bluetooth?          ( sys-apps/dbus net-wireless/bluez )
	pm-utils?           ( sys-power/pm-utils )
"

pkg_pretend() {
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

	check_extra_config
}

pkg_setup() { :; }

src_unpack() {
	if [[ "${PV}" == 9999* ]]; then
		# upstream repo fetch/checkout
		git-r3_src_unpack

		# additions repo for live patching
		git-r3_fetch \
			"${MY_ADDITIONS_REPO_URI}" "${MY_ADDITIONS_REMOTE_REF}"
		git-r3_checkout \
			"${MY_ADDITIONS_REPO_URI}" "${WORKDIR}/gentoo-additions"
	else
		default
	fi
}

src_prepare() {
	if [[ "${PV}" == 9999* ]]; then
		# * relocate config file to /etc/tlp.conf (upstream: /etc/default/tlp)
		# * disable TLP by default (-- or enable init scripts in postinst...)
		# * append TLP_LOAD_MODULES config option
		# * lspci is in sbin => tlp-pcilist in sbin
		k="$(TZ=UTC date "+%Y%m%d")"
		[[ -n "${k}" ]] || die "Failed to get time stamp"
		emake -C "${WORKDIR}/gentoo-additions" \
			TLP_SRC="${S}" TLP_CONF="${MY_CONFFILE}" \
			TLP_APPENDVER="+git-${EGIT_BRANCH:-live}-${k}" \
			livepatch-base \
			$(usex tpacpi-bundled "" "livepatch-unbundle-tpacpi-bat")
	else
		local -a PATCHES=()
		local PDIR="${WORKDIR}/patches"

		PATCHES+=( "${PDIR}/0001-gentoo-base.patch" )

		use tpacpi-bundled || \
			PATCHES+=( "${PDIR}/0002-unbundle-tpacpi-bat.patch" )

		eapply "${PATCHES[@]}"
	fi

	eapply_user
}

src_compile() {
	emake \
		TLP_ULIB="$(get_udevdir)" \
		TLP_CONF="${MY_CONFFILE}"
}

src_install() {
	emake DESTDIR="${D}" \
		TLP_ULIB="$(get_udevdir)" \
		TLP_CONF="${MY_CONFFILE}" \
		TLP_SYSD="$(systemd_get_systemunitdir)" \
		TLP_ELOD="/$(get_libdir)/elogind/system-sleep" \
		TLP_SHCPL="$(get_bashcompdir)" \
		\
		TLP_NO_INIT=1 \
		$(usex pm-utils TLP_WITH_SYSTEMD={0,1}) \
		$(usex pm-utils TLP_WITH_ELOGIND={0,1}) \
		$(usex tpacpi-bundled TLP_NO_TPACPI={0,1}) \
		install-tlp install-man $(usex rdw install-rdw "")

	## init/service file(s)
	newinitd "${FILESDIR}/tlp-init.openrc-r3" "${PN}"

	# /var/lib/tlp should exist
	keepdir /var/lib/tlp

	## doc
	dodoc README.md changelog

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
	local -a pkgv
	local pkg
	local hit

	## postinst messages
	elog "${PN^^} is disabled by default."
	elog "Refer to ${MY_README_URI} for setup instructions."

	if ! use tlp_suggests; then
		elog "Optional dependencies:"
		optfeature "full functionality" "${_OPTIONAL_RDEPEND}"
	fi

	use tpacpi-bundled || ewarn \
		"USE=-tpacpi-bundled: do not report bugs about tpacpi-bat upstream."

	if use pm-utils; then
		ewarn "USE=pm-utils: please do not report bugs about pm-utils upstream."

	else
		pkgv=( 'sys-auth/elogind' 'sys-apps/systemd' )
		hit=0

		for pkg in "${pkgv[@]}"; do
			if has_version "${pkg}"; then
				hit=1
				break
			fi
		done

		if [[ ${hit} -eq 0 ]]; then
			elog "For system sleep/resume support, install one of the following packages: ${pkgv[*]} (or set USE=pm-utils, unsupported)."
		fi
	fi
}
